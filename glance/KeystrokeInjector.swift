//
//  KeystrokeInjector.swift
//  glance
//
//  Synthesizes keystrokes via CGEvent, posted at the HID tap so they reach the lock screen's secure text field.
//

import Foundation
import ApplicationServices
import CoreGraphics

enum KeystrokeError: LocalizedError {
    case accessibilityNotGranted
    case eventCreationFailed
    /// Glance Verde: a tela foi desbloqueada por outro meio (senha ou Touch ID) no meio da digitação.
    case interrupted

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Falta a permissão de Acessibilidade. Abra Ajustes do Sistema → Privacidade e Segurança → Acessibilidade e ative o Glance."
        case .eventCreationFailed:
            return "Não foi possível criar o evento de teclado."
        case .interrupted:
            return "a tela foi desbloqueada por outro meio durante a digitação; o resto não foi digitado."
        }
    }
}

enum KeystrokeInjector {
    /// Returns true if the app has Accessibility permission (no prompt).
    nonisolated static func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Triggers the system prompt to grant Accessibility (deep links to System Settings).
    @discardableResult
    nonisolated static func promptForAccessibility() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Types the UTF-8 bytes into whatever has keyboard focus, then presses Return. Blocking.
    /// Glance Verde: decodifica direto para um buffer UTF-16 de capacidade fixa (sem `String` imutável que não dá para
    /// apagar) e zera esse buffer ao terminar, mesmo em erro.
    /// `shouldContinue` é conferido antes de cada tecla, de cada lote e do Return; falso interrompe sem soltar mais
    /// nada além das teclas que já estavam apertadas.
    nonisolated static func typeAndReturn(_ passwordBytes: Data, shouldContinue: () -> Bool = { true }) throws {
        guard isAccessibilityTrusted() else {
            throw KeystrokeError.accessibilityNotGranted
        }
        var utf16: [UInt16] = []
        // UTF-16 nunca tem mais unidades que bytes UTF-8: reservar já evita realocação e cópias soltas na memória.
        utf16.reserveCapacity(passwordBytes.count)
        defer {
            utf16.withUnsafeMutableBufferPointer { buffer in
                for index in buffer.indices { buffer[index] = 0 }
            }
        }
        let invalid = transcode(
            passwordBytes.makeIterator(),
            from: UTF8.self,
            to: UTF16.self,
            stoppingOnError: true
        ) { utf16.append($0) }
        guard !invalid, !utf16.isEmpty else {
            throw KeystrokeError.eventCreationFailed
        }
        let source = CGEventSource(stateID: .hidSystemState)
        try clearFocusedField(source: source, shouldContinue: shouldContinue)
        try postUnicodeUnits(utf16, source: source, shouldContinue: shouldContinue)
        try postReturn(source: source, shouldContinue: shouldContinue)
    }

    /// Wipes anything already typed into the focused field (e.g. a stray keypress
    /// on the lock screen) so it isn't prepended to the password: ⌘→ to the end,
    /// then ⌘⌫ to delete back to the start. Both are positional keys, so this
    /// behaves the same on every keyboard layout — unlike ⌘A, whose "A" moves.
    private nonisolated static func clearFocusedField(source: CGEventSource?, shouldContinue: () -> Bool) throws {
        let rightArrow: CGKeyCode = 0x7C
        let delete: CGKeyCode = 0x33
        try postKey(rightArrow, flags: .maskCommand, source: source, shouldContinue: shouldContinue)
        try postKey(delete, flags: .maskCommand, source: source, shouldContinue: shouldContinue)
    }

    /// Posts a virtual key down/up, wrapped in a real ⌘ down/up when `flags`
    /// includes `.maskCommand` — some text fields ignore a bare flag without it.
    /// Glance Verde: a interrupção só acontece antes de apertar algo; o que foi apertado (⌘ incluído) sempre é solto.
    private nonisolated static func postKey(
        _ keyCode: CGKeyCode,
        flags: CGEventFlags = [],
        source: CGEventSource?,
        shouldContinue: () -> Bool
    ) throws {
        let command: CGKeyCode = 0x37
        let usesCommand = flags.contains(.maskCommand)
        guard shouldContinue() else { throw KeystrokeError.interrupted }
        if usesCommand {
            guard let commandDown = CGEvent(keyboardEventSource: source, virtualKey: command, keyDown: true) else {
                throw KeystrokeError.eventCreationFailed
            }
            commandDown.flags = .maskCommand
            commandDown.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.012)
        }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw KeystrokeError.eventCreationFailed
        }
        keyDown.flags = flags
        keyUp.flags = flags
        guard shouldContinue() else {
            if usesCommand { releaseCommand(source: source) }
            throw KeystrokeError.interrupted
        }
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.012)
        keyUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.012)
        if usesCommand {
            guard releaseCommand(source: source) else { throw KeystrokeError.eventCreationFailed }
        }
    }

    @discardableResult
    private nonisolated static func releaseCommand(source: CGEventSource?) -> Bool {
        guard let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            return false
        }
        commandUp.flags = []
        commandUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.012)
        return true
    }

    /// Quartz reliably delivers only a small Unicode payload per keyboard event.
    /// Batching at this conservative limit avoids the undocumented truncation seen
    /// with longer payloads, while replacing one down/up pair per character with
    /// one pair per batch.
    nonisolated private static let maximumUnicodeBatchLength = 20
    nonisolated private static let unicodeEventInterval: TimeInterval = 0.004

    /// Posts the password in small UTF-16 batches. Splitting occurs only between
    /// surrogate pairs, so non-BMP password characters are never corrupted.
    private nonisolated static func postUnicodeUnits(
        _ utf16: [UInt16],
        source: CGEventSource?,
        shouldContinue: () -> Bool
    ) throws {
        try utf16.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            var start = 0

            while start < buffer.count {
                var end = min(start + maximumUnicodeBatchLength, buffer.count)
                // Do not split a high/low-surrogate pair across separate key events.
                if end < buffer.count,
                   (0xD800...0xDBFF).contains(buffer[end - 1]) {
                    end -= 1
                }
                guard shouldContinue() else { throw KeystrokeError.interrupted }
                try postUnicode(
                    base.advanced(by: start),
                    length: end - start,
                    source: source
                )
                start = end
            }
        }
    }

    /// Unicode injection bypasses keyboard-layout issues. The password is placed
    /// on a key-down event as a text batch; the matching key-up maintains normal
    /// secure-field event semantics.
    private nonisolated static func postUnicode(
        _ unicode: UnsafePointer<UInt16>,
        length: Int,
        source: CGEventSource?
    ) throws {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            throw KeystrokeError.eventCreationFailed
        }
        keyDown.keyboardSetUnicodeString(stringLength: length, unicodeString: unicode)
        keyUp.keyboardSetUnicodeString(stringLength: length, unicodeString: unicode)
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: unicodeEventInterval)
        keyUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: unicodeEventInterval)
    }

    /// Physical Return key (virtual key 0x24).
    private nonisolated static func postReturn(source: CGEventSource?, shouldContinue: () -> Bool) throws {
        let returnKey: CGKeyCode = 0x24
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: false) else {
            throw KeystrokeError.eventCreationFailed
        }
        guard shouldContinue() else { throw KeystrokeError.interrupted }
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.012)
        keyUp.post(tap: .cghidEventTap)
    }
}
