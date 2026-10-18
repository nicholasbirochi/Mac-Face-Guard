import XCTest
import CryptoKit
@testable import MacFaceGuardCore

final class FaceEmbeddingTests: XCTestCase {
    func testNormalizationProducesUnitVector() throws {
        let vector = try FaceEmbedding.normalized([3, 4, 0, 0], dimension: 4)
        XCTAssertEqual(vector, [0.6, 0.8, 0, 0])
        XCTAssertNoThrow(try FaceEmbedding.validate(vector, dimension: 4))
    }

    func testInvalidRawOutputsAreRejected() {
        let cases: [([Float], EmbeddingError)] = [
            ([1, 2, 3], .wrongDimension),
            ([1, .nan, 0, 0], .nonFinite),
            ([1, .infinity, 0, 0], .nonFinite),
            ([0, 0, 0, 0], .zeroNorm),
            ([1e-8, 0, 0, 0], .zeroNorm),
        ]
        for (raw, error) in cases {
            XCTAssertThrowsError(try FaceEmbedding.normalized(raw, dimension: 4)) { XCTAssertEqual($0 as? EmbeddingError, error) }
        }
        XCTAssertThrowsError(try FaceEmbedding.normalized([], dimension: 0))
    }

    func testValidationRequiresUnitNorm() {
        XCTAssertThrowsError(try FaceEmbedding.validate([0.5, 0.5, 0, 0], dimension: 4)) {
            XCTAssertEqual($0 as? EmbeddingError, .notNormalized)
        }
        XCTAssertThrowsError(try FaceEmbedding.validate([1, 0, 0], dimension: 4)) {
            XCTAssertEqual($0 as? EmbeddingError, .wrongDimension)
        }
    }

    func testCosineIsBoundedAndSymmetric() throws {
        let x: [Float] = [1, 0, 0, 0], y: [Float] = [0, 1, 0, 0]
        XCTAssertEqual(try FaceEmbedding.cosine(x, x, dimension: 4), 1, accuracy: 1e-6)
        XCTAssertEqual(try FaceEmbedding.cosine(x, x.map { -$0 }, dimension: 4), -1, accuracy: 1e-6)
        XCTAssertEqual(try FaceEmbedding.cosine(x, y, dimension: 4), 0, accuracy: 1e-6)
        let a = try FaceEmbedding.normalized([1, 2, 3, 4], dimension: 4)
        let b = try FaceEmbedding.normalized([4, 3, 2, 1], dimension: 4)
        XCTAssertEqual(try FaceEmbedding.cosine(a, b, dimension: 4), try FaceEmbedding.cosine(b, a, dimension: 4))
        // Vetor dentro da tolerância de norma (1,0005) não ultrapassa 1.
        XCTAssertLessThanOrEqual(try FaceEmbedding.cosine([1.0005, 0, 0, 0], [1.0005, 0, 0, 0], dimension: 4), 1)
        XCTAssertThrowsError(try FaceEmbedding.cosine(x, [2, 0, 0, 0], dimension: 4))
    }
}

