import Foundation

/// M4: multi-finger gestures (G16 to G24, G26). Highest priority (R2).
///
/// Fingers that land together, or join fingers that are resting or holding (not
/// drawing), form a **session** of up to five fingers. Session fingers never draw
/// single-finger ink.
///
/// - Taps react on touch-down (R1): two fingers begin G16, a third upgrades it to
///   G22, a fourth to G23. The tap is confirmed when every finger lifts within 250 ms
///   without moving.
/// - Once any finger moves `multiFingerLockDistance`, the session locks into one
///   continuous gesture by what dominates:
///   - two fingers: translation (G17 drag), distance (G18/G19 pinch), rotation (G20),
///     or one finger still while the other circles it (G21 orbit)
///   - three or four fingers: translation (G26 rake; a quick three-finger rake that
///     lifts fast is G22 swipe)
///   - five fingers: spread change (G24 gather/spread), else G26 rake
///
/// One recognizer handles the shared session and emits for each gesture, because
/// every one of them depends on the same membership and lock (a deviation from
/// "one recognizer per gesture", noted in STATUS.md).
final class MultiFingerRecognizer: Recognizer {
    enum Kind { case pending, drag, pinchIn, pinchOut, rotate, orbit, rake, gather, spread, none }

    private var active = false
    private var members: [Int] = []
    private var lifted: [Bool] = []
    private var baseX: [Float] = [], baseY: [Float] = []
    private var kind: Kind = .pending
    private var startT: Double = 0
    private var tapID: GestureID? = nil
    private var tapValid = true
    private var anyLifted = false

    // Continuous-gesture state.
    private var baseD: Float = 0, baseAngle: Float = 0, baseSpread: Float = 0
    private var lastAngle: Float = 0, rotation: Float = 0
    private var lastD: Float = 0, lastT: Double = 0, dSpeed: Float = 0, angularSpeed: Float = 0
    private var lastCX: Float = 0, lastCY: Float = 0, cvx: Float = 0, cvy: Float = 0
    private var orbitStill = 0, orbitLastAngle: Float = 0, orbitSweep: Float = 0
    private var lockT: Double = 0

    init() {
        super.init(.g16)
        members.reserveCapacity(5); lifted.reserveCapacity(5)
        baseX.reserveCapacity(5); baseY.reserveCapacity(5)
    }

    // MARK: Membership

    override func began(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        let tr = s.tracks[i]
        guard tr.kind == .finger else { return }
        if !active {
            var others: [Int] = []
            for j in 0..<s.tracks.count where j != i && s.tracks[j].active && s.tracks[j].kind == .finger
                && !s.tracks[j].drawing && !s.tracks[j].inSession {
                others.append(j)
            }
            guard !others.isEmpty else { return }
            active = true
            kind = .pending
            tapValid = true
            anyLifted = false
            members.removeAll(); lifted.removeAll()
            startT = others.map { s.tracks[$0].startT }.min() ?? tr.startT
            for j in others.prefix(4) { join(j, s) }
            // Fingers resting since well before this one can't make a tap.
            if tr.startT - startT > s.config.multiFingerTapMaxDuration { tapValid = false }
        } else if kind != .pending || members.count >= 5 {
            return
        }
        join(i, s)
        rebase(s)
        updateTap(s, emit)
    }

    private func join(_ j: Int, _ s: EngineState) {
        members.append(j); lifted.append(false)
        baseX.append(0); baseY.append(0)
        s.tracks[j].inSession = true
        s.tracks[j].strokeClaimed = true
    }

    /// Geometry baseline: reset whenever a finger joins, while the session is pending.
    private func rebase(_ s: EngineState) {
        for (k, m) in members.enumerated() { baseX[k] = s.tracks[m].x; baseY[k] = s.tracks[m].y }
        let (cx, cy) = centroid(s)
        lastCX = cx; lastCY = cy; cvx = 0; cvy = 0
        lastT = s.tracks[members.last!].t
        if members.count >= 2 {
            baseD = dist(0, 1, s); lastD = baseD
            baseAngle = angle(0, 1, s); lastAngle = baseAngle
        }
        baseSpread = spread(s)
        rotation = 0; orbitSweep = 0; lastSampleRotation = 0
    }

