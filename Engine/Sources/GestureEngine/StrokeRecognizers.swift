/// M3: single-finger depth (G8 to G15).
///
/// Mid-stroke upgrades (R1): G9 scribble and G15 dwell begin while the finger is
/// still down. After-the-fact shapes (R3): G10 circle, G11 spiral, G12 zigzag and
/// G8 flick are classified from the path at lift. The first one that matches claims
/// the lift, in that order.

// MARK: - G9 Scribble

/// 3 or more direction reversals within about 1 s over a small area. Claims the
/// stroke: G7 is cancelled and the scribble erases ink instead of drawing.
final class ScribbleRecognizer: Recognizer {
    private static let ring = 8
    private var anchorX = [Float](repeating: 0, count: 64)
    private var anchorY = [Float](repeating: 0, count: 64)
    private var dirX = [Float](repeating: 0, count: 64)
    private var dirY = [Float](repeating: 0, count: 64)
    private var reversals = [Double](repeating: -1e9, count: 64 * ScribbleRecognizer.ring)
    private var next = [Int](repeating: 0, count: 64)

    init() { super.init(.g9) }

    override func began(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        anchorX[i] = s.tracks[i].x; anchorY[i] = s.tracks[i].y
        dirX[i] = 0; dirY[i] = 0
        for k in 0..<Self.ring { reversals[i * Self.ring + k] = -1e9 }
    }

    override func moved(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        let tr = s.tracks[i]
        guard tr.kind == .finger, !tr.holding, !tr.holdBroken, !tr.slingshot else { return }
        if tr.scribbling {
            emit(s.event(id, .changed, i, size: windowExtent(i, s)))
            return
        }
        let dx = tr.x - anchorX[i], dy = tr.y - anchorY[i]
        let d = (dx * dx + dy * dy).squareRoot()
        if d >= s.config.scribbleSegment {
            let nx = dx / d, ny = dy / d
            if (dirX[i] != 0 || dirY[i] != 0) && nx * dirX[i] + ny * dirY[i] < s.config.scribbleReversalDot {
                reversals[i * Self.ring + next[i]] = tr.t
                next[i] = (next[i] + 1) % Self.ring
            }
            dirX[i] = nx; dirY[i] = ny
            anchorX[i] = tr.x; anchorY[i] = tr.y
        }
        guard tr.drawing else { return }
        var recent = 0
        for k in 0..<Self.ring where tr.t - reversals[i * Self.ring + k] <= s.config.scribbleWindow { recent += 1 }
        guard recent >= s.config.scribbleMinReversals else { return }
        let extent = windowExtent(i, s)
        guard extent <= s.config.scribbleMaxExtent else { return }
        s.tracks[i].scribbling = true
        s.tracks[i].strokeClaimed = true
        emit(s.event(id, .began, i, size: extent))
    }

    override func ended(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        guard s.tracks[i].scribbling else { return }
        s.tracks[i].liftClaimed = true
        emit(s.event(id, .ended, i))
    }

    override func cancelled(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        if s.tracks[i].scribbling { emit(s.event(id, .cancelled, i)) }
    }

    /// Bounding-box size of the path over the last scribble window.
    private func windowExtent(_ i: Int, _ s: EngineState) -> Float {
        let path = s.paths[i]
        guard let last = path.last else { return 0 }
        var minX = last.x, maxX = last.x, minY = last.y, maxY = last.y
        var k = path.count - 1
        while k >= 0 && last.t - path[k].t <= s.config.scribbleWindow {
            minX = min(minX, path[k].x); maxX = max(maxX, path[k].x)
            minY = min(minY, path[k].y); maxY = max(maxY, path[k].y)
            k -= 1
        }
        return max(maxX - minX, maxY - minY)
    }
}

// MARK: - G13 Slingshot

/// Tap, then touch down again quickly near it and drag. The first tap is the anchor.
final class SlingshotRecognizer: Recognizer {
    private var candidate = [Bool](repeating: false, count: 64)
    private var anchorX = [Float](repeating: 0, count: 64)
    private var anchorY = [Float](repeating: 0, count: 64)

    init() { super.init(.g13) }

