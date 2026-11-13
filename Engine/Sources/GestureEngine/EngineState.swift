/// Per-touch facts shared by every recognizer. The arbiter keeps these up to date;
/// recognizers read them and set the claim flags.
public struct TouchTrack: Sendable {
    public var active = false
    public var kind: TouchKind = .finger
    public var startX: Float = 0, startY: Float = 0, startT: Double = 0
    public var x: Float = 0, y: Float = 0, t: Double = 0
    public var lastMoveT: Double = 0
    public var maxDisplacement: Float = 0
    /// Smoothed velocity in points per second.
    public var vx: Float = 0, vy: Float = 0
    /// Last velocity sample point.
    var velX: Float = 0, velY: Float = 0, velT: Double = 0
    public var majorRadius: Float = 0
    /// Another finger was down at some point during this touch.
    public var multiFinger = false
    /// Position in the current run of quick taps (1 = first tap).
    public var tapSequenceIndex = 1

    // Claims, set by recognizers.
    public var drawing = false
    public var holding = false
    public var holdBroken = false
    /// A one-shot gesture consumed this touch's lift, so G31 stays quiet.
    public var liftClaimed = false
    /// Another gesture owns this stroke (scribble, slingshot): G7 must not draw it.
    public var strokeClaimed = false
    public var scribbling = false
    public var slingshot = false
    /// A G5 hold turned into a drag (G14).
    public var holdDragging = false
    /// Part of a finger-drumming run (G25): rhythm (G4) yields to it (R2).
    public var drumming = false
    /// Member of a multi-finger session.
    public var inSession = false
    /// A contextual gesture (G27, G30) took this touch-down, so the single-finger
    /// tap family stays quiet (R2).
    public var contextual = false

    public var duration: Double { t - startT }
    public var speed: Float { (vx * vx + vy * vy).squareRoot() }
}

struct PathPoint {
    var x: Float
    var y: Float
    var t: Double
}

struct TapRecord {
    var downT: Double
    var upT: Double
    var x: Float
    var y: Float
    var sequenceIndex: Int
}

/// Shared mutable state owned by the arbiter. Fixed-size storage, no allocation per event.
final class EngineState {
    let config: GestureConfig
    var tracks = [TouchTrack](repeating: TouchTrack(), count: 64)
    var fingersDown = 0
    var now: Double = 0
    /// Canvas size in points (edge gestures).
    var canvasWidth: Float = 0, canvasHeight: Float = 0
    /// Committed ink, for contextual gestures.
    weak var ink: InkHitTesting?
    /// Last time any touch was down, for idle (G32). Negative until the first tick.
    var lastActivity: Double = -1
    var lastTouchX: Float = 0, lastTouchY: Float = 0

    private(set) var taps: [TapRecord] = []
    private let tapCapacity = 8
    /// Real samples of each touch, for after-the-fact shape recognition.
    private(set) var paths: [[PathPoint]]
    private var shapes = [ShapeInfo?](repeating: nil, count: 64)

    init(config: GestureConfig) {
        self.config = config
        taps.reserveCapacity(tapCapacity)
        paths = (0..<64).map { _ in var a = [PathPoint](); a.reserveCapacity(512); return a }
    }

    /// Shape analysis of touch `i`'s path, computed once on first use.
    func shape(_ i: Int) -> ShapeInfo {
        if let s = shapes[i] { return s }
        let s = ShapeInfo.analyze(paths[i], config: config)
        shapes[i] = s
        return s
    }

    var lastTap: TapRecord? { taps.last }

    /// Down-times of the most recent `count` confirmed taps, oldest first.
    func recentTapDownTimes(_ count: Int) -> ArraySlice<TapRecord> {
        taps.suffix(count)
    }

    func begin(_ i: Int, _ e: TouchEvent) {
        var tr = TouchTrack()
        tr.active = true
        tr.kind = e.kind
        tr.startX = e.x; tr.startY = e.y; tr.startT = e.timestamp
        tr.x = e.x; tr.y = e.y; tr.t = e.timestamp; tr.lastMoveT = e.timestamp
        tr.velX = e.x; tr.velY = e.y; tr.velT = e.timestamp
        tr.majorRadius = e.majorRadius
        paths[i].removeAll(keepingCapacity: true)
        paths[i].append(PathPoint(x: e.x, y: e.y, t: e.timestamp))
        shapes[i] = nil
        if e.kind == .finger {
            fingersDown += 1
            if fingersDown > 1 {
                tr.multiFinger = true
                for j in 0..<tracks.count where tracks[j].active && tracks[j].kind == .finger {
                    tracks[j].multiFinger = true
                }
            }
            if let last = taps.last {
                let dx = e.x - last.x, dy = e.y - last.y
                let close = (dx * dx + dy * dy).squareRoot() <= config.doubleTapMaxDistance
                if close && e.timestamp - last.upT <= config.multiTapMaxInterval {
                    tr.tapSequenceIndex = last.sequenceIndex + 1
                }
            }
        }
        tracks[i] = tr
    }

