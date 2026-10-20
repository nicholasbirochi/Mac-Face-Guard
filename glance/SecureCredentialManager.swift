//
//  SecureCredentialManager.swift
//  glance
//
//  Two-tier storage on KeychainManager: a Touch-ID-gated session key (unwrapped once per launch) wraps an ungated encrypted
//  password blob, safe to read anytime — including the lock screen, where no app UI exists to host a Touch ID prompt.
//  Touch ID authorizes the session; nothing yet authorizes each individual unlock beyond that (face recognition will).
//

import Foundation
import CryptoKit
import LocalAuthentication
import OpenDirectory

enum SecureCredentialError: LocalizedError {
    case emptyPassword
    case sessionLocked
    case encryptionFailed
    case decryptionFailed
    case sessionKeyUnavailable
    case passwordMismatch

    var errorDescription: String? {
        switch self {
        case .emptyPassword:
            return "A senha não pode ficar vazia."
        case .sessionLocked:
            return "Sessão bloqueada. Confirme com o Touch ID antes de guardar ou usar a senha."
        case .encryptionFailed:
            return "A cifragem falhou."
        case .decryptionFailed:
            return "A decifragem falhou. O dado guardado pode estar corrompido ou adulterado."
        case .sessionKeyUnavailable:
            return "A chave da sessão sumiu (por exemplo, uma digital foi cadastrada ou apagada), mas ainda há dados cifrados que só ela abriria. Nada foi apagado. Remova a senha guardada na aba Senha para limpar tudo e recomeçar."
        case .passwordMismatch:
            return "A senha não confere com a do usuário \(NSUserName()) neste Mac. Nada foi guardado."
        }
    }
}

extension Notification.Name {
    /// Fires whenever the cached session key changes, so anything encrypted under it (e.g. `FaceEnrollmentStore`) can reload
    /// itself instead of relying on each call site to remember to — a past bug had the sidebar's unlock forget this, leaving
    /// face unlock silently running on stale pre-unlock data.
    static let secureCredentialSessionDidChange = Notification.Name("SecureCredentialManager.sessionDidChange")
}

enum SecureCredentialManager {
    nonisolated private static let sessionKeyAccount = "sessionKey"
    nonisolated private static let passwordBlobAccount = "encryptedPassword"

    /// Glance Verde: cada uso da chave leva um rótulo autenticado (AAD do AES-GCM). Um texto cifrado de rostos não abre
    /// como senha nem o contrário, e trocar um arquivo pelo outro é recusado em vez de decifrado.
    enum Purpose: String, Sendable {
        case password = "glanceverde.password.v1"
        case faces = "glanceverde.faces.v1"

        nonisolated var authenticatedData: Data { Data(rawValue.utf8) }
    }

    // MARK: - Session state (thread-safe via NSLock)

    nonisolated private static let sessionLock = NSLock()
    nonisolated(unsafe) private static var _cachedKey: SymmetricKey?
    /// Last unlock or successful `readPassword` — what `SessionAutoLocker` compares against the idle limit. Guarded by
    /// `sessionLock` alongside the key so the two can never be observed out of step.
    nonisolated(unsafe) private static var _lastActivityAt: Date?

    nonisolated static var isSessionUnlocked: Bool {
        sessionLock.lock(); defer { sessionLock.unlock() }
        return _cachedKey != nil
    }

    /// `nil` whenever the session is locked — there is no activity to age.
    nonisolated static var lastActivityAt: Date? {
        sessionLock.lock(); defer { sessionLock.unlock() }
        return _lastActivityAt
    }

    nonisolated private static func cachedKey() -> SymmetricKey? {
        sessionLock.lock(); defer { sessionLock.unlock() }
        return _cachedKey
    }

    nonisolated private static func setCachedKey(_ key: SymmetricKey?) {
        sessionLock.lock()
        let changed = (key != nil) != (_cachedKey != nil)
        _cachedKey = key
        _lastActivityAt = key == nil ? nil : Date()
        sessionLock.unlock()
        // Posted after releasing the lock — observers may call back into `isSessionUnlocked` (re-acquiring it) from a
        // background thread, so posting while still locked risks a real self-deadlock, not a theoretical one.
        guard changed else { return }
        NotificationCenter.default.post(name: .secureCredentialSessionDidChange, object: nil)
    }

    /// Resets the idle countdown on each successful use, so an actively-used session never auto-locks.
    nonisolated private static func recordActivity() {
        sessionLock.lock()
        if _cachedKey != nil { _lastActivityAt = Date() }
        sessionLock.unlock()
    }

    // MARK: - Generic session-key crypto (shared by passwords here and face embeddings in SecureFaceStore; requires an unlocked session)

