import Foundation

/// Decisão de uma tentativa de desbloqueio. Recusa por padrão: só `.unlock` autoriza digitar a senha.
public enum UnlockStep: Equatable, Sendable {
    case `continue`
    case unlock
    case abort(UnlockAbort)
}

public enum UnlockAbort: Equatable, Sendable {
    case notLocked, spoof, wrongFace, timeout
}

/// Porta pura de uma tentativa: tela bloqueada, um rosto, semelhança acima do limiar em quadros seguidos
/// e anti-fraude aprovado em quadros seguidos. Qualquer quadro sem vetor ou sem PAD zera as sequências.
public struct UnlockGate: Equatable, Sendable {
    public let threshold: Float
    public let matchesRequired: Int
    public let liveRequired: Int
    public let wrongFaceLimit: TimeInterval
    public let timeLimit: TimeInterval
    public let started: TimeInterval
    public private(set) var matches = 0
    public private(set) var live = 0
    public private(set) var wrongSince: TimeInterval?
    public private(set) var finished = false

    public static let minimumThreshold: Float = 0.35
    public static let maximumThreshold: Float = 0.8

    public init(threshold: Float, started: TimeInterval, matchesRequired: Int = 2, liveRequired: Int = 3,
                wrongFaceLimit: TimeInterval = 2, timeLimit: TimeInterval = 15) {
        // Limiar fora da faixa ou inválido é levado ao valor mais exigente.
        self.threshold = threshold.isFinite ? min(max(threshold, Self.minimumThreshold), Self.maximumThreshold) : Self.maximumThreshold
        self.started = started
        self.matchesRequired = max(1, matchesRequired)
        self.liveRequired = max(1, liveRequired)
        self.wrongFaceLimit = wrongFaceLimit
        self.timeLimit = timeLimit
    }

    public mutating func record(locked: Bool, faceCount: Int, similarity: Float?,
                                presentation: PresentationAssessment?, now: TimeInterval) -> UnlockStep {
        guard !finished else { return .abort(.timeout) }
        guard locked else { return finish(.notLocked) }
        guard now - started <= timeLimit, now >= started else { return finish(.timeout) }
        if let presentation, presentation.spoofSuspected { return finish(.spoof) }
        guard faceCount == 1, let similarity, similarity.isFinite, let presentation else {
            matches = 0
            live = 0
            return .continue
        }
        live = presentation.isLive ? live + 1 : 0
        if similarity >= threshold {
            matches += 1
            wrongSince = nil
        } else {
            matches = 0
            let since = wrongSince ?? now
            wrongSince = since
            if now - since >= wrongFaceLimit { return finish(.wrongFace) }
        }
        guard matches >= matchesRequired, live >= liveRequired else { return .continue }
        finished = true
        return .unlock
    }

    private mutating func finish(_ reason: UnlockAbort) -> UnlockStep {
        finished = true
        return .abort(reason)
    }
}
