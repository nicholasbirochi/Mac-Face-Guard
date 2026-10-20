import Foundation

/// Corrida entre os métodos da tela de bloqueio: senha digitada, Touch ID do macOS e rosto. O primeiro que responde
/// vence. O rosto desiste ao ver uma tecla física depois do início da procura ou a tela desbloqueada, e só pode
/// digitar a senha se reivindicar a vitória antes disso. Na dúvida (relógio inválido), o rosto desiste.
public struct UnlockRace: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case open
        case faceWon
        case yielded(Yield)
    }

    public enum Yield: Equatable, Sendable {
        /// Alguém começou a digitar a senha.
        case typing
        /// A tela foi desbloqueada por outro método (senha ou Touch ID).
        case unlocked
    }

    public let started: TimeInterval
    public private(set) var outcome = Outcome.open

    public init(started: TimeInterval) {
        self.started = started
    }

    /// `secondsSinceKey` é o tempo desde a última tecla física; `now` usa o mesmo relógio de `started`.
    @discardableResult
    public mutating func check(locked: Bool, secondsSinceKey: TimeInterval, now: TimeInterval) -> Outcome {
        guard outcome == .open else { return outcome }
        if !locked {
            outcome = .yielded(.unlocked)
        } else if Self.keyPressed(since: started, secondsSinceKey: secondsSinceKey, now: now) {
            outcome = .yielded(.typing)
        }
        return outcome
    }

    /// O rosto passou na porta: só vence se a corrida ainda estiver aberta neste instante.
    public mutating func claimForFace(locked: Bool, secondsSinceKey: TimeInterval, now: TimeInterval) -> Bool {
        guard check(locked: locked, secondsSinceKey: secondsSinceKey, now: now) == .open else { return false }
        outcome = .faceWon
        return true
    }

    /// Houve tecla física em `since` ou depois? Valores inválidos contam como tecla (recusa por padrão).
    public static func keyPressed(since: TimeInterval, secondsSinceKey: TimeInterval, now: TimeInterval) -> Bool {
        guard secondsSinceKey.isFinite, secondsSinceKey >= 0, now.isFinite, since.isFinite else { return true }
        return now - secondsSinceKey >= since
    }
}
