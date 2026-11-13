import XCTest
@testable import GestureEngine

final class GestureEngineTests: XCTestCase {
    func testGestureIDsAreStableAndComplete() {
        XCTAssertEqual(GestureID.allCases.count, 32)
        for (i, id) in GestureID.allCases.enumerated() {
            XCTAssertEqual(id.rawValue, "G\(i + 1)")
        }
    }

    func testTouchTraceRoundTripsThroughJSON() throws {
        let trace: TouchTrace = [
            TouchEvent(touchID: 0, phase: .began, kind: .finger, timestamp: 1.0, x: 100, y: 200),
            TouchEvent(touchID: 0, phase: .moved, kind: .finger, timestamp: 1.008, x: 104, y: 201, isPredicted: true),
            TouchEvent(touchID: 1, phase: .ended, kind: .pencil, timestamp: 1.1, x: 5, y: 6, force: 0.5, altitude: 0.8),
        ]
        let data = try JSONEncoder().encode(trace)
        XCTAssertEqual(try JSONDecoder().decode(TouchTrace.self, from: data), trace)
    }

    func testGestureEventRoundTripsThroughJSON() throws {
        let e = GestureEvent(gesture: .g19, phase: .changed, timestamp: 3, x: 1, y: 2, speed: 300, fingerCount: 2, magnitude: 1.5)
        let data = try JSONEncoder().encode(e)
        XCTAssertEqual(try JSONDecoder().decode(GestureEvent.self, from: data), e)
    }

    func testPalmRejectsLargeContactForItsWholeLifetime() {
        var palm = PalmRejection(maxFingerRadius: 40)
        XCTAssertFalse(palm.accept(.init(touchID: 2, phase: .began, kind: .finger, timestamp: 0, x: 0, y: 0, majorRadius: 60)))
        XCTAssertFalse(palm.accept(.init(touchID: 2, phase: .moved, kind: .finger, timestamp: 0.1, x: 5, y: 0, majorRadius: 20)))
        XCTAssertFalse(palm.accept(.init(touchID: 2, phase: .ended, kind: .finger, timestamp: 0.2, x: 5, y: 0)))
        // Slot is free again afterwards.
        XCTAssertTrue(palm.accept(.init(touchID: 2, phase: .began, kind: .finger, timestamp: 1, x: 0, y: 0, majorRadius: 10)))
    }

    func testFingerRejectedWhilePencilIsDown() {
        var palm = PalmRejection()
        XCTAssertTrue(palm.accept(.init(touchID: 0, phase: .began, kind: .pencil, timestamp: 0, x: 0, y: 0)))
        XCTAssertFalse(palm.accept(.init(touchID: 1, phase: .began, kind: .finger, timestamp: 0.1, x: 0, y: 0)))
        XCTAssertTrue(palm.accept(.init(touchID: 0, phase: .ended, kind: .pencil, timestamp: 0.2, x: 0, y: 0)))
        XCTAssertTrue(palm.accept(.init(touchID: 3, phase: .began, kind: .finger, timestamp: 0.3, x: 0, y: 0)))
    }

    func testConfigMatchesAppendixA() {
        let c = GestureConfig.default
        XCTAssertEqual(c.tapMaxDuration, 0.25)
        XCTAssertEqual(c.tapMaxMovement, 10)
        XCTAssertEqual(c.multiTapMaxInterval, 0.3)
        XCTAssertEqual(c.longPressMinDuration, 0.4)
        XCTAssertEqual(c.dwellMinDuration, 0.3)
        XCTAssertEqual(c.edgeZone, 20)
        XCTAssertEqual(c.idleDelay, 5)
    }
}