    nonisolated static func encrypt(_ plaintext: Data, purpose: Purpose) throws -> Data {
        guard let key = cachedKey() else { throw SecureCredentialError.sessionLocked }
        do {
            let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: purpose.authenticatedData)
            guard let combined = sealed.combined else { throw SecureCredentialError.encryptionFailed }
            return combined
        } catch {
            throw SecureCredentialError.encryptionFailed
        }
    }

    nonisolated static func decrypt(_ ciphertext: Data, purpose: Purpose) throws -> Data {
        guard let key = cachedKey() else { throw SecureCredentialError.sessionLocked }
        do {
            let sealed = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(sealed, using: key, authenticating: purpose.authenticatedData)
        } catch {
            throw SecureCredentialError.decryptionFailed
        }
    }

    // MARK: - Public API

    nonisolated static func hasStoredPassword() -> Bool {
        KeychainManager.exists(account: passwordBlobAccount)
    }

    /// Prompts Touch ID and unwraps the session key, creating it Touch-ID-gated on first run. Caches only after a real gated
    /// read-back succeeds — `SecItemAdd` alone returns success even if the user hit Cancel on the auth UI, and bridging
    /// `LAContext.evaluatePolicy` synchronously via a semaphore deadlocks the thread pool and crashes the process.
    /// Must succeed before `savePassword`/`readPassword`. Blocking; call from a background task.
    nonisolated static func unlockSession(reason: String) throws {
        if cachedKey() != nil { return }

        // The existence check, not the read, decides whether a key gets created (load-bearing): a cancelled Touch ID prompt on
        // a user-presence item reports `errSecItemNotFound`, indistinguishable from no key — deciding on the read's error would
        // mint a fresh key (destroying the one that decrypts existing data) on every mis-tap.
        if KeychainManager.exists(account: sessionKeyAccount) {
            let context = LAContext()
            context.localizedReason = reason
            var data = try KeychainManager.read(account: sessionKeyAccount, context: context)
            defer { data.resetBytes(in: 0..<data.count) }
            guard data.count == 32 else { throw KeychainError.unexpectedData }
            setCachedKey(SymmetricKey(data: data))
            return
        }

        // No key at all, but minting one is still destructive if data is already encrypted under a previous key (e.g. a
        // re-signed dev build) — refuse rather than silently render it unreadable forever.
        guard !hasSessionEncryptedData else {
            throw SecureCredentialError.sessionKeyUnavailable
        }

        var fresh = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        defer { fresh.resetBytes(in: 0..<fresh.count) }
        let access = try KeychainManager.makeBiometryAccessControl()
        try KeychainManager.save(
            account: sessionKeyAccount,
            data: fresh,
            accessControl: access
        )

        // Read back through the gated path rather than trusting the write — only a real read proves authentication happened.
        let readBackContext = LAContext()
        readBackContext.localizedReason = reason
        var data = try KeychainManager.read(account: sessionKeyAccount, context: readBackContext)
        defer { data.resetBytes(in: 0..<data.count) }
        guard data == fresh else { throw KeychainError.unexpectedData }
        setCachedKey(SymmetricKey(data: data))
    }

    /// Checked without needing the key itself, so this stays answerable precisely when the key can't be read.
    nonisolated static var hasSessionEncryptedData: Bool {
        KeychainManager.exists(account: passwordBlobAccount) || SecureFaceStore.exists
    }

    /// Clears the cached session key. Next save/read requires Touch ID again.
    nonisolated static func lockSession() {
        setCachedKey(nil)
    }

    /// Encrypts and stores `passwordBytes`. Requires an unlocked session —
    /// call `unlockSession(reason:)` first. Blocking; call from a background task.
    nonisolated static func savePassword(_ passwordBytes: Data) throws {
        guard !passwordBytes.isEmpty else { throw SecureCredentialError.emptyPassword }
        guard cachedKey() != nil else { throw SecureCredentialError.sessionLocked }
        // Glance Verde: senha errada nunca é guardada — digitada na tela de bloqueio, só somaria tentativas falhas.
        guard verifyLocalAccountPassword(passwordBytes) else { throw SecureCredentialError.passwordMismatch }
        let combined = try encrypt(passwordBytes, purpose: .password)
        try KeychainManager.save(account: passwordBlobAccount, data: combined)
    }

    /// No separate Touch ID prompt — only the session key was gated, at unlock time. Caller MUST zero the returned bytes via
    /// `.resetBytes(in:)` after use. Blocking; call from a background task.
    nonisolated static func readPassword() throws -> Data {
        guard cachedKey() != nil else { throw SecureCredentialError.sessionLocked }
        let ciphertext = try KeychainManager.read(account: passwordBlobAccount)
        let plaintext = try decrypt(ciphertext, purpose: .password)
        // Only on success: a failed read shouldn't extend the idle window.
        recordActivity()
        return plaintext
    }

    /// Confere a senha no diretório local deste Mac (o mesmo que a tela de bloqueio usa), sem rede e sem guardar nada.
    nonisolated private static func verifyLocalAccountPassword(_ passwordBytes: Data) -> Bool {
        guard let password = String(data: passwordBytes, encoding: .utf8), !password.isEmpty,
              let node = try? ODNode(session: ODSession.default(), name: "/Local/Default"),
              let record = try? node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
        else { return false }
        return (try? record.verifyPassword(password)) != nil
    }

    /// Deletes both Keychain items and clears the cached session key.
    nonisolated static func deletePassword() throws {
        try KeychainManager.delete(account: passwordBlobAccount)
        try KeychainManager.delete(account: sessionKeyAccount)
        setCachedKey(nil)
    }
}
