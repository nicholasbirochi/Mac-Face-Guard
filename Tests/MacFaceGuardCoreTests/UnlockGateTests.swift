import XCTest
@testable import MacFaceGuardCore

final class UnlockGateTests: XCTestCase {
    private let real = PresentationAssessment(label: .real, realScore: 0.95, isLive: true)
    private let weak = PresentationAssessment(label: .real, realScore: 0.6, isLive: false)
    private let fake = PresentationAssessment(label: .fake2D, realScore: 0.1, isLive: false)

    private func gate(_ threshold: Float = 0.5) -> UnlockGate { UnlockGate(threshold: threshold, started: 100) }

    func testUnlocksOnlyAfterMatchAndLivenessStreaks() {
        var g = gate()
        XCTAssertEqual(g.record(locked: true, faceCount: 1, similarity: 0.7, presentation: real, now: 100.2), .continue)
        XCTAssertEqual(g.record(locked: true, faceCount: 1, similarity: 0.7, presentation: real, now: 100.4), .continue)
        XCTAssertEqual(g.record(locked: true, faceCount: 1, similarity: 0.7, presentation: real, now: 100.6), .unlock)
        // Depois de decidir, nunca autoriza de novo.
        XCTAssertEqual(g.record(locked: true, faceCount: 1, similarity: 0.7, presentation: real, now: 100.8), .abort(.timeout))
    }

    func testMissingEvidenceResetsStreaks() {
        var g = gate()
        _ = g.record(locked: true, faceCount: 1, similarity: 0.7, presentation: real, now: 100.2)
        _ = g.record(locked: true, faceCount: 1, similarity: 0.7, presentation: real, now: 100.4)
        for (count, similarity, pad) in [(2, Float(0.7), real), (1, nil, real), (1, 0.7, nil), (0, nil, nil)] as [(Int, Float?, PresentationAssessment?)] {
            var copy = g
            XCTAssertEqual(copy.record(locked: true, faceCount: count, similarity: similarity, presentation: pad, now: 100.6), .continue)
            XCTAssertEqual(copy.matches, 0)
            XCTAssertEqual(copy.live, 0)
        }
    }

    func testWeakLivenessNeverUnlocks() {
        var g = gate()
        for i in 1...10 {
            XCTAssertEqual(g.record(locked: true, faceCount: 1, similarity: 0.9, presentation: weak, now: 100 + Double(i) * 0.2), .continue)
        }
    }

    func testSpoofAborts() {
        var g = gate()
        XCTAssertEqual(g.record(locked: true, faceCount: 1, similarity: 0.9, presentation: fake, now: 100.2), .abort(.spoof))
    }

    func testWrongFaceAbortsAfterLimit() {
        var g = gate()
        XCTAssertEqual(g.record(locked: true, faceCount: 1, similarity: 0.2, presentation: real, now: 101), .continue)
        XCTAssertEqual(g.record(locked: true, faceCount: 1, similarity: 0.2, presentation: real, now: 102.5), .continue)
        XCTAssertEqual(g.record(locked: true, faceCount: 1, similarity: 0.2, presentation: real, now: 103), .abort(.wrongFace))
    }

    func testUnlockedScreenAndTimeoutAbort() {
        var g = gate()
        XCTAssertEqual(g.record(locked: false, faceCount: 1, similarity: 0.9, presentation: real, now: 100.2), .abort(.notLocked))
        var late = gate()
        XCTAssertEqual(late.record(locked: true, faceCount: 1, similarity: 0.9, presentation: real, now: 116), .abort(.timeout))
        var early = gate()
        XCTAssertEqual(early.record(locked: true, faceCount: 1, similarity: 0.9, presentation: real, now: 99), .abort(.timeout))
    }

    func testThresholdIsClampedFailClosed() {
        XCTAssertEqual(gate(0.1).threshold, UnlockGate.minimumThreshold)
        XCTAssertEqual(gate(0.99).threshold, UnlockGate.maximumThreshold)
        XCTAssertEqual(gate(.nan).threshold, UnlockGate.maximumThreshold)
        var g = gate(0.6)
        for i in 1...5 {
            XCTAssertEqual(g.record(locked: true, faceCount: 1, similarity: 0.59, presentation: real, now: 100 + Double(i) * 0.1), .continue)
        }
    }
}
