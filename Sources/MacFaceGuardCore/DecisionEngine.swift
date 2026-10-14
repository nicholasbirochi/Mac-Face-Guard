/// Núcleo de decisão de DEMONSTRAÇÃO. Não autentica no macOS e não contém biometria.
/// Sinais bool são simplificações de teste; adaptadores reais devem oferecer evidências verificáveis.
public struct DemoEvidence: Sendable, Equatable {
    public let cameraAuthorized: Bool
    public let enrollmentExists: Bool
    public let singleFaceDetected: Bool
    public let captureQualityApproved: Bool
    public let identityMatched: Bool
    public let livenessPassed: Bool
    public let framesConsistent: Bool
    public let sessionCurrent: Bool
    public let spoofSuspected: Bool

    public init(cameraAuthorized: Bool, enrollmentExists: Bool, singleFaceDetected: Bool,
                captureQualityApproved: Bool, identityMatched: Bool, livenessPassed: Bool,
                framesConsistent: Bool, sessionCurrent: Bool, spoofSuspected: Bool) {
        self.cameraAuthorized = cameraAuthorized
        self.enrollmentExists = enrollmentExists
        self.singleFaceDetected = singleFaceDetected
        self.captureQualityApproved = captureQualityApproved
        self.identityMatched = identityMatched
        self.livenessPassed = livenessPassed
        self.framesConsistent = framesConsistent
        self.sessionCurrent = sessionCurrent
        self.spoofSuspected = spoofSuspected
    }
}

public enum DemoDenial: String, Sendable, Equatable {
    case cameraNotAuthorized
    case noEnrollment
    case faceCountNotOne
    case captureQualityInsufficient
    case possibleSpoof
    case identityNotMatched
    case livenessNotProven
    case inconsistentFrames
    case expiredSession
}

public enum DemoDecision: Sendable, Equatable {
    /// Permitido SOMENTE no aplicativo de demonstração. Não é autorização do macOS.
    case acceptedForDemo
    case denied(DemoDenial)
}

public struct DecisionEngine: Sendable {
    public init() {}

    /// Política fail-closed: cada controle deve estar explicitamente aprovado.
    public func evaluate(_ e: DemoEvidence) -> DemoDecision {
        if !e.cameraAuthorized { return .denied(.cameraNotAuthorized) }
        if !e.enrollmentExists { return .denied(.noEnrollment) }
        if !e.singleFaceDetected { return .denied(.faceCountNotOne) }
        if !e.captureQualityApproved { return .denied(.captureQualityInsufficient) }
        if e.spoofSuspected { return .denied(.possibleSpoof) }
        if !e.identityMatched { return .denied(.identityNotMatched) }
        if !e.livenessPassed { return .denied(.livenessNotProven) }
        if !e.framesConsistent { return .denied(.inconsistentFrames) }
        if !e.sessionCurrent { return .denied(.expiredSession) }
        return .acceptedForDemo
    }
}
