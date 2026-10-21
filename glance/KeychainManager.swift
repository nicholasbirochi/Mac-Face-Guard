//
//  KeychainManager.swift
//  glance
//
//  Thin, password-agnostic wrapper around Keychain Services — save/read/delete/exists by account, plus a Touch-ID access control helper.
//

import Foundation
import Security
import LocalAuthentication

enum KeychainError: LocalizedError {
    case itemNotFound
    case unexpectedData
    case accessControlFailed(String)
    case authenticationFailed
    case biometryUnavailable(String)
    case osStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Item não encontrado no Chaves."
        case .unexpectedData:
            return "O item do Chaves tem um formato inesperado."
        case .accessControlFailed(let msg):
            return "Não foi possível criar a proteção do Chaves: \(msg)"
        case .authenticationFailed:
            return "O Touch ID foi cancelado ou não confirmou."
        case .biometryUnavailable(let msg):
            return msg
        case .osStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Erro do Chaves: \(message)"
        }
    }
}

enum KeychainManager {
    nonisolated static let service = "com.nicholasbirochi.glanceverde"

    /// Glance Verde: todo item vai para o Chaves de proteção de dados (o mesmo do iOS, preso a este app pelo grupo de
    /// acesso) e nunca sincroniza com o iCloud. Toda consulta parte daqui para nenhuma escapar desses dois atributos.
    nonisolated private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: false
        ]
    }

    /// Attributes-only existence check — never prompts, even for access-controlled items.
    nonisolated static func exists(account: String) -> Bool {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // Nunca mostra interface: um item protegido responde "existe" sem pedir Touch ID.
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status != errSecItemNotFound
    }

    /// Pass an `LAContext` to authorize a read on an access-controlled item — the OS presents the prompt during this call.
    nonisolated static func read(account: String, context: LAContext? = nil) throws -> Data {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if let context {
            query[kSecUseAuthenticationContext as String] = context
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw KeychainError.unexpectedData }
            return data
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        case errSecUserCanceled, errSecAuthFailed:
            // Com a tampa do MacBook fechada (ou o Touch ID bloqueado) o Chaves devolve o mesmo erro de um cancelamento.
            // Só depois da falha pergunta ao LocalAuthentication o motivo, para nunca barrar uma leitura que daria certo.
            throw biometryUnavailableError() ?? KeychainError.authenticationFailed
        default:
            throw KeychainError.osStatus(status)
        }
    }

    /// `nil` quando o Touch ID pode ser usado agora; senão, o erro com o motivo legível.
    nonisolated static func biometryUnavailableError() -> KeychainError? {
        var error: NSError?
        if LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) { return nil }
        return .biometryUnavailable(biometryUnavailableMessage(code: error?.code))
    }

    nonisolated static func biometryUnavailableMessage(code: Int?) -> String {
        switch code.flatMap(LAError.Code.init(rawValue:)) {
        case .biometryNotEnrolled?:
            return "Nenhuma digital cadastrada. Cadastre uma em Ajustes do Sistema → Touch ID e Senha."
        case .biometryLockout?:
            return "O Touch ID está bloqueado depois de várias tentativas. Bloqueie e desbloqueie o Mac com a senha, depois tente de novo."
        default:
            return "O Touch ID está indisponível agora. Com a tampa do MacBook fechada ele não funciona: abra a tampa ou use um Magic Keyboard com Touch ID."
        }
    }

    /// Stores an item, updating its data in place when it already exists. Updating
    /// avoids the delete/add gap that can race with a second submit and produce
    /// `errSecDuplicateItem`. Existing access-control attributes are preserved;
    /// this method's access-control argument applies when adding a new item.
    nonisolated static func save(account: String, data: Data, accessControl: SecAccessControl? = nil) throws {
        let itemQuery = baseQuery(account: account)

        let updateStatus = SecItemUpdate(
            itemQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            break // Add below.
        default:
            throw KeychainError.osStatus(updateStatus)
        }

        var addQuery = itemQuery
        addQuery[kSecValueData as String] = data
        if let accessControl {
            addQuery[kSecAttrAccessControl as String] = accessControl
        } else {
            // Só texto cifrado entra sem controle de acesso (o cofre da senha): precisa ser legível na tela de bloqueio,
            // onde não há como pedir Touch ID. A chave que o abre continua presa à biometria.
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess { return }
        // Another save may have added the item after our update reported
        // not-found. Complete that competing replacement with an update instead
        // of surfacing an avoidable “item already exists” error.
        if status == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(
                itemQuery as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard retryStatus == errSecSuccess else { throw KeychainError.osStatus(retryStatus) }
            return
        }
        throw KeychainError.osStatus(status)
    }

    nonisolated static func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
    }

    /// Glance Verde: só a digital cadastrada hoje abre a chave (`.biometryCurrentSet`). Sem recurso à senha do Mac — quem a
    /// conhece não precisa do app — e cadastrar ou apagar uma digital invalida a chave, exigindo recomeçar o cadastro.
    nonisolated static func makeBiometryAccessControl() throws -> SecAccessControl {
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &accessError
        ) else {
            let msg = (accessError?.takeRetainedValue() as Error?)?.localizedDescription ?? "unknown"
            throw KeychainError.accessControlFailed(msg)
        }
        return access
    }
}
