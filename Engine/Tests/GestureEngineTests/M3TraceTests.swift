import XCTest
@testable import GestureEngine

/// M3 (G8 to G15): a positive and a near-miss trace for each gesture.
final class M3TraceTests: XCTestCase {

    // MARK: G8 Flick

    func testG8FlickShortFastStrokeLiftedWhileMoving() {
        var b = TraceBuilder(); b.drag(at: 0, from: (100, 300), to: (260, 300), duration: 0.12)
        let out = runTrace(b.events)
        let e = out.first(.g8, .fired)
        XCTAssertNotNil(e)
        XCTAssertGreaterThan(e!.speed, 800)
        XCTAssertEqual(e!.directionX, 1, accuracy: 0.01)
        XCTAssertFalse(out.has(.g31, .fired), "the flick claims the lift")
    }

    func testG8NearMissFingerStopsBeforeLift() {
        var b = TraceBuilder()
        b.drag(at: 0, from: (100, 300), to: (260, 300), duration: 0.12, lift: false)
        b.add(TouchEvent(touchID: 0, phase: .ended, kind: .finger, timestamp: 0.3, x: 260, y: 300))
        XCTAssertFalse(runTrace(b.events).has(.g8, .fired))
    }

    func testG8NearMissLongStrokeEndingFast() {
        var b = TraceBuilder(); b.drag(at: 0, from: (100, 300), to: (900, 300), duration: 0.6)
        XCTAssertFalse(runTrace(b.events).has(.g8, .fired), "a long drawing must not fly away")
    }

    // MARK: G9 Scribble

    func testG9ScribbleUpgradesMidStrokeAndCancelsInk() {
        let pts = zigzagPoints(x: 200, y: 300, width: 40, height: 50, legs: 8)
        var b = TraceBuilder(); b.path(at: 0, points: pts, duration: 0.6)
        let out = runTrace(b.events)
        let began = out.first(.g9, .began)
        XCTAssertNotNil(began)
        XCTAssertLessThan(began!.timestamp, 0.6, "upgrades before the lift (R1)")
        XCTAssertTrue(out.has(.g7, .began))
        XCTAssertTrue(out.has(.g7, .cancelled), "the scribble is not ink")
        XCTAssertFalse(out.has(.g7, .ended))
        XCTAssertTrue(out.has(.g9, .ended))
        XCTAssertFalse(out.has(.g12, .fired))
    }

    func testG9NearMissOnlyTwoReversals() {
        let pts: [(Float, Float)] = [(200, 300), (260, 300), (200, 305), (260, 310)]
        var b = TraceBuilder(); b.path(at: 0, points: pts, duration: 0.5)
        XCTAssertFalse(runTrace(b.events).has(.g9, .began))
    }

    func testG9NearMissWideBackAndForth() {
        let pts: [(Float, Float)] = [(100, 300), (400, 300), (100, 310), (400, 320), (100, 330)]
        var b = TraceBuilder(); b.path(at: 0, points: pts, duration: 0.9)
        XCTAssertFalse(runTrace(b.events).has(.g9, .began), "not a small area")
    }

    // MARK: G10 Circle

    func testG10Circle() {
        var b = TraceBuilder(); b.path(at: 0, points: spiralPoints(from: 80, to: 80, turns: 1.02), duration: 0.8)
        let out = runTrace(b.events)
        let e = out.first(.g10, .fired)
        XCTAssertNotNil(e)
        XCTAssertEqual(e!.size, 80, accuracy: 6)
        XCTAssertEqual(e!.x, 300, accuracy: 6)
        XCTAssertTrue(out.has(.g7, .ended), "the ring stays as ink")
        XCTAssertFalse(out.has(.g31, .fired))
    }

    func testG10NearMissHalfCircle() {
        var b = TraceBuilder(); b.path(at: 0, points: spiralPoints(from: 80, to: 80, turns: 0.5), duration: 0.5)
        XCTAssertFalse(runTrace(b.events).has(.g10, .fired))
    }

    func testG10NearMissSquashedLoop() {
        let pts = (0...120).map { k -> (Float, Float) in
            let a = Float(k) / 120 * 2 * .pi
            return (300 + 150 * cos(a), 400 + 30 * sin(a))
        }
        var b = TraceBuilder(); b.path(at: 0, points: pts, duration: 0.8)
        XCTAssertFalse(runTrace(b.events).has(.g10, .fired))
    }

    // MARK: G11 Spiral

    func testG11InwardSpiral() {
        var b = TraceBuilder(); b.path(at: 0, points: spiralPoints(from: 150, to: 20, turns: 2.2), duration: 1.2)
        let out = runTrace(b.events)
        let e = out.first(.g11, .fired)
        XCTAssertNotNil(e)
        XCTAssertGreaterThan(e!.magnitude, 1.5, "positive = inward, value = turns")
        XCTAssertFalse(out.has(.g10, .fired))
    }

    func testG11OutwardSpiral() {
        var b = TraceBuilder(); b.path(at: 0, points: spiralPoints(from: 20, to: 150, turns: 2.2), duration: 1.2)
        let e = runTrace(b.events).first(.g11, .fired)
        XCTAssertNotNil(e)
        XCTAssertLessThan(e!.magnitude, -1.5)
    }

