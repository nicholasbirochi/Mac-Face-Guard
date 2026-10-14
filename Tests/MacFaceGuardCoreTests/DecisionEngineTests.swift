import XCTest
@testable import MacFaceGuardCore

final class DecisionEngineTests: XCTestCase {
    private func evidence(
        camera: Bool = true, enrolled: Bool = true, single: Bool = true,
        quality: Bool = true, match: Bool = true, live: Bool = true,
        consistent: Bool = true, current: Bool = true, spoof: Bool = false
    ) -> DemoEvidence {
        DemoEvidence(cameraAuthorized: camera, enrollmentExists: enrolled,
                     singleFaceDetected: single, captureQualityApproved: quality,
                     identityMatched: match, livenessPassed: live,
                     framesConsistent: consistent, sessionCurrent: current,
                     spoofSuspected: spoof)
    }

    func testAllGatesPassForDemoOnly() {
        XCTAssertEqual(DecisionEngine().evaluate(evidence()), .acceptedForDemo)
    }
    func testCameraDenied() {
        XCTAssertEqual(DecisionEngine().evaluate(evidence(camera: false)), .denied(.cameraNotAuthorized))
    }
    func testNoEnrollment() {
        XCTAssertEqual(DecisionEngine().evaluate(evidence(enrolled: false)), .denied(.noEnrollment))
    }
    func testNoOrMultipleFaces() {
        XCTAssertEqual(DecisionEngine().evaluate(evidence(single: false)), .denied(.faceCountNotOne))
    }
    func testPoorCaptureQuality() {
        XCTAssertEqual(DecisionEngine().evaluate(evidence(quality: false)), .denied(.captureQualityInsufficient))
    }
    func testSpoofFailsEvenWhenOtherGatesPass() {
        XCTAssertEqual(DecisionEngine().evaluate(evidence(spoof: true)), .denied(.possibleSpoof))
    }
    func testWrongFace() {
        XCTAssertEqual(DecisionEngine().evaluate(evidence(match: false)), .denied(.identityNotMatched))
    }
    func testInconclusiveLivenessMustDeny() {
        XCTAssertEqual(DecisionEngine().evaluate(evidence(live: false)), .denied(.livenessNotProven))
    }
    func testInconsistentFrames() {
        XCTAssertEqual(DecisionEngine().evaluate(evidence(consistent: false)), .denied(.inconsistentFrames))
    }
    func testExpiredSession() {
        XCTAssertEqual(DecisionEngine().evaluate(evidence(current: false)), .denied(.expiredSession))
    }
}
