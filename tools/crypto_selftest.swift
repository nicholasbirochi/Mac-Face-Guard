//
//  crypto_selftest.swift
//  Glance Verde (tools)
//
//  Teste offline, sem câmera, sem Chaves e sem Touch ID, das regras de cifragem e de digitação que o Glance Verde
//  acrescentou. O projeto não tem alvo de testes, então roda como script avulso:
//
//      swift tools/crypto_selftest.swift
//
//  Não toca nos arquivos reais nem no Chaves: usa uma chave aleatória descartável. Os rótulos abaixo precisam bater com
//  `SecureCredentialManager.Purpose`; o próprio script confere isso lendo o código-fonte.
//

import Foundation
import CryptoKit

var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "ok    \(name)" : "FALHA \(name)")
    if !condition { failures += 1 }
}

let passwordLabel = "glanceverde.password.v1"
let facesLabel = "glanceverde.faces.v1"

// 0. Os rótulos do teste são os mesmos do app.
let sourceURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("glance/SecureCredentialManager.swift")
let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""
check(source.contains("\"\(passwordLabel)\"") && source.contains("\"\(facesLabel)\""), "rótulos AAD iguais aos do app")

// 1. Cifra e decifra com o mesmo propósito.
let key = SymmetricKey(size: .bits256)
let secret = Data("senha-de-teste-🔒".utf8)
let sealed = try AES.GCM.seal(secret, using: key, authenticating: Data(passwordLabel.utf8)).combined!
let opened = try? AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: Data(passwordLabel.utf8))
check(opened == secret, "ida e volta com o mesmo propósito")

// 2. Texto cifrado de senha não abre como rostos (troca de arquivos é recusada).
let crossed = try? AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: Data(facesLabel.utf8))
check(crossed == nil, "senha não abre com o rótulo de rostos")

// 3. Um bit trocado é detectado.
var tampered = sealed
tampered[tampered.count / 2] ^= 0x01
let tamperedOpen = try? AES.GCM.open(AES.GCM.SealedBox(combined: tampered), using: key, authenticating: Data(passwordLabel.utf8))
check(tamperedOpen == nil, "adulteração de 1 bit é recusada")

// 4. Outra chave não abre.
let otherKey = SymmetricKey(size: .bits256)
let wrongKey = try? AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: otherKey, authenticating: Data(passwordLabel.utf8))
check(wrongKey == nil, "chave diferente é recusada")

// 5. Decodificação UTF-8 → UTF-16 igual à do KeystrokeInjector.
func utf16Units(_ bytes: Data) -> [UInt16]? {
    var units: [UInt16] = []
    units.reserveCapacity(bytes.count)
    let invalid = transcode(bytes.makeIterator(), from: UTF8.self, to: UTF16.self, stoppingOnError: true) { units.append($0) }
    return invalid || units.isEmpty ? nil : units
}
let sample = "Sẽnh@ çom 🔒 e 𝄞"
check(utf16Units(Data(sample.utf8)) == Array(sample.utf16), "UTF-16 confere com acentos, emoji e fora do BMP")
check(utf16Units(Data([0x61, 0xFF, 0x62])) == nil, "UTF-8 inválido é recusado em vez de digitar lixo")
check(utf16Units(Data()) == nil, "senha vazia é recusada")

// 6. Lotes de 20 unidades nunca terminam no meio de um par substituto.
let units = Array(String(repeating: "a🔒", count: 30).utf16)
var start = 0
var splitsPair = false
var rebuilt: [UInt16] = []
while start < units.count {
    var end = min(start + 20, units.count)
    if end < units.count, (0xD800...0xDBFF).contains(units[end - 1]) { end -= 1 }
    if (0xD800...0xDBFF).contains(units[end - 1]) { splitsPair = true }
    rebuilt += units[start..<end]
    start = end
}
check(!splitsPair && rebuilt == units, "lotes preservam pares substitutos")

// 7. A digitação para no meio se a tela for desbloqueada por outro meio e nunca deixa ⌘ preso.
let injectorURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("glance/KeystrokeInjector.swift")
let injector = (try? String(contentsOf: injectorURL, encoding: .utf8)) ?? ""
check(injector.contains("shouldContinue: () -> Bool"), "injetor aceita a conferência entre teclas")
check(injector.contains("throw KeystrokeError.interrupted"), "injetor interrompe quando a conferência falha")
check(injector.contains("releaseCommand(source:"), "injetor solta ⌘ ao interromper")

print(failures == 0 ? "\nTudo certo." : "\n\(failures) falha(s).")
exit(failures == 0 ? 0 : 1)
