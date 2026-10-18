import XCTest
@testable import MacFaceGuardCore

final class RotationRingTests: XCTestCase {
    func testDirectionsMapToSegmentsCounterClockwiseFromTheRight() {
        let ring = RotationRing(segmentCount: 60)
        XCTAssertEqual(ring.segment(dx: 0.2, dy: 0), 0)
        XCTAssertEqual(ring.segment(dx: 0, dy: 0.2), 15)
        XCTAssertEqual(ring.segment(dx: -0.2, dy: 0), 30)
        XCTAssertEqual(ring.segment(dx: 0, dy: -0.2), 45)
        XCTAssertEqual(ring.segment(dx: 0.2, dy: -0.001), 0)
    }

    func testSmallHugeAndNonFiniteMovementsAreIgnored() {
        var ring = RotationRing()
        XCTAssertNil(ring.record(dx: 0.03, dy: 0.03))
        XCTAssertNil(ring.record(dx: 2, dy: 0))
        XCTAssertNil(ring.record(dx: .nan, dy: 0.2))
        XCTAssertNil(ring.record(dx: 0.2, dy: .infinity))
        XCTAssertEqual(ring.coveredCount, 0)
        XCTAssertNil(ring.largestGapCenter)
    }

    func testRecordLightsNeighboursAcrossTheWrapAround() {
        var ring = RotationRing(segmentCount: 60, spread: 2)
        XCTAssertEqual(ring.record(dx: 0.2, dy: 0), 0)
        XCTAssertEqual(ring.coveredCount, 5)
        for index in [58, 59, 0, 1, 2] { XCTAssertTrue(ring.covered[index]) }
        XCTAssertFalse(ring.covered[3])
        XCTAssertEqual(ring.largestGapCenter, 30)
    }

    func testFullCircleCompletesAndResetClears() {
        var ring = RotationRing(segmentCount: 60)
        XCTAssertFalse(ring.isComplete)
        for step in 0..<12 {
            let angle = 2 * Double.pi * Double(step) / 12
            ring.record(dx: 0.25 * cos(angle), dy: 0.25 * sin(angle))
        }
        XCTAssertEqual(ring.coverage, 1, accuracy: 0.0001)
        XCTAssertTrue(ring.isComplete)
        XCTAssertNil(ring.largestGapCenter)
        ring.reset()
        XCTAssertEqual(ring.coveredCount, 0)
        XCTAssertFalse(ring.isComplete)
    }

    func testHalfCircleIsNotEnoughAndPointsToTheMissingSide() {
        var ring = RotationRing(segmentCount: 60)
        for step in 0...6 {
            let angle = Double.pi * Double(step) / 6
            ring.record(dx: 0.25 * cos(angle), dy: 0.25 * sin(angle))
        }
        XCTAssertFalse(ring.isComplete)
        let gap = try? XCTUnwrap(ring.largestGapCenter)
        XCTAssertEqual(gap, 45)
    }

    func testNoseLiftRisesWhenLookingUpAndRejectsBadGeometry() throws {
        let front = try XCTUnwrap(FaceGeometry.noseLift(nose: 0.40, leftEyeX: 0.3, leftEyeY: 0.65, rightEyeX: 0.7, rightEyeY: 0.65))
        let up = try XCTUnwrap(FaceGeometry.noseLift(nose: 0.46, leftEyeX: 0.3, leftEyeY: 0.65, rightEyeX: 0.7, rightEyeY: 0.65))
        XCTAssertEqual(front, -0.625, accuracy: 0.0001)
        XCTAssertGreaterThan(up - front, 0.1)
        XCTAssertNil(FaceGeometry.noseLift(nose: .nan, leftEyeX: 0.3, leftEyeY: 0.65, rightEyeX: 0.7, rightEyeY: 0.65))
        XCTAssertNil(FaceGeometry.noseLift(nose: 0.4, leftEyeX: 0.5, leftEyeY: 0.65, rightEyeX: 0.52, rightEyeY: 0.65))
    }
}