final class ModelIntegrityTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MFG-integrity-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// Pacote sintético, sem pesos reais: só bytes pequenos de teste.
    private func makePackage(_ name: String, files: [(String, String)]) throws -> URL {
        let package = root.appendingPathComponent(name, isDirectory: true)
        for (path, content) in files {
            let url = package.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        return package
    }

    private static let files = [("Manifest.json", "{}"), ("Data/model.mlmodel", "spec"), ("Data/weights/weight.bin", "weights"),
                                ("Data/Z.txt", "z"), ("Data/a.txt", "a")]

    func testDigestMatchesDocumentedAlgorithm() throws {
        let package = try makePackage("A.mlpackage", files: Self.files)
        // Ordem por componentes em UTF-8: maiúsculas antes de minúsculas; "Data" antes de "Manifest.json".
        let order = ["Data/Z.txt", "Data/a.txt", "Data/model.mlmodel", "Data/weights/weight.bin", "Manifest.json"]
        var expected = SHA256()
        for path in order {
            let content = Self.files.first { $0.0 == path }!.1
            expected.update(data: Data(path.utf8) + [0])
            expected.update(data: Data(SHA256.hash(data: Data(content.utf8))))
        }
        let hex = expected.finalize().map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(try ModelIntegrity.packageDigest(at: package), hex)
        XCTAssertNoThrow(try ModelIntegrity.verify(package, expected: hex.uppercased()))
    }

    func testDigestIgnoresCreationOrder() throws {
        let first = try makePackage("A.mlpackage", files: Self.files)
        let second = try makePackage("B.mlpackage", files: Self.files.reversed())
        XCTAssertEqual(try ModelIntegrity.packageDigest(at: first), try ModelIntegrity.packageDigest(at: second))
    }

    func testTamperedRenamedOrExtraFileFailsVerification() throws {
        let package = try makePackage("A.mlpackage", files: Self.files)
        let good = try ModelIntegrity.packageDigest(at: package)
        let weights = package.appendingPathComponent("Data/weights/weight.bin")
        try Data("weightz".utf8).write(to: weights)
        XCTAssertThrowsError(try ModelIntegrity.verify(package, expected: good)) {
            XCTAssertEqual($0 as? ModelIntegrityError, .hashMismatch)
        }
        try Data("weights".utf8).write(to: weights)
        XCTAssertNoThrow(try ModelIntegrity.verify(package, expected: good))
        try FileManager.default.moveItem(at: weights, to: package.appendingPathComponent("Data/weights/weight2.bin"))
        XCTAssertThrowsError(try ModelIntegrity.verify(package, expected: good))
        try FileManager.default.moveItem(at: package.appendingPathComponent("Data/weights/weight2.bin"), to: weights)
        try Data().write(to: package.appendingPathComponent("extra"))
        XCTAssertThrowsError(try ModelIntegrity.verify(package, expected: good))
    }

    func testMissingOrMalformedPackageFailsClosed() throws {
        XCTAssertThrowsError(try ModelIntegrity.packageDigest(at: root.appendingPathComponent("absent.mlpackage"))) {
            XCTAssertEqual($0 as? ModelIntegrityError, .missing)
        }
        let empty = root.appendingPathComponent("Empty.mlpackage/Data", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertThrowsError(try ModelIntegrity.packageDigest(at: empty.deletingLastPathComponent())) {
            XCTAssertEqual($0 as? ModelIntegrityError, .invalidLayout)
        }
        let file = root.appendingPathComponent("file.mlpackage")
        try Data("x".utf8).write(to: file)
        XCTAssertThrowsError(try ModelIntegrity.packageDigest(at: file)) {
            XCTAssertEqual($0 as? ModelIntegrityError, .invalidLayout)
        }
    }

    func testSymbolicLinksAreRejected() throws {
        let package = try makePackage("A.mlpackage", files: Self.files)
        let outside = root.appendingPathComponent("outside.bin")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: package.appendingPathComponent("Data/link.bin"), withDestinationURL: outside)
        XCTAssertThrowsError(try ModelIntegrity.packageDigest(at: package)) {
            XCTAssertEqual($0 as? ModelIntegrityError, .invalidLayout)
        }
        let linkedRoot = root.appendingPathComponent("Linked.mlpackage")
        let clean = try makePackage("C.mlpackage", files: Self.files)
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: clean)
        XCTAssertThrowsError(try ModelIntegrity.packageDigest(at: linkedRoot)) {
            XCTAssertEqual($0 as? ModelIntegrityError, .invalidLayout)
        }
    }

    func testTooManyFilesAreRejected() throws {
        let many = (0...ModelIntegrity.maximumFiles).map { ("f\($0)", "x") }
        let package = try makePackage("Many.mlpackage", files: many)
        XCTAssertThrowsError(try ModelIntegrity.packageDigest(at: package)) {
            XCTAssertEqual($0 as? ModelIntegrityError, .tooLarge)
        }
    }
}

final class EnrollmentV2Tests: XCTestCase {
    private let model = FaceModelDescriptor(id: "test-model", packageSHA256: String(repeating: "ab", count: 32),
                                            dimension: 8, preprocessing: "test-align-v1", input: "face", output: "embedding")

    /// Vetores sintéticos aleatórios normalizados; nenhum dado facial real.
    private func vector() throws -> [Float] {
        try FaceEmbedding.normalized((0..<model.dimension).map { _ in Float.random(in: -1...1) }, dimension: model.dimension)
    }

    private func enrollment() throws -> EnrollmentV2 {
        EnrollmentV2(model: model, embeddings: try (0..<EnrollmentV2.sampleCount).map { _ in try vector() })
    }

    func testRoundTripPreservesVectorsAndModelBinding() throws {
        let key = SymmetricKey(size: .bits256), record = try enrollment()
        let sealed = try EnrollmentCipherV2.seal(record, key: key, model: model)
        let opened = try EnrollmentCipherV2.open(sealed, key: key, model: model)
        XCTAssertEqual(opened, record)
        XCTAssertEqual(opened.version, 2)
        XCTAssertEqual(opened.modelSHA256, model.packageSHA256)
        XCTAssertEqual(opened.preprocessing, model.preprocessing)
    }

