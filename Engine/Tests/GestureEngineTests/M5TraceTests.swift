import XCTest
@testable import GestureEngine

/// M5 (G27 to G30, G32): positive and near-miss traces.
final class M5TraceTests: XCTestCase {
    let ink = MockInk()

    // MARK: G27 Touch a stroke

    func testG27TapOnInkPlucksTheStroke() {
        var b = TraceBuilder(); b.tap(at: 0, x: 250, y: 305)
        let out = runTrace(b.events, ink: ink)
        let e = out.first(.g27, .began)
        XCTAssertNotNil(e)
        XCTAssertEqual(e!.timestamp, 0, "R1: reacts on touch-down")
        XCTAssertEqual(e!.y, 300, "snapped onto the stroke")
        XCTAssertEqual(e!.size, 150, accuracy: 0.01, "distance along the stroke")
        XCTAssertEqual(e!.magnitude, 400, "stroke length sets ring time")
        XCTAssertEqual(e!.targetID, 7)
        XCTAssertTrue(out.has(.g27, .ended))
        XCTAssertFalse(out.has(.g1, .began), "R2: contextual beats the single-finger tap")
        XCTAssertFalse(out.has(.g31, .fired))
    }

    func testG27NearMissTapBesideTheInk() {
        var b = TraceBuilder(); b.tap(at: 0, x: 250, y: 340)
        let out = runTrace(b.events, ink: ink)
        XCTAssertFalse(out.has(.g27, .began))
        XCTAssertTrue(out.has(.g1, .ended))
    }

    func testG27DragFromInkDrawsInstead() {
        var b = TraceBuilder(); b.drag(at: 0, from: (250, 300), to: (250, 450), duration: 0.4)
        let out = runTrace(b.events, ink: ink)
        XCTAssertTrue(out.has(.g27, .cancelled))
        XCTAssertTrue(out.has(.g7, .ended))
        XCTAssertFalse(out.has(.g28, .fired), "starting on a stroke is not crossing it")
    }

    // MARK: G28 Cross a stroke

    func testG28NewStrokeCrossesInk() {
        var b = TraceBuilder(); b.drag(at: 0, from: (300, 150), to: (300, 450), duration: 0.4)
        let out = runTrace(b.events, ink: ink)
        XCTAssertEqual(out.count(.g28, .fired), 1)
        let e = out.first(.g28, .fired)!
        XCTAssertEqual(e.x, 300, accuracy: 0.5); XCTAssertEqual(e.y, 300, accuracy: 0.5)
        XCTAssertEqual(e.originX, 1, "the older stroke's direction")
        XCTAssertGreaterThan(e.speed, 0)
    }

    func testG28NearMissStrokeStopsShort() {
        var b = TraceBuilder(); b.drag(at: 0, from: (300, 150), to: (300, 290), duration: 0.4)
        XCTAssertFalse(runTrace(b.events, ink: ink).has(.g28, .fired))
    }

    func testG28NearMissNoInk() {
        var b = TraceBuilder(); b.drag(at: 0, from: (300, 150), to: (300, 450), duration: 0.4)
        XCTAssertFalse(runTrace(b.events).has(.g28, .fired))
    }

    // MARK: G29 Close a shape

    func testG29ClosedSquareFills() {
        let square: [(Float, Float)] = [(100, 100), (300, 100), (300, 300), (100, 300), (102, 104)]
        var b = TraceBuilder(); b.path(at: 0, points: square, duration: 1.0)
        let out = runTrace(b.events)
        let e = out.first(.g29, .fired)
        XCTAssertNotNil(e)
        XCTAssertEqual(e!.magnitude, 40000, accuracy: 2500, "area")
        XCTAssertEqual(e!.originX, 200, accuracy: 25, "centroid")
        XCTAssertFalse(out.has(.g10, .fired)); XCTAssertFalse(out.has(.g12, .fired))
        XCTAssertTrue(out.has(.g7, .ended), "the outline stays as ink")
    }