    override func began(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        let tr = s.tracks[i]
        candidate[i] = false
        guard tr.kind == .finger, !tr.multiFinger, tr.tapSequenceIndex == 2, let tap = s.lastTap else { return }
        candidate[i] = true
        anchorX[i] = tap.x; anchorY[i] = tap.y
    }

    override func moved(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        let tr = s.tracks[i]
        if tr.slingshot {
            emit(s.event(id, .changed, i, magnitude: stretch(i, tr), originX: anchorX[i], originY: anchorY[i]))
        } else if candidate[i] && !tr.multiFinger && tr.maxDisplacement >= s.config.tapMaxMovement {
            candidate[i] = false
            s.tracks[i].slingshot = true
            s.tracks[i].strokeClaimed = true
            emit(s.event(id, .began, i, magnitude: stretch(i, tr), originX: anchorX[i], originY: anchorY[i]))
        }
    }

    override func ended(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        candidate[i] = false
        let tr = s.tracks[i]
        guard tr.slingshot else { return }
        s.tracks[i].liftClaimed = true
        emit(s.event(id, .ended, i, magnitude: stretch(i, tr), originX: anchorX[i], originY: anchorY[i]))
    }

    override func cancelled(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) { yield(i, s, emit) }
    override func yieldToMultiFinger(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) { yield(i, s, emit) }

    private func yield(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        candidate[i] = false
        guard s.tracks[i].slingshot else { return }
        s.tracks[i].slingshot = false
        emit(s.event(id, .cancelled, i, originX: anchorX[i], originY: anchorY[i]))
    }

    private func stretch(_ i: Int, _ tr: TouchTrack) -> Float {
        let dx = tr.x - anchorX[i], dy = tr.y - anchorY[i]
        return (dx * dx + dy * dy).squareRoot()
    }
}

// MARK: - G14 Hold-drag

/// A G5 hold that starts moving. The long-press recognizer hands over by setting
/// `holdDragging`; this one runs the drag until lift.
final class HoldDragRecognizer: Recognizer {
    private var live = [Bool](repeating: false, count: 64)

    init() { super.init(.g14) }

    override func began(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) { live[i] = false }

    override func moved(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        guard s.tracks[i].holdDragging else { return }
        if live[i] {
            emit(s.event(id, .changed, i))
        } else {
            live[i] = true
            emit(s.event(id, .began, i))
        }
    }

    override func ended(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        guard live[i] else { return }
        live[i] = false
        s.tracks[i].liftClaimed = true
        emit(s.event(id, .ended, i))
    }

    override func cancelled(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) { yield(i, s, emit) }
    override func yieldToMultiFinger(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) { yield(i, s, emit) }

    private func yield(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        guard live[i] else { return }
        live[i] = false
        s.tracks[i].holdDragging = false
        emit(s.event(id, .cancelled, i))
    }
}

// MARK: - G15 Dwell

/// Pause over 300 ms mid-stroke without lifting. Continuous: `changed` carries the
/// dwell time; `ended` when the finger moves on or lifts.
final class DwellRecognizer: Recognizer {
    private var anchorX = [Float](repeating: 0, count: 64)
    private var anchorY = [Float](repeating: 0, count: 64)
    private var anchorT = [Double](repeating: 0, count: 64)
    private var dwelling = [Bool](repeating: false, count: 64)

    init() { super.init(.g15) }

    override func began(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        dwelling[i] = false
        reanchor(i, s)
    }

    override func moved(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        let tr = s.tracks[i]
        let dx = tr.x - anchorX[i], dy = tr.y - anchorY[i]
        guard (dx * dx + dy * dy).squareRoot() > s.config.dwellRadius else { return }
        if dwelling[i] {
            dwelling[i] = false
            emit(s.event(id, .ended, i, magnitude: Float(tr.t - anchorT[i]), x: anchorX[i], y: anchorY[i]))
        }
        reanchor(i, s)
    }