    func testTamperWrongKeyAndTruncationFail() throws {
        let key = SymmetricKey(size: .bits256)
        var sealed = try EnrollmentCipherV2.seal(try enrollment(), key: key, model: model)
        XCTAssertThrowsError(try EnrollmentCipherV2.open(sealed, key: SymmetricKey(size: .bits256), model: model))
        XCTAssertThrowsError(try EnrollmentCipherV2.open(sealed.prefix(27), key: key, model: model))
        XCTAssertThrowsError(try EnrollmentCipherV2.open(sealed.dropLast(), key: key, model: model))
        sealed[sealed.count / 2] ^= 1
        XCTAssertThrowsError(try EnrollmentCipherV2.open(sealed, key: key, model: model))
    }

    func testV1AndV2EnvelopesAreNotInterchangeable() throws {
        let key = SymmetricKey(size: .bits256)
        let v2 = try EnrollmentCipherV2.seal(try enrollment(), key: key, model: model)
        XCTAssertThrowsError(try EnrollmentCipher.open(v2, key: key))
        let v1 = try EnrollmentCipher.seal(Enrollment(revision: 2, samples: [Data([1]), Data([2]), Data([3])]), key: key)
        XCTAssertThrowsError(try EnrollmentCipherV2.open(v1, key: key, model: model))
    }

    func testRecordFromAnotherModelOrPreprocessingIsRejected() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try EnrollmentCipherV2.seal(try enrollment(), key: key, model: model)
        let others = [
            FaceModelDescriptor(id: "other", packageSHA256: model.packageSHA256, dimension: 8, preprocessing: model.preprocessing, input: "face", output: "embedding"),
            FaceModelDescriptor(id: model.id, packageSHA256: String(repeating: "cd", count: 32), dimension: 8, preprocessing: model.preprocessing, input: "face", output: "embedding"),
            FaceModelDescriptor(id: model.id, packageSHA256: model.packageSHA256, dimension: 16, preprocessing: model.preprocessing, input: "face", output: "embedding"),
            FaceModelDescriptor(id: model.id, packageSHA256: model.packageSHA256, dimension: 8, preprocessing: "test-align-v2", input: "face", output: "embedding"),
        ]
        for other in others {
            XCTAssertThrowsError(try EnrollmentCipherV2.open(sealed, key: key, model: other)) {
                XCTAssertEqual($0 as? EnrollmentError, .invalidRecord)
            }
        }
    }

    func testInvalidVectorsAreNotSealed() throws {
        let key = SymmetricKey(size: .bits256)
        let good = try vector()
        let bad: [[[Float]]] = [
            [good, good],
            [good, good, good, good],
            [good, good, good.map { $0 * 2 }],
            [good, good, [Float](repeating: .nan, count: 8)],
            [good, good, Array(good.prefix(7))],
        ]
        for embeddings in bad {
            XCTAssertThrowsError(try EnrollmentCipherV2.seal(EnrollmentV2(model: model, embeddings: embeddings), key: key, model: model)) {
                XCTAssertEqual($0 as? EnrollmentError, .invalidRecord)
            }
        }
    }

    func testBestSimilarityPicksClosestSampleAndValidatesProbe() throws {
        let basis = (0..<3).map { i in (0..<8).map { Float($0 == i ? 1 : 0) } }
        let record = EnrollmentV2(model: model, embeddings: basis)
        let probe = try FaceEmbedding.normalized([0.2, 0.9, 0.1, 0, 0, 0, 0, 0], dimension: 8)
        XCTAssertEqual(try record.bestSimilarity(to: probe), probe[1], accuracy: 1e-6)
        XCTAssertThrowsError(try record.bestSimilarity(to: [1, 0, 0]))
        XCTAssertThrowsError(try record.bestSimilarity(to: [Float](repeating: .nan, count: 8)))
    }

    func testSimilarityNeverAuthorizesWithoutPAD() {
        // Mesmo com similaridade alta, sem prova de vida (PAD) e limiar validado a decisão continua negada.
        func evidence(match: Bool) -> DemoEvidence {
            DemoEvidence(cameraAuthorized: true, enrollmentExists: true, singleFaceDetected: true,
                         captureQualityApproved: true, identityMatched: match, livenessPassed: false,
                         framesConsistent: true, sessionCurrent: true, spoofSuspected: false)
        }
        XCTAssertEqual(DecisionEngine().evaluate(evidence(match: false)), .denied(.identityNotMatched))
        XCTAssertEqual(DecisionEngine().evaluate(evidence(match: true)), .denied(.livenessNotProven))
    }
}
