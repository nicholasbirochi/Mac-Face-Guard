import Foundation
import CryptoKit
import Security
import LocalAuthentication
import MacFaceGuardCore

enum GuardError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}

struct TemplateVault {
    private let manager = FileManager.default
    private var directory: URL {
        manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacFaceGuard/private", isDirectory: true)
    }
    /// Cadastro v1 (descritores do Vision), só lido para saber que existe; v2 é o cadastro do modelo facial.
    private var file: URL { directory.appendingPathComponent("enrollment.aesgcm") }
    private var fileV2: URL { directory.appendingPathComponent("enrollment-v2.aesgcm") }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.macfaceguard.local.template-key.v1",
         kSecAttrAccount as String: "device-template",
         kSecUseDataProtectionKeychain as String: true,
         kSecAttrSynchronizable as String: false]
    }
    var exists: Bool { hasLegacy || hasV2 }
    var hasLegacy: Bool { manager.fileExists(atPath: file.path) }
    var hasV2: Bool { manager.fileExists(atPath: fileV2.path) }

    func prepare(context: LAContext) throws {
        if try readKey(context: context) == nil {
            try addKey(SymmetricKey(size: .bits256), context: context)
        }
        guard try readKey(context: context) != nil else {
            throw GuardError.message("O Chaves não confirmou o armazenamento. A câmera não será iniciada.")
        }
    }

    func load(context: LAContext, model: FaceModelDescriptor) throws -> EnrollmentV2 {
        guard hasV2 else { throw GuardError.message("Refaça o cadastro: o cadastro antigo não usa o modelo facial.") }
        let data = try readPrivate(fileV2)
        guard let key = try readKey(context: context) else {
            throw GuardError.message("A chave local não está disponível. O cadastro não será aceito.")
        }
        do { return try EnrollmentCipherV2.open(data, key: key, model: model) }
        catch { throw GuardError.message("O cadastro não confere com o modelo instalado. Refaça o cadastro.") }
    }

    /// Grava o v2 de forma atômica; o v1 só é removido depois que o v2 foi gravado e protegido.
    func save(_ enrollment: EnrollmentV2, model: FaceModelDescriptor, context: LAContext) throws {
        try enrollment.validate(for: model)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let attributes = try manager.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw GuardError.message("O diretório privado não é válido.")
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var privateURL = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try privateURL.setResourceValues(values)
        let existingKey = try readKey(context: context)
        let key = existingKey ?? SymmetricKey(size: .bits256)
        if existingKey == nil { try addKey(key, context: context) }
        do {
            let data = try EnrollmentCipherV2.seal(enrollment, key: key, model: model)
            try data.write(to: fileV2, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileV2.path)
            var privateFile = fileV2
            try privateFile.setResourceValues(values)
        } catch {
            // A chave de um cadastro anterior é preservada se a atualização falhar.
            if existingKey == nil { SecItemDelete(query as CFDictionary) }
            throw error
        }
        // Releitura antes de apagar o v1: se o v2 não abrir, o v1 fica e o erro sobe.
        guard try EnrollmentCipherV2.open(readPrivate(fileV2), key: key, model: model) == enrollment else {
            throw GuardError.message("O novo cadastro não pôde ser conferido. O cadastro anterior foi mantido.")
        }
        if hasLegacy { try? manager.removeItem(at: file) }
    }

    private func readPrivate(_ url: URL) throws -> Data {
        let attributes = try manager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) < 1_000_000 else {
            throw GuardError.message("O cadastro local não é válido. Exclua-o e cadastre novamente.")
        }
        return try Data(contentsOf: url)
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GuardError.message("Não foi possível excluir a chave do Chaves (\(status)).")
        }
        if hasV2 { try manager.removeItem(at: fileV2) }
        if hasLegacy { try manager.removeItem(at: file) }
    }

    private func readKey(context: LAContext) throws -> SymmetricKey? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        request[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            throw GuardError.message("A chave protegida não pôde ser acessada (\(status)).")
        }
        return SymmetricKey(data: data)
    }

    private func addKey(_ key: SymmetricKey, context: LAContext) throws {
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, &accessError) else {
            throw GuardError.message("Não foi possível criar a proteção biométrica da chave.")
        }
        var item = query
        item[kSecAttrAccessControl as String] = access
        item[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        item[kSecUseAuthenticationContext as String] = context
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw GuardError.message("Não foi possível guardar a chave no Chaves (\(status)).")
        }
    }

    static func verifyKeychainProtection() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.macfaceguard.diagnostic." + UUID().uuidString,
            kSecAttrAccount as String: "synthetic-test", kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: false]
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet, nil) else { throw GuardError.message("Não foi possível criar o controle biométrico do teste.") }
        var item = query
        item[kSecAttrAccessControl as String] = access
        item[kSecValueData as String] = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let created = SecItemAdd(item as CFDictionary, nil)
        guard created == errSecSuccess else { throw GuardError.message("Teste do Chaves: criação falhou (\(created)).") }
        let unauthenticated = LAContext()
        unauthenticated.interactionNotAllowed = true
        var read = query
        read[kSecReturnData as String] = true
        read[kSecUseAuthenticationContext as String] = unauthenticated
        let result = SecItemCopyMatching(read as CFDictionary, nil)
        let removed = SecItemDelete(query as CFDictionary)
        guard removed == errSecSuccess else { throw GuardError.message("Teste do Chaves: limpeza falhou (\(removed)).") }
        guard result == errSecInteractionNotAllowed || result == errSecAuthFailed else {
            throw GuardError.message("Teste do Chaves: bloqueio de leitura não confirmado (\(result)).")
        }
    }
}