    private func updateTap(_ s: EngineState, _ emit: (GestureEvent) -> Void) {
        guard tapValid else { return }
        let id: GestureID = members.count == 2 ? .g16 : (members.count == 3 ? .g22 : .g23)
        if tapID == id { return }
        if let old = tapID { emit(event(old, .cancelled, s)) }
        tapID = id
        emit(event(id, .began, s, magnitude: Float(members.count), size: spread(s)))
    }

    private func cancelTap(_ s: EngineState, _ emit: (GestureEvent) -> Void, at t: Double? = nil) {
        tapValid = false
        if let id = tapID { emit(event(id, .cancelled, s, at: t)) }
        tapID = nil
    }

    // MARK: Motion

    override func moved(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        guard active, members.contains(i), !anyLifted else { return }
        if tapID != nil && s.tracks[i].maxDisplacement >= s.config.tapMaxMovement { cancelTap(s, emit) }
        trackMotion(s)
        if kind == .pending {
            guard maxMemberDisplacement(s) >= s.config.multiFingerLockDistance else { return }
            kind = classify(s)
            lockT = s.tracks[i].t
            if let id = continuousID { emit(continuousEvent(id, .began, s)) }
        } else if let id = continuousID {
            emit(continuousEvent(id, .changed, s))
        }
    }

    override func tick(_ s: EngineState, _ emit: (GestureEvent) -> Void) {
        if active, tapID != nil, s.now - startT > s.config.multiFingerTapMaxDuration {
            cancelTap(s, emit, at: s.now)
        }
    }

    /// Rotation at the last speed sample.
    private var lastSampleRotation: Float = 0

    private func trackMotion(_ s: EngineState) {
        let t = members.map { s.tracks[$0].t }.max() ?? lastT
        let dt = Float(t - lastT)
        // Speeds are sampled at most every 2 ms. Fingers arrive as separate events with
        // (nearly) the same timestamp, and tiny steps would produce absurd speeds.
        let sample = dt >= 0.002
        let (cx, cy) = centroid(s)
        if sample {
            let k: Float = 0.4
            cvx += k * ((cx - lastCX) / dt - cvx)
            cvy += k * ((cy - lastCY) / dt - cvy)
            lastCX = cx; lastCY = cy
        }
        if members.count >= 2 {
            let d = dist(0, 1, s)
            let a = angle(0, 1, s)
            var da = a - lastAngle
            if da > .pi { da -= 2 * .pi } else if da < -.pi { da += 2 * .pi }
            rotation += da
            lastAngle = a
            if sample {
                dSpeed += 0.4 * (abs(d - lastD) / dt - dSpeed)
                angularSpeed += 0.4 * ((rotation - lastSampleRotation) / dt - angularSpeed)
                lastSampleRotation = rotation
                lastD = d
            }
            // Orbit: sweep of the moving finger around the still one.
            let still = orbitStill, mover = 1 - orbitStill
            let oa = atan2(s.tracks[members[mover]].y - s.tracks[members[still]].y,
                           s.tracks[members[mover]].x - s.tracks[members[still]].x)
            if kind == .orbit {
                var d2 = oa - orbitLastAngle
                if d2 > .pi { d2 -= 2 * .pi } else if d2 < -.pi { d2 += 2 * .pi }
                orbitSweep += d2
            }
            orbitLastAngle = oa
        }
        if sample { lastT = t }
    }

