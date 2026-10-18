import Foundation
import CryptoKit
import Security
import LocalAuthentication
import OpenDirectory

/// Senha de sessão do macOS, autorizada pelo proprietário para o desbloqueio facial.
/// A senha fica cifrada (AES-GCM) no Chaves; a chave exige Touch ID e só vive na memória enquanto o desbloqueio está armado.
final class PasswordVault: @unchecked Sendable {
    private static let service = "com.macfaceguard.local.unlock"
    private let lock = NSLock()
    private var key: SymmetricKey?

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: account,
         kSecUseDataProtectionKeychain as String: true,
         kSecAttrSynchronizable as String: false]
    }

    var hasPassword: Bool {
        var request = query("password")
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(request as CFDictionary, nil) == errSecSuccess
    }

    var isArmed: Bool { lock.withLock { key != nil } }

    /// Confere a senha no diretório local antes de guardar; senha errada nunca é armazenada.
    static func verify(_ password: String) -> Bool {
        guard !password.isEmpty,
              let node = try? ODNode(session: ODSession.default(), name: "/Local/Default"),
              let record = try? node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
        else { return false }
        return (try? record.verifyPassword(password)) != nil
    }

    func store(_ password: String, context: LAContext) throws {
        guard Self.verify(password) else { throw GuardError.message("A senha não confere com a do usuário \(NSUserName()). Nada foi guardado.") }
        try remove()
        let fresh = SymmetricKey(size: .bits256)
        var plain = Data(password.utf8)
        defer { plain.resetBytes(in: 0..<plain.count) }
        let sealed = try AES.GCM.seal(plain, using: fresh, authenticating: Data(Self.service.utf8))
        guard let blob = sealed.combined else { throw GuardError.message("Não foi possível cifrar a senha.") }

        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                           .biometryCurrentSet, &accessError) else {
            throw GuardError.message("Não foi possível criar a proteção biométrica da chave.")
        }
        var keyItem = query("session-key")
        keyItem[kSecAttrAccessControl as String] = access
        keyItem[kSecValueData as String] = fresh.withUnsafeBytes { Data($0) }
        keyItem[kSecUseAuthenticationContext as String] = context
        var status = SecItemAdd(keyItem as CFDictionary, nil)
        guard status == errSecSuccess else { throw GuardError.message("Não foi possível guardar a chave no Chaves (\(status)).") }

        var blobItem = query("password")
        blobItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        blobItem[kSecValueData as String] = blob
        status = SecItemAdd(blobItem as CFDictionary, nil)
        guard status == errSecSuccess else {
            try? remove()
            throw GuardError.message("Não foi possível guardar a senha cifrada (\(status)).")
        }
        lock.withLock { key = fresh }
    }

    /// Lê a chave com o contexto já autenticado por Touch ID e a mantém na memória até `disarm()`.
    func arm(context: LAContext) throws {
        var request = query("session-key")
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        request[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        guard status == errSecSuccess, var data = result as? Data, data.count == 32 else {
            throw GuardError.message(status == errSecItemNotFound ? "Guarde a senha antes de armar o desbloqueio."
                                                                  : "A chave da senha não pôde ser acessada (\(status)).")
        }
        defer { data.resetBytes(in: 0..<data.count) }
        let loaded = SymmetricKey(data: data)
        // Confere que a senha abre antes de armar.
        var probe = try open(with: loaded)
        probe.resetBytes(in: 0..<probe.count)
        lock.withLock { key = loaded }
    }

    func disarm() { lock.withLock { key = nil } }

    /// Bytes UTF-8 da senha; quem chama deve zerá-los logo após o uso.
    func password() throws -> Data {
        guard let current = lock.withLock({ key }) else { throw GuardError.message("Desbloqueio desarmado.") }
        return try open(with: current)
    }

    private func open(with key: SymmetricKey) throws -> Data {
        var request = query("password")
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        guard status == errSecSuccess, let blob = result as? Data else {
            throw GuardError.message("Senha cifrada ausente (\(status)).")
        }
        do { return try AES.GCM.open(AES.GCM.SealedBox(combined: blob), using: key, authenticating: Data(Self.service.utf8)) }
        catch { throw GuardError.message("A senha cifrada não confere com a chave. Guarde a senha de novo.") }
    }

    func remove() throws {
        disarm()
        for account in ["password", "session-key"] {
            let status = SecItemDelete(query(account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw GuardError.message("Não foi possível apagar a senha do Chaves (\(status)).")
            }
        }
    }
}
