import XCTest
@testable import GestureEngine

/// M4 (G16 to G26): positive and near-miss traces. Synthetic only: the Simulator
/// cannot produce 3+ touches, so these and the device are the only checks.
final class M4TraceTests: XCTestCase {

    /// Several fingers moving together: `paths[k]` is finger k's (from, to).
    private func fingers(_ paths: [((Float, Float), (Float, Float))], at t: Double = 0, stagger: Double = 0.02,
                         duration: Double, holdBefore: Double = 0, lift: Bool = true) -> TraceBuilder {
        var b = TraceBuilder()
        for (k, p) in paths.enumerated() {
            b.add(TouchEvent(touchID: UInt16(k), phase: .began, kind: .finger, timestamp: t + Double(k) * stagger, x: p.0.0, y: p.0.1))
        }
        let start = t + Double(paths.count - 1) * stagger + holdBefore
        let steps = max(2, Int(duration * 120))
        for n in 1...steps {
            let f = Float(n) / Float(steps)
            for (k, p) in paths.enumerated() {
                b.add(TouchEvent(touchID: UInt16(k), phase: .moved, kind: .finger, timestamp: start + duration * Double(f),
                                 x: p.0.0 + (p.1.0 - p.0.0) * f, y: p.0.1 + (p.1.1 - p.0.1) * f))
            }
        }
        if lift {
            for (k, p) in paths.enumerated() {
                b.add(TouchEvent(touchID: UInt16(k), phase: .ended, kind: .finger, timestamp: start + duration + 0.001 * Double(k),
                                 x: p.1.0, y: p.1.1))
            }
        }
        return b
    }

    private func tap(_ n: Int, duration: Double = 0.12, move: Float = 0) -> TraceBuilder {
        var b = TraceBuilder()
        for k in 0..<n {
            b.add(TouchEvent(touchID: UInt16(k), phase: .began, kind: .finger, timestamp: Double(k) * 0.02, x: 100 + Float(k) * 70, y: 300))
        }
        for k in 0..<n {
            b.add(TouchEvent(touchID: UInt16(k), phase: .ended, kind: .finger, timestamp: duration + Double(k) * 0.005,
                             x: 100 + Float(k) * 70 + (k == 0 ? move : 0), y: 300))
        }
        return b
    }

    // MARK: Taps (G16, G22, G23)

    func testG16TwoFingerTap() {
        let out = runTrace(tap(2).events)
        XCTAssertTrue(out.has(.g16, .began))
        XCTAssertTrue(out.has(.g16, .ended))
        let e = out.first(.g16, .ended)!
        XCTAssertEqual(e.touchPoints.count, 4, "both finger positions travel with the event")
        XCTAssertFalse(out.has(.g1, .ended), "R2: multi-finger beats single-finger")
        XCTAssertFalse(out.has(.g31, .fired))
    }

    func testG16NearMissHeldTooLong() {
        let out = runTrace(tap(2, duration: 0.4).events)
        XCTAssertFalse(out.has(.g16, .ended))
        XCTAssertTrue(out.has(.g16, .cancelled))
    }

    func testG16NearMissFingerSlides() {
        XCTAssertFalse(runTrace(tap(2, move: 14).events).has(.g16, .ended))
    }

    func testG22ThreeFingerTapUpgradesProgressively() {
        let out = runTrace(tap(3).events)
        XCTAssertTrue(out.has(.g16, .began), "R1: two fingers react before the third lands")
        XCTAssertTrue(out.has(.g16, .cancelled))
        XCTAssertTrue(out.has(.g22, .ended))
        XCTAssertEqual(out.first(.g22, .ended)?.fingerCount, 3)
    }

    func testG23FourAndFiveFingerSplash() {
        XCTAssertTrue(runTrace(tap(4).events).has(.g23, .ended))
        let five = runTrace(tap(5).events)
        XCTAssertEqual(five.first(.g23, .ended)?.magnitude, 5, "finger count sets splash size")
        XCTAssertFalse(five.has(.g22, .ended))
    }

    func testG23NearMissThreeFingers() {
        XCTAssertFalse(runTrace(tap(3).events).has(.g23, .began))
    }

    // MARK: Two-finger continuous (G17 to G21)

    func testG17TwoFingerDrag() {
        let out = runTrace(fingers([((100, 300), (100, 500)), ((180, 300), (180, 500))], duration: 0.5).events)
        XCTAssertTrue(out.has(.g17, .began))
        XCTAssertTrue(out.has(.g17, .changed))
        XCTAssertTrue(out.has(.g17, .ended))
        let e = out.first(.g17, .changed)!
        XCTAssertEqual(e.size, 80, accuracy: 1, "finger gap sets ribbon width")
        XCTAssertFalse(out.has(.g7, .began), "session fingers do not draw")
        XCTAssertFalse(out.has(.g18, .began)); XCTAssertFalse(out.has(.g20, .began))
    }

    func testG18PinchIn() {
        let out = runTrace(fingers([((100, 300), (180, 300)), ((300, 300), (220, 300))], duration: 0.4).events)
        XCTAssertTrue(out.has(.g18, .began))
        XCTAssertTrue(out.has(.g18, .ended))
        XCTAssertLessThan(out.first(.g18, .ended)!.magnitude, 1)
        XCTAssertFalse(out.has(.g19, .began))
    }

