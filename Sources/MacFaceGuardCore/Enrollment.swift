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
