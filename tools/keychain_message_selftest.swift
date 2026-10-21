//
//  keychain_message_selftest.swift
//  Glance Verde (tools)
//
//  Teste offline, sem Chaves e sem Touch ID, das mensagens de Touch ID indisponível. Compila junto do arquivo real:
//
//      swiftc -o /tmp/keychain_message_selftest glance/KeychainManager.swift \
//          tools/keychain_message_selftest.swift && /tmp/keychain_message_selftest
//
//  Também confere, lendo o código-fonte, que a leitura só pergunta o motivo depois de falhar.
//

import Foundation
import LocalAuthentication

nonisolated(unsafe) var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "ok    \(name)" : "FALHA \(name)")
    if !condition { failures += 1 }
}

func source(_ path: String) -> String {
    (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
}

// Dentro de `@main`, não solto no arquivo: com mais de um arquivo, o `swiftc` só aceita código solto em `main.swift`.
@main
struct KeychainMessageSelfTest {
    static func main() {
        // 1. Cada motivo tem sua mensagem.
        let notEnrolled = KeychainManager.biometryUnavailableMessage(code: LAError.Code.biometryNotEnrolled.rawValue)
        check(notEnrolled.contains("Nenhuma digital cadastrada"), "sem digital cadastrada (-7)")
        let lockout = KeychainManager.biometryUnavailableMessage(code: LAError.Code.biometryLockout.rawValue)
        check(lockout.contains("bloqueado"), "Touch ID bloqueado por tentativas (-8)")
        let unavailable = KeychainManager.biometryUnavailableMessage(code: LAError.Code.biometryNotAvailable.rawValue)
        check(unavailable.contains("tampa do MacBook fechada"), "Touch ID indisponível (-6) cita a tampa")
        check(KeychainManager.biometryUnavailableMessage(code: nil) == unavailable, "sem código cai na mensagem geral")
        check(KeychainManager.biometryUnavailableMessage(code: -4) == unavailable, "erro -4 (tampa fechada) cai na mensagem geral")

        // 2. O erro mostra a mensagem como está e não se confunde com cancelamento.
        let error = KeychainError.biometryUnavailable(unavailable)
        check(error.errorDescription == unavailable, "errorDescription devolve a mensagem")
        check(KeychainError.authenticationFailed.errorDescription != unavailable, "cancelamento mantém a mensagem própria")

        // 3. A leitura só consulta o LocalAuthentication depois da falha e mantém o erro antigo como recurso.
        let manager = source("glance/KeychainManager.swift")
        check(manager.contains("throw biometryUnavailableError() ?? KeychainError.authenticationFailed"),
              "read() traduz a falha sem barrar leituras")
        check(manager.contains(".biometryCurrentSet"), "chave continua presa à digital atual")
        check(!manager.contains(".userPresence") && !manager.contains("devicePasscode"), "sem recurso à senha do Mac")

        print(failures == 0 ? "\nTudo certo." : "\n\(failures) falha(s).")
        exit(failures == 0 ? 0 : 1)
    }
}