    func testG29NearMissOpenShape() {
        let open: [(Float, Float)] = [(100, 100), (300, 100), (300, 300), (100, 300), (100, 180)]
        var b = TraceBuilder(); b.path(at: 0, points: open, duration: 1.0)
        XCTAssertFalse(runTrace(b.events).has(.g29, .fired))
    }

    func testG29NearMissCircleIsG10() {
        var b = TraceBuilder(); b.path(at: 0, points: spiralPoints(from: 80, to: 80, turns: 1.02), duration: 0.8)
        let out = runTrace(b.events)
        XCTAssertTrue(out.has(.g10, .fired))
        XCTAssertFalse(out.has(.g29, .fired))
    }

    // MARK: G30 Edge touch

    func testG30EdgeTouchPushesInward() {
        var b = TraceBuilder(); b.tap(at: 0, x: 8, y: 400)
        let out = runTrace(b.events, canvas: (400, 800))
        let e = out.first(.g30, .fired)
        XCTAssertNotNil(e)
        XCTAssertEqual(e!.directionX, 1); XCTAssertEqual(e!.directionY, 0)
        XCTAssertEqual(e!.magnitude, 0.5, accuracy: 0.01, "position along the edge")
        XCTAssertFalse(out.has(.g1, .began))
        XCTAssertFalse(out.has(.g31, .fired), "one reaction per edge touch")
    }

    func testG30BottomEdge() {
        var b = TraceBuilder(); b.tap(at: 0, x: 200, y: 790)
        XCTAssertEqual(runTrace(b.events, canvas: (400, 800)).first(.g30, .fired)?.directionY, -1)
    }

    func testG30NearMissAwayFromEdge() {
        var b = TraceBuilder(); b.tap(at: 0, x: 30, y: 400)
        XCTAssertFalse(runTrace(b.events, canvas: (400, 800)).has(.g30, .fired))
    }

    // MARK: G32 Idle

    func testG32IdleAfterFiveSecondsAndEndsOnTouch() {
        var b = TraceBuilder()
        b.tap(at: 0, x: 200, y: 200)
        b.tap(at: 7, x: 210, y: 220)
        let out = runTrace(b.events, idleCheck: true)
        let began = out.first(.g32, .began)
        XCTAssertNotNil(began)
        XCTAssertEqual(began!.timestamp, 5.08, accuracy: 0.05)
        XCTAssertEqual(began!.x, 200, "at the last touch location")
        let ended = out.first(.g32, .ended)
        XCTAssertNotNil(ended)
        XCTAssertEqual(ended!.timestamp, 7, "any touch interrupts it instantly")
        let order = out.firstIndex { $0.gesture == .g32 && $0.phase == .ended }!
        XCTAssertLessThan(order, out.firstIndex { $0.gesture == .g1 && $0.timestamp == 7 }!, "ends before the touch reacts")
    }

    func testG32EndsOnActivityOutsideTheCanvas() {
        let engine = GestureEngine()
        var out: [GestureEvent] = []
        var t = 0.0
        while t < 6 { engine.tick(now: t) { out.append($0) }; t += 0.1 }
        XCTAssertTrue(out.has(.g32, .began))
        engine.noteActivity(at: t)          // e.g. a tap on the Undo button
        engine.tick(now: t + 0.01) { out.append($0) }
        XCTAssertTrue(out.has(.g32, .ended))
    }

    func testG32NearMissShortPause() {
        var b = TraceBuilder()
        b.tap(at: 0); b.tap(at: 4)
        XCTAssertFalse(runTrace(b.events, tail: 0.5, idleCheck: true).has(.g32, .began))
    }

    func testG32NotWhileAFingerRests() {
        var b = TraceBuilder(); b.hold(at: 0, duration: 7)
        XCTAssertFalse(runTrace(b.events, tail: 0.5, idleCheck: true).has(.g32, .began))
    }
}
