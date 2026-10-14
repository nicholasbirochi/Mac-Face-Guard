import XCTest
import CryptoKit
@testable import MacFaceGuardCore

final class EnrollmentTests: XCTestCase {
    private let record = Enrollment(revision: 2, samples: [Data([1]), Data([2]), Data([3])])

    func testEncryptedRoundTripAndRandomNonce() throws {
        let key = SymmetricKey(size: .bits256)
        let a = try EnrollmentCipher.seal(record, key: key)
        let b = try EnrollmentCipher.seal(record, key: key)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(try EnrollmentCipher.open(a, key: key), record)
        XCTAssertFalse(String(decoding: a, as: UTF8.self).contains(record.provider))
    }

    func testTamperingWrongKeyAndTruncationFailClosed() throws {
        let key = SymmetricKey(size: .bits256)
        let data = try EnrollmentCipher.seal(record, key: key)
        var altered = data
        altered[altered.count - 1] ^= 1
        XCTAssertThrowsError(try EnrollmentCipher.open(altered, key: key))
        XCTAssertThrowsError(try EnrollmentCipher.open(data, key: SymmetricKey(size: .bits256)))
        XCTAssertThrowsError(try EnrollmentCipher.open(Data(data.prefix(10)), key: key))
    }

    func testInvalidRecordsRejected() {
        let key = SymmetricKey(size: .bits256)
        for record in [Enrollment(revision: 1, samples: [Data([1]), Data([2]), Data([3])]),
                       Enrollment(revision: 2, samples: []),
                       Enrollment(revision: 2, samples: [Data(), Data([1]), Data([2])])] {
            XCTAssertThrowsError(try EnrollmentCipher.seal(record, key: key))
        }
    }

    func testPoseBoundariesAndNonFiniteValues() {
        XCTAssertTrue(CapturePose.center.accepts(yaw: 0))
        XCTAssertTrue(CapturePose.left.accepts(yaw: 0.3))
        XCTAssertTrue(CapturePose.right.accepts(yaw: -0.3))
        XCTAssertFalse(CapturePose.left.accepts(yaw: 0))
        XCTAssertFalse(CapturePose.center.accepts(yaw: .nan))
        XCTAssertFalse(CapturePose.right.accepts(yaw: -.infinity))
    }

    func testExperimentalSimilarityCannotAuthorizeWithoutIdentityAndPAD() {
        let evidence = DemoEvidence(cameraAuthorized: true, enrollmentExists: true,
            singleFaceDetected: true, captureQualityApproved: true, identityMatched: false,
            livenessPassed: false, framesConsistent: true, sessionCurrent: true, spoofSuspected: false)
        XCTAssertEqual(DecisionEngine().evaluate(evidence), .denied(.identityNotMatched))
    }

    func testSystemDialogCanReturnBeforeAppRegainsFocus() {
        var gate = CaptureActivationGate()
        let session = UUID()
        gate.prepare(session)
        XCTAssertFalse(gate.consume(session, isForeground: false))
        XCTAssertTrue(gate.consume(session, isForeground: true))
        XCTAssertFalse(gate.consume(session, isForeground: true))
    }

    func testCancelledAndStaleActivationsCannotStartCamera() {
        var gate = CaptureActivationGate()
        let first = UUID(), second = UUID()
        gate.prepare(first)
        gate.cancel()
        XCTAssertFalse(gate.consume(first, isForeground: true))
        gate.prepare(second)
        XCTAssertFalse(gate.consume(first, isForeground: true))
        XCTAssertTrue(gate.consume(second, isForeground: true))
    }
}