    private func classify(_ s: EngineState) -> Kind {
        let c = s.config
        let (cx, cy) = centroid(s)
        let (bx, by) = baseCentroid()
        let translation = hypot(cx - bx, cy - by)
        switch members.count {
        case 2:
            let dispA = displacement(0, s), dispB = displacement(1, s)
            if min(dispA, dispB) < c.orbitStillMax && max(dispA, dispB) >= c.multiFingerLockDistance {
                // One finger still: orbit if the other mostly goes around it, else pinch.
                orbitStill = dispA <= dispB ? 0 : 1
                let still = orbitStill, mover = 1 - still
                let bAngle = atan2(baseY[mover] - baseY[still], baseX[mover] - baseX[still])
                let mx = s.tracks[members[mover]].x, my = s.tracks[members[mover]].y
                let sx = s.tracks[members[still]].x, sy = s.tracks[members[still]].y
                var sweep = atan2(my - sy, mx - sx) - bAngle
                if sweep > .pi { sweep -= 2 * .pi } else if sweep < -.pi { sweep += 2 * .pi }
                let r = hypot(mx - sx, my - sy)
                let radial = abs(r - hypot(baseX[mover] - baseX[still], baseY[mover] - baseY[still]))
                if abs(sweep) * r > radial * 1.2 {
                    orbitSweep = sweep
                    orbitLastAngle = atan2(my - sy, mx - sx)
                    return .orbit
                }
                return r < baseD ? .pinchIn : .pinchOut
            }
            let d = dist(0, 1, s)
            let pinch = abs(d - baseD)
            let arc = abs(rotation) * d / 2
            if translation >= max(pinch, arc) { return .drag }
            if pinch >= arc { return d < baseD ? .pinchIn : .pinchOut }
            return .rotate
        case 3, 4:
            let spreadChange = abs(spread(s) - baseSpread)
            return translation >= spreadChange ? .rake : .none
        default:
            let sp = spread(s)
            let spreadChange = abs(sp - baseSpread)
            if spreadChange > translation { return sp < baseSpread ? .gather : .spread }
            return .rake
        }
    }

    private var continuousID: GestureID? {
        switch kind {
        case .drag: return .g17
        case .pinchIn: return .g18
        case .pinchOut: return .g19
        case .rotate: return .g20
        case .orbit: return .g21
        case .rake: return .g26
        case .gather, .spread: return .g24
        case .pending, .none: return nil
        }
    }

    // MARK: Lift

    override func ended(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) { lift(i, s, emit, cancelled: false) }
    override func cancelled(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) { lift(i, s, emit, cancelled: true) }

    private func lift(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void, cancelled: Bool) {
        guard active, let k = members.firstIndex(of: i) else { return }
        s.tracks[i].liftClaimed = true
        if !anyLifted {
            anyLifted = true
            if let id = continuousID, kind != .rake {
                if cancelled {
                    emit(continuousEvent(id, .cancelled, s))
                } else if kind == .gather || kind == .spread {
                    emit(continuousEvent(id, progress(s) >= s.config.gatherMinProgress ? .ended : .cancelled, s))
                } else {
                    emit(continuousEvent(id, .ended, s))
                }
            } else if kind == .rake {
                // A quick, fast three-finger rake was really a swipe (G22).
                let speed = hypot(cvx, cvy)
                if !cancelled && members.count == 3 && s.tracks[i].t - startT <= s.config.swipeMaxDuration
                    && speed >= s.config.swipeMinSpeed {
                    emit(continuousEvent(.g26, .cancelled, s))
                    emit(event(.g22, .fired, s, speed: speed, dirX: cvx / speed, dirY: cvy / speed))
                    kind = .none
                }
            }
        }
        lifted[k] = true
        guard lifted.allSatisfy({ $0 }) else { return }
        // Last finger up.
        if let id = tapID {
            let ok = !cancelled && tapValid && s.tracks[i].t - startT <= s.config.multiFingerTapMaxDuration
                && members.allSatisfy { s.tracks[$0].maxDisplacement < s.config.tapMaxMovement }
            emit(event(id, ok ? .ended : .cancelled, s, magnitude: Float(members.count), size: spread(s)))
        }
        if kind == .rake { emit(continuousEvent(.g26, cancelled ? .cancelled : .ended, s)) }
        for m in members { s.tracks[m].inSession = false }
        active = false
        tapID = nil
        members.removeAll(); lifted.removeAll(); baseX.removeAll(); baseY.removeAll()
    }

    // MARK: Events