    func testG19PinchOut() {
        let out = runTrace(fingers([((180, 300), (100, 300)), ((220, 300), (300, 300))], duration: 0.4).events)
        XCTAssertTrue(out.has(.g19, .began))
        XCTAssertGreaterThan(out.first(.g19, .ended)!.magnitude, 1)
    }

    func testG20Rotate() {
        // Two fingers turning 90° around (200, 300).
        var b = TraceBuilder()
        b.add(TouchEvent(touchID: 0, phase: .began, kind: .finger, timestamp: 0, x: 120, y: 300))
        b.add(TouchEvent(touchID: 1, phase: .began, kind: .finger, timestamp: 0.02, x: 280, y: 300))
        for n in 1...48 {
            let a = Float(n) / 48 * .pi / 2, t = 0.02 + Double(n) / 120
            b.add(TouchEvent(touchID: 0, phase: .moved, kind: .finger, timestamp: t, x: 200 - 80 * cos(a), y: 300 - 80 * sin(a)))
            b.add(TouchEvent(touchID: 1, phase: .moved, kind: .finger, timestamp: t, x: 200 + 80 * cos(a), y: 300 + 80 * sin(a)))
        }
        b.add(TouchEvent(touchID: 0, phase: .ended, kind: .finger, timestamp: 0.45, x: 200, y: 220))
        b.add(TouchEvent(touchID: 1, phase: .ended, kind: .finger, timestamp: 0.45, x: 200, y: 380))
        let out = runTrace(b.events)
        XCTAssertTrue(out.has(.g20, .began))
        XCTAssertEqual(out.first(.g20, .ended)!.magnitude, .pi / 2, accuracy: 0.15, "total rotation in radians")
        XCTAssertFalse(out.has(.g17, .began)); XCTAssertFalse(out.has(.g18, .began))
    }

    func testG21Orbit() {
        var b = TraceBuilder()
        b.add(TouchEvent(touchID: 0, phase: .began, kind: .finger, timestamp: 0, x: 200, y: 300))
        b.add(TouchEvent(touchID: 1, phase: .began, kind: .finger, timestamp: 0.3, x: 300, y: 300))
        for n in 1...120 {
            let a = Float(n) / 120 * 2 * .pi, t = 0.3 + Double(n) / 120
            b.add(TouchEvent(touchID: 1, phase: .moved, kind: .finger, timestamp: t, x: 200 + 100 * cos(a), y: 300 + 100 * sin(a)))
        }
        b.add(TouchEvent(touchID: 1, phase: .ended, kind: .finger, timestamp: 1.31, x: 300, y: 300))
        b.add(TouchEvent(touchID: 0, phase: .ended, kind: .finger, timestamp: 1.35, x: 200, y: 300))
        let out = runTrace(b.events)
        XCTAssertTrue(out.has(.g21, .began))
        let e = out.first(.g21, .ended)!
        XCTAssertEqual(e.magnitude, 1, accuracy: 0.15, "one revolution")
        XCTAssertEqual(e.originX, 200, "the held finger is the core")
        XCTAssertFalse(out.has(.g20, .began))
        XCTAssertFalse(out.has(.g5, .began), "the held finger is the orbit's core, not a long press (R2)")
        XCTAssertFalse(out.has(.g6, .fired))
    }

    func testG21NearMissSecondFingerMovesStraightAway() {
        var b = TraceBuilder()
        b.add(TouchEvent(touchID: 0, phase: .began, kind: .finger, timestamp: 0, x: 200, y: 300))
        b.drag(1, at: 0.1, from: (260, 300), to: (400, 300), duration: 0.4)
        b.add(TouchEvent(touchID: 0, phase: .ended, kind: .finger, timestamp: 0.6, x: 200, y: 300))
        let out = runTrace(b.events)
        XCTAssertFalse(out.has(.g21, .began))
        XCTAssertTrue(out.has(.g19, .began), "it is a one-sided pinch out")
    }

    func testDrawingFingerKeepsDrawingWhenAnotherLands() {
        var b = TraceBuilder()
        b.drag(0, at: 0, from: (100, 100), to: (400, 100), duration: 0.6)
        b.tap(1, at: 0.3, x: 300, y: 500)
        let out = runTrace(b.events)
        XCTAssertTrue(out.has(.g7, .ended), "a stroke in progress is not taken over")
        XCTAssertFalse(out.has(.g16, .began))
    }

    // MARK: Three or more fingers (G22 swipe, G26 rake, G24)

    func testG26RakeThreeFingers() {
        let out = runTrace(fingers([((100, 200), (100, 600)), ((160, 200), (160, 600)), ((220, 200), (220, 600))], duration: 0.8).events)
        XCTAssertTrue(out.has(.g26, .began))
        XCTAssertTrue(out.has(.g26, .ended))
        XCTAssertEqual(out.first(.g26, .began)?.touchIDs.count, 3)
        XCTAssertFalse(out.has(.g22, .fired))
    }

