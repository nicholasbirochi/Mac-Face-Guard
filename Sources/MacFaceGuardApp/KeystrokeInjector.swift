// Adaptado de Glance (https://github.com/jonnyoo/glance), KeystrokeInjector.swift.
// MIT License, Copyright (c) 2026 Jonathan Zhou. Aviso completo em THIRD_PARTY_NOTICES.md.
import Foundation
import ApplicationServices
import CoreGraphics

/// Digita a senha no campo da tela de bloqueio por eventos de teclado (exige Acessibilidade).
enum KeystrokeInjector {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForAccessibility() {
        // Valor de kAXTrustedCheckOptionPrompt; a constante global não é segura para concorrência no Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Limpa o campo, digita a senha e pressiona Return. Os bytes são da senha; quem chama os zera.
    static func typeAndReturn(_ passwordBytes: Data) throws {
        guard isTrusted else { throw GuardError.message("Permita o MacFaceGuard em Ajustes → Privacidade e Segurança → Acessibilidade.") }
        guard var text = String(data: passwordBytes, encoding: .utf8), !text.isEmpty,
              let source = CGEventSource(stateID: .hidSystemState) else {
            throw GuardError.message("Não foi possível preparar a digitação.")
        }
        defer { text = "" }
        post(key: 0x7C, flags: .maskCommand, source: source)  // ⌘→
        post(key: 0x33, flags: .maskCommand, source: source)  // ⌘⌫
        try postText(text, source: source)
        post(key: 0x24, flags: [], source: source)            // Return
    }

    private static func post(key: CGKeyCode, flags: CGEventFlags, source: CGEventSource) {
        let command = flags.contains(.maskCommand)
        if command, let down = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true) {
            down.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            usleep(12_000)
        }
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
            usleep(12_000)
        }
        if command, let up = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) {
            up.flags = []
            up.post(tap: .cghidEventTap)
            usleep(12_000)
        }
    }

    /// Envia o texto em lotes de 20 unidades UTF-16 sem partir pares substitutos.
    private static func postText(_ text: String, source: CGEventSource) throws {
        var buffer = Array(text.utf16)
        defer { for i in buffer.indices { buffer[i] = 0 } }
        var start = 0
        while start < buffer.count {
            var end = min(start + 20, buffer.count)
            if end < buffer.count, (0xD800...0xDBFF).contains(buffer[end - 1]) { end -= 1 }
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                throw GuardError.message("Não foi possível criar os eventos de teclado.")
            }
            try buffer[start..<end].withUnsafeBufferPointer { chunk in
                guard let base = chunk.baseAddress else { throw GuardError.message("Texto vazio.") }
                down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: base)
                up.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: base)
            }
            down.post(tap: .cghidEventTap)
            usleep(4_000)
            up.post(tap: .cghidEventTap)
            usleep(4_000)
            start = end
        }
    }
}