    private func continuousEvent(_ id: GestureID, _ phase: GesturePhase, _ s: EngineState) -> GestureEvent {
        let (cx, cy) = centroid(s)
        let speed = hypot(cvx, cvy)
        let dx = speed > 0 ? cvx / speed : 0, dy = speed > 0 ? cvy / speed : 0
        switch kind {
        case .drag:
            let a = members[0], b = members[1]
            return event(id, phase, s, speed: speed, x: s.tracks[a].x, y: s.tracks[a].y, size: dist(0, 1, s),
                         originX: s.tracks[b].x, originY: s.tracks[b].y, dirX: dx, dirY: dy)
        case .pinchIn, .pinchOut:
            return event(id, phase, s, magnitude: baseD > 0 ? dist(0, 1, s) / baseD : 1, speed: dSpeed,
                         x: cx, y: cy, size: dist(0, 1, s))
        case .rotate:
            return event(id, phase, s, magnitude: rotation, tempo: angularSpeed, speed: speed,
                         x: cx, y: cy, size: dist(0, 1, s) / 2)
        case .orbit:
            let still = members[orbitStill], mover = members[1 - orbitStill]
            return event(id, phase, s, magnitude: abs(orbitSweep) / (2 * .pi),
                         speed: s.tracks[mover].speed,
                         x: s.tracks[mover].x, y: s.tracks[mover].y,
                         size: hypot(s.tracks[mover].x - s.tracks[still].x, s.tracks[mover].y - s.tracks[still].y),
                         originX: s.tracks[still].x, originY: s.tracks[still].y)
        case .gather, .spread:
            let p = progress(s)
            return event(id, phase, s, magnitude: kind == .gather ? p : -p, speed: speed, x: cx, y: cy, size: spread(s))
        case .rake, .pending, .none:
            return event(id, phase, s, speed: speed, x: cx, y: cy, size: spread(s), dirX: dx, dirY: dy)
        }
    }

    private func event(_ id: GestureID, _ phase: GesturePhase, _ s: EngineState, at t: Double? = nil,
                       magnitude: Float = 0, tempo: Float = 0, speed: Float = 0,
                       x: Float? = nil, y: Float? = nil, size: Float = 0,
                       originX: Float = 0, originY: Float = 0,
                       dirX: Float = 0, dirY: Float = 0) -> GestureEvent {
        let (cx, cy) = centroid(s)
        var pts: [Float] = []
        pts.reserveCapacity(members.count * 2)
        for m in members { pts.append(s.tracks[m].x); pts.append(s.tracks[m].y) }
        let first = members.first ?? 0
        var e = s.event(id, phase, first, at: t ?? members.map { s.tracks[$0].t }.max(),
                        magnitude: magnitude, tempo: tempo, speed: speed,
                        x: x ?? cx, y: y ?? cy, size: size, originX: originX, originY: originY,
                        dirX: dirX, dirY: dirY,
                        touchPoints: pts, touchIDs: members.map { UInt16($0) })
        e.fingerCount = UInt8(members.count)
        return e
    }

    // MARK: Geometry

    private func centroid(_ s: EngineState) -> (Float, Float) {
        guard !members.isEmpty else { return (0, 0) }
        var x: Float = 0, y: Float = 0
        for m in members { x += s.tracks[m].x; y += s.tracks[m].y }
        return (x / Float(members.count), y / Float(members.count))
    }

    private func baseCentroid() -> (Float, Float) {
        guard !baseX.isEmpty else { return (0, 0) }
        return (baseX.reduce(0, +) / Float(baseX.count), baseY.reduce(0, +) / Float(baseY.count))
    }

    /// Mean distance of the fingers from their centroid.
    private func spread(_ s: EngineState) -> Float {
        guard members.count >= 2 else { return 0 }
        let (cx, cy) = centroid(s)
        var total: Float = 0
        for m in members { total += hypot(s.tracks[m].x - cx, s.tracks[m].y - cy) }
        return total / Float(members.count)
    }