    func testG11NearMissOneTurn() {
        var b = TraceBuilder(); b.path(at: 0, points: spiralPoints(from: 150, to: 40, turns: 1.0), duration: 0.8)
        XCTAssertFalse(runTrace(b.events).has(.g11, .fired))
    }

    // MARK: G12 Zigzag

    func testG12Zigzag() {
        var b = TraceBuilder(); b.path(at: 0, points: zigzagPoints(width: 400, height: 120, legs: 5), duration: 0.9)
        let out = runTrace(b.events)
        XCTAssertTrue(out.has(.g12, .fired))
        XCTAssertFalse(out.has(.g9, .began))
    }

    func testG12ShallowHandDrawnZigzag() {
        // About 80° corners, like a quick hand-drawn zigzag.
        var b = TraceBuilder(); b.path(at: 0, points: zigzagPoints(width: 360, height: 75, legs: 4), duration: 0.8)
        XCTAssertTrue(runTrace(b.events).has(.g12, .fired))
    }

    func testG12NearMissGentleWave() {
        let pts = (0...80).map { k -> (Float, Float) in
            let f = Float(k) / 80
            return (100 + 400 * f, 400 + 40 * sin(f * 4 * .pi))
        }
        var b = TraceBuilder(); b.path(at: 0, points: pts, duration: 0.9)
        XCTAssertFalse(runTrace(b.events).has(.g12, .fired))
    }

    // MARK: G13 Slingshot

    func testG13SlingshotAnchorsAtFirstTap() {
        var b = TraceBuilder()
        b.tap(at: 0, x: 200, y: 300)
        b.drag(at: 0.2, from: (202, 300), to: (300, 400), duration: 0.4)
        let out = runTrace(b.events)
        let began = out.first(.g13, .began)
        XCTAssertNotNil(began)
        XCTAssertEqual(began!.originX, 200)
        XCTAssertEqual(began!.originY, 300)
        let end = out.first(.g13, .ended)
        XCTAssertNotNil(end)
        XCTAssertGreaterThan(end!.magnitude, 120, "stretch distance")
        XCTAssertFalse(out.has(.g7, .began), "the slingshot is not ink")
        XCTAssertTrue(out.has(.g2, .cancelled), "the provisional double tap yields")
    }

    func testG13NearMissSecondTouchTooLate() {
        var b = TraceBuilder()
        b.tap(at: 0, x: 200, y: 300)
        b.drag(at: 0.6, from: (202, 300), to: (300, 400), duration: 0.4)
        let out = runTrace(b.events)
        XCTAssertFalse(out.has(.g13, .began))
        XCTAssertTrue(out.has(.g7, .began))
    }

    // MARK: G14 Hold-drag

    func testG14HoldThenDrag() {
        var b = TraceBuilder()
        b.add(TouchEvent(touchID: 0, phase: .began, kind: .finger, timestamp: 0, x: 200, y: 300))
        b.drag(at: 0.6, from: (200, 300), to: (350, 300), duration: 0.5, lift: false)
        b.events.removeAll { $0.phase == .began && $0.timestamp == 0.6 }
        b.add(TouchEvent(touchID: 0, phase: .ended, kind: .finger, timestamp: 1.1, x: 350, y: 300))
        let out = runTrace(b.events)
        XCTAssertTrue(out.has(.g5, .began))
        XCTAssertTrue(out.has(.g14, .began))
        XCTAssertTrue(out.has(.g14, .changed))
        XCTAssertTrue(out.has(.g14, .ended))
        XCTAssertFalse(out.has(.g6, .fired), "dragging is not a release")
        XCTAssertFalse(out.has(.g7, .began), "the magnet does not draw")
    }

    func testG14NearMissDragWithoutHold() {
        var b = TraceBuilder(); b.drag(at: 0, from: (200, 300), to: (350, 300), duration: 0.5)
        XCTAssertFalse(runTrace(b.events).has(.g14, .began))
    }

    // MARK: G15 Dwell

    func testG15DwellMidStroke() {
        var b = TraceBuilder()
        b.path(at: 0, points: [(100, 300), (300, 300)], duration: 0.6, pauseAt: 0.5, pause: 0.6)
        let out = runTrace(b.events)
        let began = out.first(.g15, .began)
        XCTAssertNotNil(began)
        XCTAssertEqual(began!.x, 200, accuracy: 4)
        let grow = out.filter { $0.gesture == .g15 && $0.phase == .changed }.map(\.magnitude)
        XCTAssertEqual(grow, grow.sorted())
        XCTAssertTrue(out.has(.g15, .ended))
        XCTAssertTrue(out.has(.g7, .ended), "the stroke carries on as ink")
    }

    func testG15NearMissShortPause() {
        var b = TraceBuilder()
        b.path(at: 0, points: [(100, 300), (300, 300)], duration: 0.6, pauseAt: 0.5, pause: 0.2)
        XCTAssertFalse(runTrace(b.events).has(.g15, .began))
    }

    // MARK: Pencil stays draw-only (R6)

    func testPencilCircleIsJustInk() {
        var b = TraceBuilder()
        b.path(at: 0, points: spiralPoints(from: 80, to: 80, turns: 1.02), duration: 0.8, kind: .pencil)
        let out = runTrace(b.events)
        XCTAssertFalse(out.has(.g10, .fired))
        XCTAssertTrue(out.has(.g7, .ended))
    }
}
