import Foundation

/// M5: contextual gestures (G27 to G30) and idle (G32). Contextual gestures depend on
/// the ink already on the canvas or on the canvas edges; they beat single-finger
/// gestures (R2), so a touch-down they claim does not also start the tap family.

// MARK: - G27 Touch a stroke

/// A tap on existing ink. Begins on touch-down (R1) when the finger lands on a stroke;
/// confirmed on a quick, still lift, cancelled otherwise (the touch may go on to draw).
final class TouchStrokeRecognizer: Recognizer {
    private var live = [Bool](repeating: false, count: 64)
    private var hits = [StrokeHit?](repeating: nil, count: 64)

    init() { super.init(.g27) }

    override func began(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        live[i] = false
        let tr = s.tracks[i]
        guard tr.kind == .finger, !tr.inSession,
              let hit = s.ink?.hitStroke(x: tr.x, y: tr.y, radius: s.config.strokeHitRadius) else { return }
        live[i] = true
        hits[i] = hit
        s.tracks[i].contextual = true
        emit(event(.began, i, s, hit))
    }

    override func moved(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        if live[i] && s.tracks[i].maxDisplacement >= s.config.tapMaxMovement { cancel(i, s, emit) }
    }

    override func tick(_ s: EngineState, _ emit: (GestureEvent) -> Void) {
        for i in 0..<live.count where live[i] && s.now - s.tracks[i].startT > s.config.tapMaxDuration {
            cancel(i, s, emit)
        }
    }

    override func ended(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        guard live[i], let hit = hits[i] else { return }
        live[i] = false
        if s.isValidTap(i) {
            s.tracks[i].liftClaimed = true
            emit(event(.ended, i, s, hit))
        } else {
            emit(event(.cancelled, i, s, hit))
        }
    }

    override func cancelled(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) { cancel(i, s, emit) }
    override func yieldToMultiFinger(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) { cancel(i, s, emit) }

    private func cancel(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        guard live[i], let hit = hits[i] else { return }
        live[i] = false
        emit(event(.cancelled, i, s, hit))
    }

    /// Point on the stroke; magnitude is the stroke's length, size the distance along it.
    private func event(_ phase: GesturePhase, _ i: Int, _ s: EngineState, _ hit: StrokeHit) -> GestureEvent {
        s.event(id, phase, i, magnitude: hit.length, x: hit.x, y: hit.y, size: hit.along, targetID: hit.strokeID)
    }
}

// MARK: - G28 Cross a stroke

/// A stroke being drawn crosses existing ink. Fires once per crossing, at the crossing
/// point, carrying the older stroke's direction as the origin vector.
final class CrossStrokeRecognizer: Recognizer {
    private var lastX = [Float](repeating: 0, count: 64)
    private var lastY = [Float](repeating: 0, count: 64)
    private var sinceCrossing = [Float](repeating: .greatestFiniteMagnitude, count: 64)
    private var lastStroke = [UInt32](repeating: 0, count: 64)

    init() { super.init(.g28) }

    override func began(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        lastX[i] = s.tracks[i].x; lastY[i] = s.tracks[i].y
        sinceCrossing[i] = .greatestFiniteMagnitude
        lastStroke[i] = 0
    }

    override func moved(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        let tr = s.tracks[i]
        let x0 = lastX[i], y0 = lastY[i]
        lastX[i] = tr.x; lastY[i] = tr.y
        sinceCrossing[i] += hypot(tr.x - x0, tr.y - y0)
        // Pencil stays draw-only (R6). Ignore the first stretch so starting on a stroke
        // (a G27 touch that turns into a drag) is not a crossing.
        guard tr.drawing, tr.kind == .finger, tr.maxDisplacement >= s.config.drawMinMovement,
              let c = s.ink?.crossing(x0: x0, y0: y0, x1: tr.x, y1: tr.y) else { return }
        guard c.strokeID != lastStroke[i] || sinceCrossing[i] >= s.config.crossingSpacing else { return }
        lastStroke[i] = c.strokeID
        sinceCrossing[i] = 0
        emit(s.event(id, .fired, i, x: c.x, y: c.y, originX: c.dirX, originY: c.dirY, targetID: c.strokeID))
    }
}