    /// G24: 0 at the start, 1 when the spread has changed by `gatherFullChange`.
    private func progress(_ s: EngineState) -> Float {
        guard baseSpread > 0 else { return 0 }
        let change = abs(spread(s) - baseSpread) / baseSpread
        return min(1, change / s.config.gatherFullChange)
    }

    private func dist(_ a: Int, _ b: Int, _ s: EngineState) -> Float {
        hypot(s.tracks[members[a]].x - s.tracks[members[b]].x, s.tracks[members[a]].y - s.tracks[members[b]].y)
    }

    private func angle(_ a: Int, _ b: Int, _ s: EngineState) -> Float {
        atan2(s.tracks[members[b]].y - s.tracks[members[a]].y, s.tracks[members[b]].x - s.tracks[members[a]].x)
    }

    private func displacement(_ k: Int, _ s: EngineState) -> Float {
        hypot(s.tracks[members[k]].x - baseX[k], s.tracks[members[k]].y - baseY[k])
    }

    private func maxMemberDisplacement(_ s: EngineState) -> Float {
        var m: Float = 0
        for k in members.indices { m = max(m, displacement(k, s)) }
        return m
    }
}

// MARK: - G25 Finger drumming

/// 4 or more quick taps within about 1 s, alternating between 2 or more fingers at
/// different spots. Drum taps may overlap in time, so they are tracked separately
/// from single-finger taps. Fires on each qualifying touch-down (R1), carrying the
/// previous tap point as the origin so the response can link the two.
final class DrummingRecognizer: Recognizer {
    private struct DrumTap { var t: Double; var x: Float; var y: Float }
    /// Fingers landing closer together than this are one multi-finger tap, not drumming.
    private static let simultaneous: Double = 0.04
    private var taps: [DrumTap] = []
    private var live = [Bool](repeating: false, count: 64)

    init() {
        super.init(.g25)
        taps.reserveCapacity(8)
    }

    override func began(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        let tr = s.tracks[i]
        guard tr.kind == .finger, !tr.inSession else { return }
        let c = s.config
        let need = c.drummingMinTaps - 1
        guard taps.count >= need else { return }
        let recent = taps.suffix(need)
        guard let first = recent.first, tr.startT - first.t <= c.drummingWindow else { return }
        // Alternating: consecutive taps (including this one) land on different spots.
        var changes = 0
        var prev = first
        for t in recent.dropFirst() {
            if hypot(t.x - prev.x, t.y - prev.y) > c.drummingMinSpotDistance { changes += 1 }
            prev = t
        }
        if hypot(tr.startX - prev.x, tr.startY - prev.y) > c.drummingMinSpotDistance { changes += 1 }
        guard changes >= need - 1 else { return }
        live[i] = true
        s.tracks[i].drumming = true
        let tempo = Float(Double(need) / max(0.05, tr.startT - first.t))
        emit(s.event(id, .began, i, tempo: tempo, originX: prev.x, originY: prev.y))
    }

    override func moved(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        if live[i] && s.tracks[i].maxDisplacement >= s.config.tapMaxMovement {
            live[i] = false
            emit(s.event(id, .cancelled, i))
        }
    }

    override func ended(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        let tr = s.tracks[i]
        let quick = tr.kind == .finger && tr.duration <= s.config.tapMaxDuration
            && tr.maxDisplacement < s.config.tapMaxMovement
        if quick && (taps.last.map { tr.startT - $0.t >= Self.simultaneous } ?? true) {
            if taps.count == 8 { taps.removeFirst() }
            taps.append(DrumTap(t: tr.startT, x: tr.startX, y: tr.startY))
        }
        guard live[i] else { return }
        live[i] = false
        if quick { s.tracks[i].liftClaimed = true }
        emit(s.event(id, quick ? .ended : .cancelled, i))
    }

    override func cancelled(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        if live[i] { live[i] = false; emit(s.event(id, .cancelled, i)) }
    }

    /// Fingers landing together are a multi-finger gesture, not a drum hit.
    override func yieldToMultiFinger(_ i: Int, _ s: EngineState, _ emit: (GestureEvent) -> Void) {
        cancelled(i, s, emit)
    }
}