    func testG22SwipeIsAQuickThreeFingerRake() {
        let out = runTrace(fingers([((100, 300), (400, 300)), ((100, 360), (400, 360)), ((100, 420), (400, 420))],
                                   stagger: 0.01, duration: 0.15).events)
        let e = out.first(.g22, .fired)
        XCTAssertNotNil(e)
        XCTAssertEqual(e!.directionX, 1, accuracy: 0.05)
        XCTAssertTrue(out.has(.g26, .cancelled), "the rake lines give way to the swipe")
    }

    func testG22NearMissFourFingerFastDragStaysRake() {
        let out = runTrace(fingers([((100, 300), (400, 300)), ((100, 340), (400, 340)), ((100, 380), (400, 380)),
                                    ((100, 420), (400, 420))], stagger: 0.01, duration: 0.15).events)
        XCTAssertFalse(out.has(.g22, .fired))
        XCTAssertTrue(out.has(.g26, .ended))
    }

    func testG24FiveFingerGather() {
        let center: (Float, Float) = (300, 400)
        let paths = (0..<5).map { k -> ((Float, Float), (Float, Float)) in
            let a = Float(k) / 5 * 2 * .pi
            return ((center.0 + 150 * cos(a), center.1 + 150 * sin(a)), (center.0 + 50 * cos(a), center.1 + 50 * sin(a)))
        }
        let out = runTrace(fingers(paths, stagger: 0.01, duration: 0.5).events)
        XCTAssertTrue(out.has(.g24, .began))
        let e = out.first(.g24, .ended)
        XCTAssertNotNil(e, "a full gather completes")
        XCTAssertGreaterThan(e!.magnitude, 0, "positive = gather")
        XCTAssertFalse(out.has(.g26, .began))
    }

    func testG24FiveFingerSpread() {
        let center: (Float, Float) = (300, 400)
        let paths = (0..<5).map { k -> ((Float, Float), (Float, Float)) in
            let a = Float(k) / 5 * 2 * .pi
            return ((center.0 + 50 * cos(a), center.1 + 50 * sin(a)), (center.0 + 150 * cos(a), center.1 + 150 * sin(a)))
        }
        let e = runTrace(fingers(paths, stagger: 0.01, duration: 0.5).events).first(.g24, .ended)
        XCTAssertNotNil(e)
        XCTAssertLessThan(e!.magnitude, 0, "negative = spread")
    }

    func testG24NearMissSmallGatherIsCancelled() {
        let center: (Float, Float) = (300, 400)
        let paths = (0..<5).map { k -> ((Float, Float), (Float, Float)) in
            let a = Float(k) / 5 * 2 * .pi
            return ((center.0 + 150 * cos(a), center.1 + 150 * sin(a)), (center.0 + 130 * cos(a), center.1 + 130 * sin(a)))
        }
        let out = runTrace(fingers(paths, stagger: 0.01, duration: 0.4).events)
        XCTAssertTrue(out.has(.g24, .began))
        XCTAssertTrue(out.has(.g24, .cancelled))
        XCTAssertFalse(out.has(.g24, .ended))
    }

    // MARK: G25 Drumming

    func testG25DrummingAlternatingFingers() {
        var b = TraceBuilder()
        for k in 0..<6 {
            b.tap(UInt16(k % 2), at: Double(k) * 0.15, x: k % 2 == 0 ? 150 : 230, y: 400, duration: 0.06)
        }
        let out = runTrace(b.events)
        XCTAssertGreaterThanOrEqual(out.count(.g25, .began), 2, "fires on the 4th tap and each one after")
        let e = out.first(.g25, .began)!
        XCTAssertNotEqual(e.originX, e.x, "linked to the previous tap point")
        XCTAssertFalse(out.has(.g4, .began), "R2: drumming beats rhythm")
    }

    func testG25NearMissSameSpot() {
        var b = TraceBuilder()
        for k in 0..<6 { b.tap(UInt16(k % 2), at: Double(k) * 0.15, x: 150, y: 400, duration: 0.06) }
        XCTAssertFalse(runTrace(b.events).has(.g25, .began))
    }

    func testG25NearMissMultiFingerTapsAreNotDrumming() {
        // A two-, three- and four-finger tap in quick succession at different spots.
        var b = TraceBuilder()
        for (n, t) in [(2, 0.0), (3, 0.3), (4, 0.6)] {
            for k in 0..<n {
                b.tap(UInt16(k), at: t + Double(k) * 0.015, x: 100 + Float(k) * 70 + Float(n) * 15, y: 300, duration: 0.08)
            }
        }
        let out = runTrace(b.events)
        XCTAssertFalse(out.has(.g25, .began))
        XCTAssertTrue(out.has(.g23, .ended))
    }

    func testG25NearMissTooSlow() {
        var b = TraceBuilder()
        for k in 0..<5 { b.tap(UInt16(k % 2), at: Double(k) * 0.45, x: k % 2 == 0 ? 150 : 230, y: 400, duration: 0.06) }
        XCTAssertFalse(runTrace(b.events).has(.g25, .began))
    }
}
