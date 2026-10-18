import Foundation
import CryptoKit

public struct Enrollment: Codable, Equatable, Sendable {
    public let version: Int
    public let provider: String
    public let revision: Int
    public let samples: [Data]

    public init(revision: Int, samples: [Data]) {
        version = 1
        provider = "apple-vision-image-feature-print"
        self.revision = revision
        self.samples = samples
    }

    public func validate() throws {
        guard version == 1, provider == "apple-vision-image-feature-print", revision == 2,
              samples.count == 3, samples.allSatisfy({ !$0.isEmpty && $0.count < 200_000 }) else {
            throw EnrollmentError.invalidRecord
        }
    }
}

public enum EnrollmentError: Error { case invalidRecord, invalidEnvelope }

public enum EnrollmentCipher {
    private static let context = Data("MacFaceGuard.enrollment.v1".utf8)

    public static func seal(_ enrollment: Enrollment, key: SymmetricKey) throws -> Data {
        try enrollment.validate()
        let box = try AES.GCM.seal(JSONEncoder().encode(enrollment), using: key, authenticating: context)
        guard let data = box.combined else { throw EnrollmentError.invalidEnvelope }
        return data
    }

    public static func open(_ data: Data, key: SymmetricKey) throws -> Enrollment {
        guard data.count >= 28, data.count < 1_000_000 else { throw EnrollmentError.invalidEnvelope }
        let plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: context)
        let enrollment = try JSONDecoder().decode(Enrollment.self, from: plaintext)
        try enrollment.validate()
        return enrollment
    }
}

/// Cadastro v2: vetores do modelo facial, presos ao hash do pacote, à dimensão e ao pré-processamento.
public struct EnrollmentV2: Codable, Equatable, Sendable {
    public static let sampleCount = 3
    public let version: Int
    public let modelID: String
    public let modelSHA256: String
    public let dimension: Int
    public let preprocessing: String
    public let embeddings: [[Float]]

    public init(model: FaceModelDescriptor, embeddings: [[Float]]) {
        version = 2
        modelID = model.id
        modelSHA256 = model.packageSHA256
        dimension = model.dimension
        preprocessing = model.preprocessing
        self.embeddings = embeddings
    }

    /// Recusa registro de outro modelo, outra dimensão, outro alinhamento ou vetor inválido.
    public func validate(for model: FaceModelDescriptor) throws {
        guard version == 2, modelID == model.id, modelSHA256 == model.packageSHA256,
              dimension == model.dimension, preprocessing == model.preprocessing,
              embeddings.count == Self.sampleCount else { throw EnrollmentError.invalidRecord }
        do {
            for vector in embeddings { try FaceEmbedding.validate(vector, dimension: dimension) }
        } catch { throw EnrollmentError.invalidRecord }
    }

    /// Maior similaridade do cosseno entre a amostra e o cadastro; apenas informativa.
    public func bestSimilarity(to probe: [Float]) throws -> Float {
        try embeddings.map { try FaceEmbedding.cosine($0, probe, dimension: dimension) }.max() ?? -1
    }
}

public enum EnrollmentCipherV2 {
    private static let context = Data("MacFaceGuard.enrollment.v2".utf8)

    public static func seal(_ enrollment: EnrollmentV2, key: SymmetricKey, model: FaceModelDescriptor) throws -> Data {
        try enrollment.validate(for: model)
        let box = try AES.GCM.seal(JSONEncoder().encode(enrollment), using: key, authenticating: context)
        guard let data = box.combined else { throw EnrollmentError.invalidEnvelope }
        return data
    }

    public static func open(_ data: Data, key: SymmetricKey, model: FaceModelDescriptor) throws -> EnrollmentV2 {
        guard data.count >= 28, data.count < 1_000_000 else { throw EnrollmentError.invalidEnvelope }
        let plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: context)
        let enrollment = try JSONDecoder().decode(EnrollmentV2.self, from: plaintext)
        try enrollment.validate(for: model)
        return enrollment
    }
}

public enum CapturePose: Int, CaseIterable, Sendable {
    case center, eitherSide, oppositeSide

    public var minimumQuality: Float { self == .center ? 0.20 : 0.10 }

    public func accepts(quality: Float, yaw: Double, firstTurn: Double? = nil) -> Bool {
        guard yaw.isFinite, quality.isFinite, quality >= minimumQuality, quality <= 1 else { return false }
        switch self {
        case .center: return abs(yaw) < 0.12
        case .eitherSide: return abs(yaw) >= 0.08 && abs(yaw) <= 0.65
        case .oppositeSide:
            guard let firstTurn, firstTurn.isFinite, abs(firstTurn) >= 0.08 else { return false }
            return abs(yaw) >= 0.08 && abs(yaw) <= 0.65 && yaw * firstTurn < 0
        }
    }
}

/// Preserva a sessão autorizada enquanto o diálogo do sistema devolve o foco à janela.
public struct CaptureActivationGate: Sendable {
    private var pending: UUID?
    public init() {}
    public mutating func prepare(_ run: UUID) { pending = run }
    public mutating func cancel() { pending = nil }
    public mutating func consume(_ run: UUID, isForeground: Bool) -> Bool {
        guard pending == run, isForeground else { return false }
        pending = nil
        return true
    }
}

/// Recusa quadros atrasados, futuros ou fora de ordem; não é prova de vida.
public struct CaptureFrameGate: Sendable {
    private let startedAt: TimeInterval
    private var lastCapture: TimeInterval?

    public init(startedAt: TimeInterval) { self.startedAt = startedAt }

    public mutating func consume(capturedAt: TimeInterval, now: TimeInterval) -> Bool {
        guard startedAt.isFinite, now.isFinite, capturedAt.isFinite,
              capturedAt >= startedAt, capturedAt <= now, now - capturedAt < 2,
              lastCapture.map({ capturedAt > $0 }) ?? true else { return false }
        lastCapture = capturedAt
        return true
    }
}
