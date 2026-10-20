//
//  POCController.swift
//  glance
//
//  Orchestration for credential storage: wires SecureCredentialManager to
//  KeystrokeInjector and exposes session/password status for Settings.
//

import Foundation
import Observation

@Observable
@MainActor
final class POCController {
    var accessibilityGranted: Bool = KeystrokeInjector.isAccessibilityTrusted()

    var hasStoredPassword: Bool = SecureCredentialManager.hasStoredPassword()
    var isSessionUnlocked: Bool = SecureCredentialManager.isSessionUnlocked
    var sessionError: String? = nil

    /// Bound to the setup SecureField. Cleared immediately after a successful save.
    var passwordInput: String = ""

    var statusMessage: String = "Idle"

    func refreshAccessibilityStatus() {
        accessibilityGranted = KeystrokeInjector.isAccessibilityTrusted()
    }

    func requestAccessibility() {
        KeystrokeInjector.promptForAccessibility()
    }

    func refreshCredentialStatus() {
        hasStoredPassword = SecureCredentialManager.hasStoredPassword()
        isSessionUnlocked = SecureCredentialManager.isSessionUnlocked
    }

    // MARK: - Session (Touch ID gate)

    /// Must succeed before `savePassword()` or `injectStoredPassword()` will do anything.
    func unlockSession() async {
        sessionError = nil
        do {
            try await Task.detached(priority: .userInitiated) {
                try SecureCredentialManager.unlockSession(reason: "Confirme para configurar ou usar o Glance")
            }.value
            isSessionUnlocked = true
        } catch {
            isSessionUnlocked = false
            sessionError = error.localizedDescription
        }
    }

    func lockSession() {
        SecureCredentialManager.lockSession()
        isSessionUnlocked = false
    }

    // MARK: - Setup flow

    /// Encrypts and stores `passwordInput`. Requires the session to already
    /// be unlocked (Touch ID happens in `unlockSession()`, not here).
    func savePassword() async {
        guard !passwordInput.isEmpty else {
            statusMessage = "Digite a senha primeiro."
            return
        }
        let plaintext = passwordInput
        passwordInput = ""

        do {
            try await Task.detached(priority: .userInitiated) {
                guard var bytes = plaintext.data(using: .utf8) else {
                    throw SecureCredentialError.emptyPassword
                }
                defer { bytes.resetBytes(in: 0..<bytes.count) }
                try SecureCredentialManager.savePassword(bytes)
            }.value
            statusMessage = "Senha conferida, cifrada e guardada."
            hasStoredPassword = true
        } catch {
            statusMessage = "Não guardou: \(error.localizedDescription)"
        }
    }

    // MARK: - Injection

    /// Reads + decrypts + injects the stored password, zeroing the plaintext
    /// buffer before returning. When `requireAuthoritativeLock` is true (the
    /// auto-trigger path), refuses to inject unless the CGSession dictionary
    /// confirms the screen is actually locked.
    /// Glance Verde: a senha só é digitada com a tela realmente bloqueada — conferido aqui e de novo no instante de digitar,
    /// para que um desbloqueio no meio do caminho não a mande para um campo de texto qualquer.
    /// A tela continua conferida antes de cada tecla e de cada lote: se a pessoa desbloquear com a senha ou o Touch ID
    /// no meio, a digitação para ali.
    func injectStoredPassword() async {
        guard KeystrokeInjector.isAccessibilityTrusted() else {
            statusMessage = "Falta a permissão de Acessibilidade — ative o Glance nos Ajustes do Sistema."
            return
        }
        guard SecureCredentialManager.isSessionUnlocked else {
            statusMessage = "Sessão bloqueada — confirme com o Touch ID primeiro."
            return
        }
        guard LockMonitor.isScreenActuallyLocked() else {
            statusMessage = "Não digitou: a tela não está bloqueada."
            return
        }

        statusMessage = "Digitando…"
        do {
            try await Task.detached(priority: .userInitiated) {
                guard LockMonitor.isScreenActuallyLocked() else { throw InjectionRefusal.screenNotLocked }
                var bytes = try SecureCredentialManager.readPassword()
                defer { bytes.resetBytes(in: 0..<bytes.count) }
                try KeystrokeInjector.typeAndReturn(bytes, shouldContinue: { LockMonitor.isScreenActuallyLocked() })
            }.value
            statusMessage = "Senha digitada às \(Date().formatted(date: .omitted, time: .standard))"
        } catch {
            statusMessage = "Não digitou: \(error.localizedDescription)"
        }
    }
}

nonisolated private enum InjectionRefusal: LocalizedError {
    case screenNotLocked

    var errorDescription: String? { "a tela deixou de estar bloqueada antes de digitar." }
}
