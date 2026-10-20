//
//  UnlockRace.swift
//  glance
//
//  Glance Verde: senha digitada, Touch ID e rosto correm juntos na tela de bloqueio; o primeiro que responder vence.
//  Sob entrada segura o app não vê as teclas, mas o estado HID diz há quanto tempo houve a última tecla física. Uma
//  tecla depois do início da procura cede a vez à digitação; a tela desbloqueada por outro meio (senha ou Touch ID)
//  cede a vez ao desbloqueio. O rosto só digita depois de reivindicar a vitória com `claimForFace`, que confere as
//  duas coisas no mesmo instante. Nenhuma regra de segurança muda: a corrida só faz o rosto desistir mais cedo.
//

import Foundation
import CoreGraphics

nonisolated struct UnlockRace: Equatable, Sendable {
    enum Yield: Equatable, Sendable {
        /// Tecla física depois do início: a pessoa está digitando a senha.
        case typing
        /// A tela deixou de estar bloqueada por outro meio (senha ou Touch ID).
        case unlocked
    }

    enum Outcome: Equatable, Sendable {
        case open
        case faceWon
        case yielded(Yield)
    }

    /// Instante do início da procura, no relógio de `ProcessInfo.systemUptime`.
    let started: TimeInterval
    private(set) var outcome: Outcome = .open

    init(started: TimeInterval) {
        self.started = started
    }

    /// Fecha a corrida a favor de quem respondeu primeiro. Depois de fechada, o resultado não muda mais.
    @discardableResult
    mutating func check(locked: Bool, secondsSinceKey: TimeInterval, now: TimeInterval) -> Outcome {
        guard outcome == .open else { return outcome }
        if !locked {
            outcome = .yielded(.unlocked)
        } else if Self.keyPressed(since: started, secondsSinceKey: secondsSinceKey, now: now) {
            outcome = .yielded(.typing)
        }
        return outcome
    }

    /// Verdadeiro só se ninguém respondeu antes: a partir daí o rosto pode digitar.
    mutating func claimForFace(locked: Bool, secondsSinceKey: TimeInterval, now: TimeInterval) -> Bool {
        guard check(locked: locked, secondsSinceKey: secondsSinceKey, now: now) == .open else { return false }
        outcome = .faceWon
        return true
    }

    /// Leitura impossível (não finita ou negativa) conta como tecla: na dúvida o rosto cede a vez.
    static func keyPressed(since started: TimeInterval, secondsSinceKey: TimeInterval, now: TimeInterval) -> Bool {
        guard secondsSinceKey.isFinite, secondsSinceKey >= 0 else { return true }
        return now - secondsSinceKey >= started
    }

    /// Segundos desde a última tecla física apertada, lidos do estado HID (funciona com a entrada segura ativa).
    static func secondsSinceLastKeyDown() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
    }

    static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}
