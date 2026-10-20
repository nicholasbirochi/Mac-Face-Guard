import XCTest
@testable import MacFaceGuardCore

final class UnlockRaceTests: XCTestCase {
    func testStaysOpenWhenLastKeyIsOlderThanTheScan() {
        var race = UnlockRace(started: 100)
        // Última tecla em 99 (a que acordou o Mac, por exemplo): o rosto continua.
        XCTAssertEqual(race.check(locked: true, secondsSinceKey: 2, now: 101), .open)
        XCTAssertTrue(race.claimForFace(locked: true, secondsSinceKey: 3, now: 102))
        XCTAssertEqual(race.outcome, .faceWon)
    }

    func testTypingDuringScanMakesFaceYield() {
        var race = UnlockRace(started: 100)
        XCTAssertEqual(race.check(locked: true, secondsSinceKey: 0.3, now: 101), .yielded(.typing))
        // Desistência é definitiva: nem o rosto aprovado depois vence.
        XCTAssertFalse(race.claimForFace(locked: true, secondsSinceKey: 50, now: 102))
        XCTAssertEqual(race.outcome, .yielded(.typing))
    }

    func testOtherMethodUnlockingWinsTheRace() {
        var race = UnlockRace(started: 100)
        XCTAssertFalse(race.claimForFace(locked: false, secondsSinceKey: 50, now: 101))
        XCTAssertEqual(race.outcome, .yielded(.unlocked))
    }

    func testFaceWinIsFinal() {
        var race = UnlockRace(started: 100)
        XCTAssertTrue(race.claimForFace(locked: true, secondsSinceKey: 50, now: 101))
        XCTAssertFalse(race.claimForFace(locked: true, secondsSinceKey: 50, now: 101.1))
        XCTAssertEqual(race.check(locked: false, secondsSinceKey: 0, now: 101.2), .faceWon)
    }

    func testInvalidClockCountsAsKey() {
        XCTAssertTrue(UnlockRace.keyPressed(since: 100, secondsSinceKey: .nan, now: 101))
        XCTAssertTrue(UnlockRace.keyPressed(since: 100, secondsSinceKey: -1, now: 101))
        XCTAssertTrue(UnlockRace.keyPressed(since: 100, secondsSinceKey: .infinity, now: 101))
        XCTAssertFalse(UnlockRace.keyPressed(since: 100, secondsSinceKey: 1.5, now: 101))
        XCTAssertTrue(UnlockRace.keyPressed(since: 100, secondsSinceKey: 1, now: 101))
    }
}
