/// One small recognizer per gesture. Each reads the shared touch tracks and its own
/// state, and emits GestureEvents. No UIKit.
class Recognizer {
    let id: GestureID
    var category: GestureCategory { id.category }

    init(_ id: GestureID) { self.id = id }

    func began(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {}
    func moved(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {}
    func ended(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {}
    func cancelled(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {}
    /// A second finger landed: single-finger gestures on touch `i` must yield (R2).
    func yieldToMultiFinger(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {}
    func tick(_ s: EngineState, _ emit: (GestureEvent) -> Void) {}
}

// MARK: - Taps (progressive reveal, R1)

/// Base for gestures that begin on touch-down and are confirmed when the touch lifts
/// as a valid tap. They begin immediately (R1) and are cancelled the moment the touch
/// stops qualifying: it moves, is held too long, or another finger lands.
class ProvisionalTapRecognizer: Recognizer {
    private var live = [Bool](repeating: false, count: 64)

    /// Whether this gesture begins on this touch-down, with its magnitude and tempo.
    func shouldBegin(_ i: Int, _ s: EngineState) -> (Bool, Float, Float) { (false, 0, 0) }

    override func began(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        let tr = s.tracks[i]
        guard tr.kind == .finger, !tr.multiFinger else { return }
        let (go, magnitude, tempo) = shouldBegin(i, s)
        guard go else { return }
        live[i] = true
        emit(s.event(id, .began, i, magnitude: magnitude, tempo: tempo))
    }

    override func moved(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        if live[i] && s.tracks[i].maxDisplacement >= s.config.tapMaxMovement { cancel(i, s, emit) }
    }

    override func tick(_ s: EngineState, _ emit: (GestureEvent) -> Void) {
        for i in 0..<live.count where live[i] && s.now - s.tracks[i].startT > s.config.tapMaxDuration {
            cancel(i, s, emit, at: s.now)
        }
    }

    override func ended(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        guard live[i] else { return }
        live[i] = false
        if s.isValidTap(i) {
            s.tracks[i].liftClaimed = true
            emit(s.event(id, .ended, i))
        } else {
            emit(s.event(id, .cancelled, i))
        }
    }

    override func cancelled(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) { cancel(i, s, emit) }
    override func yieldToMultiFinger(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) { cancel(i, s, emit) }

    private func cancel(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void, at t: Double? = nil) {
        guard live[i] else { return }
        live[i] = false
        emit(s.event(id, .cancelled, i, at: t))
    }
}

/// G1 Tap. Begins on every finger touch-down; confirmed on a quick, still lift.
final class TapRecognizer: ProvisionalTapRecognizer {
    init() { super.init(.g1) }
    override func shouldBegin(_ i: Int, _ s: EngineState) -> (Bool, Float, Float) {
        (true, s.tracks[i].majorRadius, 0)   // contact size sets ring size
    }
}

/// G2 Double tap: the second touch-down of a quick run of taps.
final class DoubleTapRecognizer: ProvisionalTapRecognizer {
    init() { super.init(.g2) }
    override func shouldBegin(_ i: Int, _ s: EngineState) -> (Bool, Float, Float) {
        (s.tracks[i].tapSequenceIndex == 2, 0, 0)
    }
}

/// G3 Triple tap: the third touch-down of a quick run of taps.
final class TripleTapRecognizer: ProvisionalTapRecognizer {
    init() { super.init(.g3) }
    override func shouldBegin(_ i: Int, _ s: EngineState) -> (Bool, Float, Float) {
        (s.tracks[i].tapSequenceIndex == 3, 0, 0)
    }
}

/// G4 Rhythm taps: this touch-down plus the previous taps make 4 or more taps whose
/// intervals are all within 20% of their mean. Fires on every qualifying tap so the
/// pulse follows the latest tap point and tempo.
final class RhythmRecognizer: ProvisionalTapRecognizer {
    init() { super.init(.g4) }
    override func shouldBegin(_ i: Int, _ s: EngineState) -> (Bool, Float, Float) {
        let need = s.config.rhythmMinTaps
        let previous = s.recentTapDownTimes(need - 1)
        guard need >= 2, previous.count == need - 1, let first = previous.first else { return (false, 0, 0) }
        let now = s.tracks[i].startT
        let mean = (now - first.downT) / Double(need - 1)
        guard mean > 0, mean <= s.config.rhythmMaxInterval else { return (false, 0, 0) }
        let tol = Double(s.config.rhythmTempoTolerance) * mean
        var prevT = first.downT
        for tap in previous.dropFirst() {
            if abs(tap.downT - prevT - mean) > tol { return (false, 0, 0) }
            prevT = tap.downT
        }
        if abs(now - prevT - mean) > tol { return (false, 0, 0) }
        return (true, Float(need), Float(1 / mean))
    }
}

// MARK: - Holds

/// G5 Long press: a finger held still past 400 ms. Continuous: `changed` every tick
/// carries the hold time as magnitude.
final class LongPressRecognizer: Recognizer {
    init() { super.init(.g5) }

    override func tick(_ s: EngineState, _ emit: (GestureEvent) -> Void) {
        for i in 0..<s.tracks.count where s.tracks[i].active { update(i, s, emit) }
    }

    private func update(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        let tr = s.tracks[i]
        guard tr.kind == .finger, !tr.multiFinger, !tr.drawing, !tr.holdBroken else { return }
        let held = s.now - tr.startT
        if tr.holding {
            emit(s.event(id, .changed, i, at: s.now, magnitude: Float(held)))
        } else if held >= s.config.longPressMinDuration && tr.maxDisplacement < s.config.longPressMaxMovement {
            s.tracks[i].holding = true
            emit(s.event(id, .began, i, at: s.now, magnitude: Float(held)))
        }
    }

    override func moved(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        // Moving after the hold breaks it. M3 turns this into G14 (hold-drag).
        if s.tracks[i].holding && s.tracks[i].maxDisplacement >= s.config.longPressMaxMovement {
            s.tracks[i].holding = false
            s.tracks[i].holdBroken = true
            emit(s.event(id, .cancelled, i))
        }
    }

    override func ended(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        // Catch a hold that crossed the threshold since the last tick.
        if !s.tracks[i].holding {
            s.now = max(s.now, s.tracks[i].t)
            update(i, s, emit)
        }
        if s.tracks[i].holding {
            emit(s.event(id, .ended, i, magnitude: Float(s.tracks[i].duration)))
        }
    }

    override func cancelled(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) { yield(i, s, emit) }
    override func yieldToMultiFinger(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) { yield(i, s, emit) }

    private func yield(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        guard s.tracks[i].holding else { return }
        s.tracks[i].holding = false
        s.tracks[i].holdBroken = true
        emit(s.event(id, .cancelled, i))
    }
}

/// G6 Hold and release: lifting after a G5 hold. Magnitude is the hold time,
/// capped at `holdReleaseStrengthCap`.
final class HoldReleaseRecognizer: Recognizer {
    init() { super.init(.g6) }
    override func ended(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        guard s.tracks[i].holding else { return }
        s.tracks[i].liftClaimed = true
        let held = min(s.tracks[i].duration, s.config.holdReleaseStrengthCap)
        emit(s.event(id, .fired, i, magnitude: Float(held)))
    }
}

// MARK: - Draw

/// G7 Draw: a finger that moves 10 pt or more, or any Pencil touch (R6: Pencil is draw-only).
final class DrawRecognizer: Recognizer {
    init() { super.init(.g7) }

    override func began(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        guard s.tracks[i].kind == .pencil else { return }
        s.tracks[i].drawing = true
        emit(s.event(id, .began, i))
    }

    override func moved(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        let tr = s.tracks[i]
        if tr.drawing {
            emit(s.event(id, .changed, i))
        } else if tr.kind == .finger, !tr.holding, !tr.holdBroken,
                  tr.maxDisplacement >= s.config.drawMinMovement {
            s.tracks[i].drawing = true
            emit(s.event(id, .began, i))
        }
    }

    override func ended(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        if s.tracks[i].drawing { emit(s.event(id, .ended, i, speed: s.speedAtLift(i))) }
    }

    override func cancelled(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        if s.tracks[i].drawing { emit(s.event(id, .cancelled, i)) }
    }
}

// MARK: - Lift-off

/// G31 Lift-off: any finger lift that no one-shot gesture claimed (a confirmed tap or
/// a hold release). Runs last. Strokes are not a claim, so a stroke's end blooms too
/// (an assumption, see STATUS.md).
final class LiftOffRecognizer: Recognizer {
    init() { super.init(.g31) }
    override func ended(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        let tr = s.tracks[i]
        guard tr.kind == .finger, !tr.liftClaimed else { return }
        emit(s.event(id, .fired, i, speed: s.speedAtLift(i)))
    }
}
