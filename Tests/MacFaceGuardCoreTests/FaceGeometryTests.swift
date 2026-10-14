import XCTest
import CoreGraphics
@testable import MacFaceGuardCore

final class FaceGeometryTests: XCTestCase {
    func testSmallTurnRespondsToNoseMovementAndIsTranslationInvariant() throws {
        let front = try XCTUnwrap(FaceGeometry.noseOffset(nose: 0.5, leftEye: 0.3, rightEye: 0.7))
        let side = try XCTUnwrap(FaceGeometry.noseOffset(nose: 0.54, leftEye: 0.3, rightEye: 0.7))
        let moved = try XCTUnwrap(FaceGeometry.noseOffset(nose: 0.64, leftEye: 0.4, rightEye: 0.8))
        XCTAssertEqual(front, 0, accuracy: 0.0001)
        XCTAssertEqual(side, 0.1, accuracy: 0.0001)
        XCTAssertEqual(side, moved, accuracy: 0.0001)
        XCTAssertTrue(CapturePose.eitherSide.accepts(quality: 0.15, yaw: side - front))
    }

    func testMissingOrInvalidLandmarkGeometryFailsClosed() {
        XCTAssertNil(FaceGeometry.noseOffset(nose: .nan, leftEye: 0.3, rightEye: 0.7))
        XCTAssertNil(FaceGeometry.noseOffset(nose: 0.5, leftEye: 0.5, rightEye: 0.5))
        XCTAssertNil(FaceGeometry.noseOffset(nose: 2, leftEye: 0.3, rightEye: 0.7))
    }

    func testOnlyNearIdenticalFaceBoxesAreDeduplicated() {
        let a = CGRect(x: 0.3, y: 0.2, width: 0.4, height: 0.5)
        let duplicate = CGRect(x: 0.31, y: 0.21, width: 0.4, height: 0.5)
        XCTAssertEqual(FaceGeometry.uniqueFaceIndices([a, duplicate]), [0])
        let distinct = CGRect(x: 0.02, y: 0.2, width: 0.2, height: 0.4)
        XCTAssertEqual(FaceGeometry.uniqueFaceIndices([a, distinct]).count, 2)
        let partiallyOverlapping = CGRect(x: 0.4, y: 0.2, width: 0.4, height: 0.5)
        XCTAssertEqual(FaceGeometry.uniqueFaceIndices([a, partiallyOverlapping]).count, 2)
        let contained = CGRect(x: 0.4, y: 0.3, width: 0.1, height: 0.1)
        XCTAssertEqual(FaceGeometry.uniqueFaceIndices([a, contained]).count, 2)
    }
}