// MARK: - G29 Close a shape

/// A stroke that ends on its own start without being circle-like. Classified at lift
/// (R3), before zigzag and flick, after circle and spiral have had their say. The
/// event sits at the closing point; the origin is the shape's centroid, size the
/// square root of its area.
final class CloseShapeRecognizer: StrokeShapeRecognizer {
    init() { super.init(.g29) }
    override func classify(_ i: Int, _ s: EngineState, _ sh: ShapeInfo) -> GestureEvent? {
        let c = s.config
        guard sh.count >= 10, sh.length >= c.closeShapeMinLength,
              sh.closeGap <= max(c.closeShapeMaxGap, sh.length * 0.05),
              sh.area >= c.closeShapeMinArea,
              !sh.isCircle(c), sh.spiralDirection(c) == 0 else { return nil }
        let speed = sh.duration > 0 ? sh.length / Float(sh.duration) : 0
        return s.event(id, .fired, i, magnitude: sh.area, speed: speed,
                       size: sh.area.squareRoot(), originX: sh.cx, originY: sh.cy)
    }

    // G29 is listed with the contextual gestures but is classified with the shapes,
    // so it keeps the shapes' order instead of jumping ahead of G10 and G11.
    override var category: GestureCategory { .singleFinger }
}

// MARK: - G30 Edge touch

/// A touch that begins within `edgeZone` of a screen edge. Fires on touch-down with
/// the inward direction; does not stop the touch from drawing afterwards.
final class EdgeRecognizer: Recognizer {
    init() { super.init(.g30) }

    override func began(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        let tr = s.tracks[i]
        let w = s.canvasWidth, h = s.canvasHeight
        guard tr.kind == .finger, !tr.inSession, w > 0, h > 0 else { return }
        let distances: [(Float, Float, Float)] = [(tr.x, 1, 0), (w - tr.x, -1, 0), (tr.y, 0, 1), (h - tr.y, 0, -1)]
        guard let nearest = distances.min(by: { $0.0 < $1.0 }), nearest.0 <= s.config.edgeZone else { return }
        s.tracks[i].contextual = true
        s.tracks[i].liftClaimed = true   // one reaction per edge touch, no lift-off bloom
        // Magnitude: position along the edge, 0...1.
        let along = nearest.1 != 0 ? tr.y / h : tr.x / w
        emit(s.event(id, .fired, i, magnitude: along, dirX: nearest.1, dirY: nearest.2))
    }
}

// MARK: - G32 Idle

/// No touch for `idleDelay` seconds. Begins from the tick, reports the idle time
/// about twice a second, and ends the moment any touch lands.
final class IdleRecognizer: Recognizer {
    private var idle = false
    private var since: Double = 0
    private var lastReport: Double = 0

    init() { super.init(.g32) }

    // Runs first so the idle state ends before anything reacts to the touch.
    override var category: GestureCategory { .multiFinger }

    override func began(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        guard idle else { return }
        idle = false
        emit(event(.ended, s, i: i))
    }

    override func tick(_ s: EngineState, _ emit: (GestureEvent) -> Void) {
        guard s.lastActivity >= 0 else { return }
        let quiet = s.now - s.lastActivity
        if !idle {
            guard quiet >= s.config.idleDelay else { return }
            idle = true
            since = s.lastActivity
            lastReport = s.now
            emit(event(.began, s, i: 0))
        } else if s.now - lastReport >= 0.5 {
            lastReport = s.now
            emit(event(.changed, s, i: 0))
        }
    }

    /// At the last touch location; magnitude is seconds of quiet.
    private func event(_ phase: GesturePhase, _ s: EngineState, i: Int) -> GestureEvent {
        var e = GestureEvent(gesture: id, phase: phase, timestamp: s.now, x: s.lastTouchX, y: s.lastTouchY,
                             fingerCount: 0, magnitude: Float(s.now - since), touchID: UInt16(i))
        e.speed = 0
        return e
    }
}