    override func tick(_ s: EngineState, _ emit: (GestureEvent) -> Void) {
        for i in 0..<s.tracks.count where s.tracks[i].active {
            let tr = s.tracks[i]
            guard tr.drawing, tr.kind == .finger, !tr.strokeClaimed else { continue }
            let held = s.now - anchorT[i]
            if dwelling[i] {
                emit(s.event(id, .changed, i, at: s.now, magnitude: Float(held), x: anchorX[i], y: anchorY[i]))
            } else if held >= s.config.dwellMinDuration {
                dwelling[i] = true
                emit(s.event(id, .began, i, at: s.now, magnitude: Float(held), x: anchorX[i], y: anchorY[i]))
            }
        }
    }

    override func ended(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) { finish(i, s, emit, .ended) }
    override func cancelled(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) { finish(i, s, emit, .cancelled) }

    private func finish(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void, _ phase: GesturePhase) {
        guard dwelling[i] else { return }
        dwelling[i] = false
        emit(s.event(id, phase, i, magnitude: Float(s.tracks[i].t - anchorT[i]), x: anchorX[i], y: anchorY[i]))
    }

    private func reanchor(_ i: Int, _ s: EngineState) {
        anchorX[i] = s.tracks[i].x; anchorY[i] = s.tracks[i].y; anchorT[i] = s.tracks[i].t
    }
}

// MARK: - After-the-fact shapes (R3)

/// Base for shapes classified at lift. Runs only for finger strokes that G7 drew and
/// that no earlier shape claimed.
class StrokeShapeRecognizer: Recognizer {
    override func ended(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        let tr = s.tracks[i]
        guard tr.drawing, tr.kind == .finger, !tr.liftClaimed, !tr.strokeClaimed else { return }
        if let e = classify(i, s, s.shape(i)) {
            s.tracks[i].liftClaimed = true
            emit(e)
        }
    }

    func classify(_ i: Int, _ s: EngineState, _ shape: ShapeInfo) -> GestureEvent? { nil }
}

/// G10 Circle: the stroke closes into a near-circular loop. Event is at the center;
/// size is the radius.
final class CircleRecognizer: StrokeShapeRecognizer {
    init() { super.init(.g10) }
    override func classify(_ i: Int, _ s: EngineState, _ sh: ShapeInfo) -> GestureEvent? {
        guard sh.isCircle(s.config) else { return nil }
        return s.event(id, .fired, i, magnitude: sh.sweep > 0 ? 1 : -1, x: sh.cx, y: sh.cy, size: sh.meanRadius)
    }
}

/// G11 Spiral: 1.5 or more turns with the radius shrinking (inward) or growing
/// (outward). Magnitude is the number of turns, positive inward, negative outward.
final class SpiralRecognizer: StrokeShapeRecognizer {
    init() { super.init(.g11) }
    override func classify(_ i: Int, _ s: EngineState, _ sh: ShapeInfo) -> GestureEvent? {
        let dir = sh.spiralDirection(s.config)
        guard dir != 0 else { return nil }
        return s.event(id, .fired, i, magnitude: dir * sh.turns, x: sh.cx, y: sh.cy,
                       size: max(sh.startRadius, sh.endRadius))
    }
}

/// G12 Zigzag: 3 or more sharp direction changes in one stroke.
final class ZigzagRecognizer: StrokeShapeRecognizer {
    init() { super.init(.g12) }
    override func classify(_ i: Int, _ s: EngineState, _ sh: ShapeInfo) -> GestureEvent? {
        guard sh.isZigzag(s.config) else { return nil }
        let speed = sh.duration > 0 ? sh.length / Float(sh.duration) : 0
        return s.event(id, .fired, i, magnitude: Float(sh.sharpTurns), speed: speed,
                       x: sh.cx, y: sh.cy, size: sh.extent)
    }
}

/// G8 Flick: a short, fast stroke that lifts while still moving.
final class FlickRecognizer: StrokeShapeRecognizer {
    init() { super.init(.g8) }
    override func classify(_ i: Int, _ s: EngineState, _ sh: ShapeInfo) -> GestureEvent? {
        let speed = s.speedAtLift(i)
        guard speed >= s.config.flickMinSpeed, sh.duration <= s.config.flickMaxDuration,
              sh.length >= s.config.flickMinLength else { return nil }
        return s.event(id, .fired, i, speed: speed, size: sh.length)
    }
}