    func move(_ i: Int, _ e: TouchEvent) {
        var tr = tracks[i]
        // Velocity is sampled against an anchor at least 2 ms old, so samples that
        // arrive with (nearly) the same timestamp cannot produce absurd speeds.
        let dt = Float(e.timestamp - tr.velT)
        if dt >= 0.002 {
            let k: Float = 0.4
            tr.vx += k * ((e.x - tr.velX) / dt - tr.vx)
            tr.vy += k * ((e.y - tr.velY) / dt - tr.vy)
            tr.velX = e.x; tr.velY = e.y; tr.velT = e.timestamp
        }
        tr.x = e.x; tr.y = e.y; tr.t = e.timestamp; tr.lastMoveT = e.timestamp
        let ox = e.x - tr.startX, oy = e.y - tr.startY
        tr.maxDisplacement = max(tr.maxDisplacement, (ox * ox + oy * oy).squareRoot())
        tracks[i] = tr
        paths[i].append(PathPoint(x: e.x, y: e.y, t: e.timestamp))
    }

    /// Updates position for a lift without counting it as motion.
    func touchLift(_ i: Int, _ e: TouchEvent) {
        let ox = e.x - tracks[i].startX, oy = e.y - tracks[i].startY
        tracks[i].maxDisplacement = max(tracks[i].maxDisplacement, (ox * ox + oy * oy).squareRoot())
        tracks[i].x = e.x; tracks[i].y = e.y; tracks[i].t = e.timestamp
        if let last = paths[i].last, last.x != e.x || last.y != e.y {
            paths[i].append(PathPoint(x: e.x, y: e.y, t: e.timestamp))
            shapes[i] = nil
        }
    }

    func isValidTap(_ i: Int) -> Bool {
        let tr = tracks[i]
        return tr.kind == .finger && !tr.multiFinger
            && tr.duration <= config.tapMaxDuration
            && tr.maxDisplacement < config.tapMaxMovement
    }

    /// Speed at the moment of lift: zero if the finger had already stopped.
    func speedAtLift(_ i: Int) -> Float {
        let tr = tracks[i]
        return tr.t - tr.lastMoveT <= 0.05 ? tr.speed : 0
    }

    func end(_ i: Int) {
        let tr = tracks[i]
        guard tr.active else { return }
        if tr.kind == .finger {
            fingersDown = max(0, fingersDown - 1)
            if isValidTap(i) {
                if taps.count == tapCapacity { taps.removeFirst() }
                taps.append(TapRecord(downT: tr.startT, upT: tr.t, x: tr.startX, y: tr.startY,
                                      sequenceIndex: tr.tapSequenceIndex))
            }
        }
        tracks[i].active = false
    }

    func event(_ id: GestureID, _ phase: GesturePhase, _ i: Int, at t: Double? = nil,
               magnitude: Float = 0, tempo: Float = 0, speed: Float? = nil,
               x: Float? = nil, y: Float? = nil, size: Float = 0,
               originX: Float = 0, originY: Float = 0,
               dirX: Float? = nil, dirY: Float? = nil,
               touchPoints: [Float] = [], touchIDs: [UInt16] = [], targetID: UInt32 = 0) -> GestureEvent {
        let tr = tracks[i]
        let s = speed ?? tr.speed
        let v = tr.speed
        return GestureEvent(gesture: id, phase: phase, timestamp: t ?? tr.t, x: x ?? tr.x, y: y ?? tr.y,
                            speed: s,
                            directionX: dirX ?? (v > 0 ? tr.vx / v : 0), directionY: dirY ?? (v > 0 ? tr.vy / v : 0),
                            fingerCount: UInt8(max(1, fingersDown)),
                            magnitude: magnitude, tempo: tempo, touchID: UInt16(i),
                            size: size, originX: originX, originY: originY,
                            touchPoints: touchPoints, touchIDs: touchIDs, targetID: targetID)
    }
}
