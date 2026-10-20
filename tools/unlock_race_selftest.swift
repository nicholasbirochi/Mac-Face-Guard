//
//  unlock_race_selftest.swift
//  Glance Verde (tools)
//
//  Teste offline, sem câmera e sem tela de bloqueio, da corrida entre senha digitada, Touch ID e rosto. O projeto não
//  tem alvo de testes, então compila junto do arquivo real:
//
//      swiftc -o /tmp/unlock_race_selftest glance/UnlockRace.swift tools/unlock_race_selftest.swift \
//      && /tmp/unlock_race_selftest
//
//  Também confere, lendo o código-fonte, que o coordenador e o injetor usam a corrida nos pontos certos.
//

import Foundation

nonisolated(unsafe) var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "ok    \(name)" : "FALHA \(name)")
    if !condition { failures += 1 }
}

// Dentro de `@main`, não solto no arquivo: com mais de um arquivo, o `swiftc` só aceita código solto em `main.swift`.
@main
enum UnlockRaceSelfTest {
    static func main() {
        // O relógio é o `systemUptime`: a última tecla aconteceu em `now - secondsSinceKey`.
        let started: TimeInterval = 1_000

        // 1. Tecla antiga (antes do início) não conta; o rosto pode vencer.
        do {
            var race = UnlockRace(started: started)
            check(race.check(locked: true, secondsSinceKey: 30, now: 1_010) == .open, "tecla anterior ao início não cede a vez")
            check(race.claimForFace(locked: true, secondsSinceKey: 30, now: 1_011), "sem tecla nem desbloqueio, o rosto vence")
            check(race.outcome == .faceWon, "vitória do rosto fica registrada")
        }

        // 2. Tecla depois do início: a digitação vence e o rosto não pode mais reivindicar.
        do {
            var race = UnlockRace(started: started)
            check(race.check(locked: true, secondsSinceKey: 0.5, now: 1_002) == .yielded(.typing), "tecla depois do início cede à digitação")
            check(!race.claimForFace(locked: true, secondsSinceKey: 60, now: 1_100), "depois de ceder, o rosto não digita")
            check(race.outcome == .yielded(.typing), "resultado não muda depois de fechado")
        }

        // 3. Tela desbloqueada por outro meio (senha ou Touch ID): o desbloqueio vence, mesmo com tecla junto.
        do {
            var race = UnlockRace(started: started)
            check(race.check(locked: false, secondsSinceKey: 0, now: 1_003) == .yielded(.unlocked), "desbloqueio por outro meio vence")
            check(!race.claimForFace(locked: true, secondsSinceKey: 60, now: 1_100), "rosto não digita depois do desbloqueio")
        }

        // 4. A reivindicação confere as duas coisas no mesmo instante.
        do {
            var race = UnlockRace(started: started)
            check(!race.claimForFace(locked: true, secondsSinceKey: 0.1, now: 1_005), "tecla no instante da reivindicação impede o rosto")
            check(race.outcome == .yielded(.typing), "reivindicação perdida registra a digitação")
            var other = UnlockRace(started: started)
            check(!other.claimForFace(locked: false, secondsSinceKey: 60, now: 1_005), "tela já desbloqueada impede o rosto")
        }

        // 5. Depois que o rosto venceu, teclas injetadas não reabrem nem mudam a corrida.
        do {
            var race = UnlockRace(started: started)
            _ = race.claimForFace(locked: true, secondsSinceKey: 60, now: 1_004)
            check(race.check(locked: true, secondsSinceKey: 0, now: 1_005) == .faceWon, "teclas do próprio rosto não viram digitação")
        }

        // 6. Leituras impossíveis contam como tecla (na dúvida, o rosto cede).
        check(UnlockRace.keyPressed(since: started, secondsSinceKey: .nan, now: 1_001), "NaN conta como tecla")
        check(UnlockRace.keyPressed(since: started, secondsSinceKey: .infinity, now: 1_001), "infinito conta como tecla")
        check(UnlockRace.keyPressed(since: started, secondsSinceKey: -1, now: 1_001), "negativo conta como tecla")
        check(UnlockRace.keyPressed(since: started, secondsSinceKey: 1, now: 1_001), "tecla exatamente no início conta")
        check(!UnlockRace.keyPressed(since: started, secondsSinceKey: 1.001, now: 1_001), "tecla um milissegundo antes não conta")

        // 7. Leitura real do estado HID: finita e não negativa nesta máquina.
        let live = UnlockRace.secondsSinceLastKeyDown()
        check(live.isFinite && live >= 0, "estado HID devolve um intervalo válido")

        // 8. O código usa a corrida nos pontos certos.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        func source(_ path: String) -> String {
            (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
        }
        let coordinator = source("glance/FaceUnlockCoordinator.swift")
        check(coordinator.contains("guard claimFaceWin(generation: generation) else { return .noResolution }"), "rosto reivindica a vitória antes de digitar")
        check(coordinator.contains("guard raceStillOpen(generation: generation) else { return .noResolution }"), "cada quadro confere a corrida")
        check(coordinator.contains("camera.stop()") && coordinator.contains("NotchOverlayController.shared.collapse()"), "ceder desliga a câmera e recolhe a ilha")
        check(coordinator.contains("guard unlockRace == nil, !typingYieldedForCurrentLock else { return }"), "espaço no meio da senha não religa a câmera")
        let poc = source("glance/POCController.swift")
        check(poc.contains("shouldContinue: { LockMonitor.isScreenActuallyLocked() }"), "digitação para se a tela desbloquear no meio")
        let window = source("glance/NotchOverlay/NotchWindowController.swift")
        check(window.contains("acceptsKey = interactive && key"), "a ilha não tira o foco do campo de senha")

        print(failures == 0 ? "\nTudo certo." : "\n\(failures) falha(s).")
        exit(failures == 0 ? 0 : 1)
    }
}
