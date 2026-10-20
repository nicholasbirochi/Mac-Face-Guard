//
//  SecureFaceStore.swift
//  glance
//
//  Low-level encrypted persistence for enrolled face identities — AES-GCM under the same session key SecureCredentialManager
//  uses for the Mac password, rather than a second key. `FaceEnrollmentStore` delegates its load/save here; no plaintext fallback.
//

import Foundation
import Security

enum SecureFaceStoreError: LocalizedError {
    case sessionLocked

    var errorDescription: String? {
        switch self {
        case .sessionLocked:
            return "Sessão bloqueada. Confirme com o Touch ID para acessar os rostos cadastrados."
        }
    }
}

nonisolated enum SecureFaceStore {
    /// Distinct filename/extension so plaintext can never be mistaken for ciphertext.
    /// Glance Verde: pasta própria só do dono (0700), fora do backup do Time Machine e do iCloud.
    private static let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var directory = appSupport.appendingPathComponent("GlanceVerde", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        return directory.appendingPathComponent("face-identities.enc")
    }()

    /// True if a store exists on disk, regardless of whether the session is currently unlocked enough to read it.
    static var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Throws `.sessionLocked` rather than returning an empty array, so callers can distinguish "nothing enrolled" from "enrolled, but locked".
    static func load() throws -> [FaceIdentity] {
        guard SecureCredentialManager.isSessionUnlocked else { throw SecureFaceStoreError.sessionLocked }
        guard let ciphertext = try? Data(contentsOf: fileURL) else { return [] }
        var plaintext = try SecureCredentialManager.decrypt(ciphertext, purpose: .faces)
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        return try JSONDecoder().decode([FaceIdentity].self, from: plaintext)
    }

    static func save(_ identities: [FaceIdentity]) throws {
        guard SecureCredentialManager.isSessionUnlocked else { throw SecureFaceStoreError.sessionLocked }
        var plaintext = try JSONEncoder().encode(identities)
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        let ciphertext = try SecureCredentialManager.encrypt(plaintext, purpose: .faces)
        try ciphertext.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Sobrescreve com bytes aleatórios antes de apagar (melhor esforço: o APFS pode manter blocos antigos, mas o arquivo
    /// já era só texto cifrado com chave presa ao Touch ID).
    static func deleteAll() {
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            let size = (try? handle.seekToEnd()) ?? 0
            if size > 0 {
                try? handle.seek(toOffset: 0)
                var noise = Data(count: Int(size))
                _ = noise.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, Int(size), $0.baseAddress!) }
                try? handle.write(contentsOf: noise)
                try? handle.synchronize()
            }
            try? handle.close()
        }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
