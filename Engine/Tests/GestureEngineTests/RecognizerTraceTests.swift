import XCTest
@testable import GestureEngine

/// Each gesture has at least one positive trace and one near-miss trace (spec: Testing).
final class RecognizerTraceTests: XCTestCase {

    // MARK: G1 Tap

    func testG1TapBeginsOnTouchDownAndConfirmsOnLift() {
        var b = TraceBuilder(); b.tap(at: 0, duration: 0.1, move: 3)
        let out = runTrace(b.events)
        XCTAssertEqual(out.first?.gesture, .g1, "R1: tap reacts on touch-down, before anything else")
        XCTAssertEqual(out.first?.phase, .began)
        XCTAssertEqual(out.first?.timestamp, 0)
        XCTAssertTrue(out.has(.g1, .ended))
        XCTAssertFalse(out.has(.g31, .fired), "a confirmed tap claims the lift")
    }

    func testG1NearMissMoved12ptIsNotATap() {
        var b = TraceBuilder(); b.tap(at: 0, duration: 0.1, move: 12)
        let out = runTrace(b.events)
        XCTAssertTrue(out.has(.g1, .began))
        XCTAssertTrue(out.has(.g1, .cancelled))
        XCTAssertFalse(out.has(.g1, .ended))
    }

    func testG1NearMissTooSlowIsNotATap() {
        var b = TraceBuilder(); b.tap(at: 0, duration: 0.3)
        let out = runTrace(b.events)
        XCTAssertFalse(out.has(.g1, .ended))
        XCTAssertTrue(out.has(.g1, .cancelled))
    }

    // MARK: G2 Double tap

    func testG2DoubleTapLayersOnTopOfG1() {
        var b = TraceBuilder(); b.tap(at: 0); b.tap(at: 0.25, x: 210)
        let out = runTrace(b.events)
        XCTAssertEqual(out.count(.g1, .began), 2, "R1: the second tap still shows G1")
        XCTAssertTrue(out.has(.g2, .began))
        XCTAssertTrue(out.has(.g2, .ended))
        XCTAssertEqual(out.first(.g2, .began)?.timestamp, 0.25, "G2 fires on the second touch-down")
    }

    func testG2NearMissTooFarApartInTime() {
        var b = TraceBuilder(); b.tap(at: 0); b.tap(at: 0.5)
        XCTAssertFalse(runTrace(b.events).has(.g2, .began))
    }

    func testG2NearMissTooFarApartInSpace() {
        var b = TraceBuilder(); b.tap(at: 0, x: 200); b.tap(at: 0.2, x: 240)
        XCTAssertFalse(runTrace(b.events).has(.g2, .began))
    }

    // MARK: G3 Triple tap

    func testG3TripleTap() {
        var b = TraceBuilder(); b.tap(at: 0); b.tap(at: 0.2); b.tap(at: 0.4)
        let out = runTrace(b.events)
        XCTAssertEqual(out.count(.g2, .ended), 1)
        XCTAssertEqual(out.count(.g3, .ended), 1)
    }

    func testG3NearMissThirdTapTooLate() {
        var b = TraceBuilder(); b.tap(at: 0); b.tap(at: 0.2); b.tap(at: 0.7)
        let out = runTrace(b.events)
        XCTAssertTrue(out.has(.g2, .ended))
        XCTAssertFalse(out.has(.g3, .began))
    }

    // MARK: G4 Rhythm

    func testG4RhythmAtSteadyTempo() {
        var b = TraceBuilder()
        for (k, x) in [100, 300, 150, 250].enumerated() { b.tap(at: Double(k) * 0.5, x: Float(x)) }
        let out = runTrace(b.events)
        let e = out.first(.g4, .began)
        XCTAssertNotNil(e)
        XCTAssertEqual(e?.timestamp, 1.5, "fires on the 4th tap")
        XCTAssertEqual(e?.tempo ?? 0, 2, accuracy: 0.01)
        XCTAssertEqual(e?.x, 250, "pulse sits at the last tap point")
    }

    func testG4NearMissUnevenTempo() {
        var b = TraceBuilder()
        for (k, t) in [0, 0.4, 0.9, 1.6].enumerated() { b.tap(at: t, x: Float(100 + k * 60)) }
        XCTAssertFalse(runTrace(b.events).has(.g4, .began))
    }

    func testG4NearMissOnlyThreeTaps() {
        var b = TraceBuilder()
        for k in 0..<3 { b.tap(at: Double(k) * 0.5, x: Float(100 + k * 60)) }
        XCTAssertFalse(runTrace(b.events).has(.g4, .began))
    }

    // MARK: G5 Long press and G6 Hold and release

    func testG5LongPressBeginsAfter400msAndGrows() {
        var b = TraceBuilder(); b.hold(at: 0, duration: 0.8)
        let out = runTrace(b.events)
        let began = out.first(.g5, .began)
        XCTAssertNotNil(began)
        XCTAssertEqual(began!.timestamp, 0.4, accuracy: 1.0 / 120 + 1e-9)
        XCTAssertTrue(out.has(.g1, .cancelled), "the provisional tap yields to the hold")
        let changes = out.filter { $0.gesture == .g5 && $0.phase == .changed }.map(\.magnitude)
        XCTAssertGreaterThan(changes.count, 10)
        XCTAssertEqual(changes, changes.sorted(), "hold time only grows")
        XCTAssertTrue(out.has(.g5, .ended))
    }

    func testG5NearMissReleasedAt350ms() {
        var b = TraceBuilder(); b.hold(at: 0, duration: 0.35)
        XCTAssertFalse(runTrace(b.events).has(.g5, .began))
    }

