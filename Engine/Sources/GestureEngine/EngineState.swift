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

    public var duration: Double { t - startT }
    public var speed: Float { (vx * vx + vy * vy).squareRoot() }
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

    private(set) var taps: [TapRecord] = []
    private let tapCapacity = 8

    init(config: GestureConfig) {
        self.config = config
        taps.reserveCapacity(tapCapacity)
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
        tr.majorRadius = e.majorRadius
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
        let dt = Float(e.timestamp - tr.t)
        if dt > 0 {
            let k: Float = 0.4
            tr.vx += k * ((e.x - tr.x) / dt - tr.vx)
            tr.vy += k * ((e.y - tr.y) / dt - tr.vy)
        }
        tr.x = e.x; tr.y = e.y; tr.t = e.timestamp; tr.lastMoveT = e.timestamp
        let ox = e.x - tr.startX, oy = e.y - tr.startY
        tr.maxDisplacement = max(tr.maxDisplacement, (ox * ox + oy * oy).squareRoot())
        tracks[i] = tr
    }

    /// Updates position for a lift without counting it as motion.
    func touchLift(_ i: Int, _ e: TouchEvent) {
        let ox = e.x - tracks[i].startX, oy = e.y - tracks[i].startY
        tracks[i].maxDisplacement = max(tracks[i].maxDisplacement, (ox * ox + oy * oy).squareRoot())
        tracks[i].x = e.x; tracks[i].y = e.y; tracks[i].t = e.timestamp
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
               magnitude: Float = 0, tempo: Float = 0, speed: Float? = nil) -> GestureEvent {
        let tr = tracks[i]
        let s = speed ?? tr.speed
        let v = tr.speed
        return GestureEvent(gesture: id, phase: phase, timestamp: t ?? tr.t, x: tr.x, y: tr.y,
                            speed: s,
                            directionX: v > 0 ? tr.vx / v : 0, directionY: v > 0 ? tr.vy / v : 0,
                            fingerCount: UInt8(max(1, fingersDown)),
                            magnitude: magnitude, tempo: tempo, touchID: UInt16(i))
    }
}