    func testG5NearMissFingerWanders() {
        var b = TraceBuilder(); b.drag(at: 0, from: (200, 300), to: (225, 300), duration: 0.6)
        XCTAssertFalse(runTrace(b.events).has(.g5, .began))
    }

    func testG6ReleaseAfterHoldCarriesHoldTime() {
        var b = TraceBuilder(); b.hold(at: 0, duration: 0.6)
        let out = runTrace(b.events)
        let e = out.first(.g6, .fired)
        XCTAssertNotNil(e)
        XCTAssertEqual(e!.magnitude, 0.6, accuracy: 0.01)
        XCTAssertFalse(out.has(.g31, .fired), "the release claims the lift")
    }

    func testG6StrengthIsCapped() {
        var b = TraceBuilder(); b.hold(at: 0, duration: 3.0)
        XCTAssertEqual(runTrace(b.events).first(.g6, .fired)!.magnitude, 2.0, accuracy: 1e-6)
    }

    func testG6NearMissLiftBeforeHold() {
        var b = TraceBuilder(); b.hold(at: 0, duration: 0.3)
        XCTAssertFalse(runTrace(b.events).has(.g6, .fired))
    }

    // MARK: G7 Draw

    func testG7DrawBeginsAt10pt() {
        var b = TraceBuilder(); b.drag(at: 0, from: (100, 100), to: (160, 100), duration: 0.3)
        let out = runTrace(b.events)
        XCTAssertTrue(out.has(.g7, .began))
        XCTAssertTrue(out.has(.g7, .changed))
        XCTAssertTrue(out.has(.g7, .ended))
        XCTAssertGreaterThanOrEqual(out.first(.g7, .began)!.x, 110)
    }

    func testG7NearMissMoves8pt() {
        var b = TraceBuilder(); b.drag(at: 0, from: (100, 100), to: (108, 100), duration: 0.3)
        XCTAssertFalse(runTrace(b.events).has(.g7, .began))
    }

    func testPencilIsDrawOnly() {
        var b = TraceBuilder(); b.tap(at: 0, kind: .pencil)
        let out = runTrace(b.events)
        XCTAssertTrue(out.has(.g7, .began), "R6: Pencil draws from touch-down")
        XCTAssertFalse(out.has(.g1, .began))
        XCTAssertFalse(out.has(.g31, .fired))
    }

    // MARK: G31 Lift-off

    func testG31FiresForUnclaimedLift() {
        var b = TraceBuilder(); b.tap(at: 0, duration: 0.3, move: 5)
        XCTAssertTrue(runTrace(b.events).has(.g31, .fired))
    }

    func testG31CarriesSpeedAtLiftAfterStroke() {
        // Long enough not to be a flick (G8), still moving fast at the lift.
        var b = TraceBuilder(); b.drag(at: 0, from: (100, 100), to: (700, 100), duration: 0.5)
        let e = runTrace(b.events).first(.g31, .fired)
        XCTAssertNotNil(e)
        XCTAssertGreaterThan(e!.speed, 1000)
    }

    func testG31NearMissConfirmedTapDoesNotFire() {
        var b = TraceBuilder(); b.tap(at: 0)
        XCTAssertFalse(runTrace(b.events).has(.g31, .fired))
    }

    // MARK: Priority (R2)

    func testSecondFingerCancelsProvisionalTap() {
        var b = TraceBuilder()
        b.add(TouchEvent(touchID: 0, phase: .began, kind: .finger, timestamp: 0, x: 100, y: 100))
        b.add(TouchEvent(touchID: 1, phase: .began, kind: .finger, timestamp: 0.03, x: 200, y: 100))
        b.add(TouchEvent(touchID: 0, phase: .ended, kind: .finger, timestamp: 0.1, x: 100, y: 100))
        b.add(TouchEvent(touchID: 1, phase: .ended, kind: .finger, timestamp: 0.1, x: 200, y: 100))
        let out = runTrace(b.events)
        XCTAssertEqual(out.count(.g1, .began), 1, "the second finger does not start a single-finger tap")
        XCTAssertTrue(out.has(.g1, .cancelled))
        XCTAssertFalse(out.has(.g1, .ended))
    }

    func testSecondFingerCancelsHold() {
        var b = TraceBuilder()
        b.add(TouchEvent(touchID: 0, phase: .began, kind: .finger, timestamp: 0, x: 100, y: 100))
        b.add(TouchEvent(touchID: 1, phase: .began, kind: .finger, timestamp: 0.6, x: 200, y: 100))
        b.add(TouchEvent(touchID: 0, phase: .ended, kind: .finger, timestamp: 0.8, x: 100, y: 100))
        b.add(TouchEvent(touchID: 1, phase: .ended, kind: .finger, timestamp: 0.8, x: 200, y: 100))
        let out = runTrace(b.events)
        XCTAssertTrue(out.has(.g5, .began))
        XCTAssertTrue(out.has(.g5, .cancelled))
        XCTAssertFalse(out.has(.g6, .fired))
    }

    func testPredictedSamplesNeverClassify() {
        var b = TraceBuilder()
        b.add(TouchEvent(touchID: 0, phase: .began, kind: .finger, timestamp: 0, x: 100, y: 100))
        b.add(TouchEvent(touchID: 0, phase: .moved, kind: .finger, timestamp: 0.02, x: 150, y: 100, isPredicted: true))
        b.add(TouchEvent(touchID: 0, phase: .ended, kind: .finger, timestamp: 0.08, x: 100, y: 100))
        let out = runTrace(b.events)
        XCTAssertFalse(out.has(.g7, .began))
        XCTAssertTrue(out.has(.g1, .ended))
    }
}
