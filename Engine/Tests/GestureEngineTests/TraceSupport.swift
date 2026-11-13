import Foundation
@testable import GestureEngine

/// Builds synthetic TouchTraces. Every trace is round-tripped through JSON before it
/// runs, so the tests exercise the same format recorded device traces will use.
struct TraceBuilder {
    var events: TouchTrace = []

    mutating func tap(_ id: UInt16 = 0, at t: Double, x: Float = 200, y: Float = 300,
                      duration: Double = 0.08, move: Float = 0, kind: TouchKind = .finger) {
        events.append(TouchEvent(touchID: id, phase: .began, kind: kind, timestamp: t, x: x, y: y))
        if move > 0 {
            events.append(TouchEvent(touchID: id, phase: .moved, kind: kind, timestamp: t + duration / 2, x: x + move / 2, y: y))
            events.append(TouchEvent(touchID: id, phase: .moved, kind: kind, timestamp: t + duration, x: x + move, y: y))
        }
        events.append(TouchEvent(touchID: id, phase: .ended, kind: kind, timestamp: t + duration, x: x + move, y: y))
    }

    /// A still hold with tiny jitter, then lift.
    mutating func hold(_ id: UInt16 = 0, at t: Double, x: Float = 200, y: Float = 300, duration: Double) {
        events.append(TouchEvent(touchID: id, phase: .began, kind: .finger, timestamp: t, x: x, y: y))
        var k = 1
        while Double(k) * 0.05 < duration {
            events.append(TouchEvent(touchID: id, phase: .moved, kind: .finger, timestamp: t + Double(k) * 0.05,
                                     x: x + (k % 2 == 0 ? 1 : -1), y: y))
            k += 1
        }
        events.append(TouchEvent(touchID: id, phase: .ended, kind: .finger, timestamp: t + duration, x: x, y: y))
    }

    /// A straight drag sampled at 120 Hz. `lift` false leaves the touch down.
    mutating func drag(_ id: UInt16 = 0, at t: Double, from: (Float, Float), to: (Float, Float),
                       duration: Double, kind: TouchKind = .finger, lift: Bool = true) {
        events.append(TouchEvent(touchID: id, phase: .began, kind: kind, timestamp: t, x: from.0, y: from.1))
        let steps = max(2, Int(duration * 120))
        for k in 1...steps {
            let f = Float(k) / Float(steps)
            events.append(TouchEvent(touchID: id, phase: .moved, kind: kind, timestamp: t + duration * Double(f),
                                     x: from.0 + (to.0 - from.0) * f, y: from.1 + (to.1 - from.1) * f))
        }
        if lift {
            events.append(TouchEvent(touchID: id, phase: .ended, kind: kind, timestamp: t + duration, x: to.0, y: to.1))
        }
    }

    mutating func add(_ e: TouchEvent) { events.append(e) }

    /// A stroke through `points`, sampled at 120 Hz with even spacing along the path.
    /// `pauseAt` holds the finger still at that fraction of the path for `pause` seconds.
    mutating func path(_ id: UInt16 = 0, at t: Double, points: [(Float, Float)], duration: Double,
                       kind: TouchKind = .finger, pauseAt: Double? = nil, pause: Double = 0,
                       lift: Bool = true) {
        var lengths: [Float] = [0]
        for k in 1..<points.count {
            lengths.append(lengths[k - 1] + hypot(points[k].0 - points[k - 1].0, points[k].1 - points[k - 1].1))
        }
        let total = lengths.last!
        func at(_ f: Float) -> (Float, Float) {
            let d = f * total
            var k = 1
            while k < lengths.count - 1 && lengths[k] < d { k += 1 }
            let seg = max(1e-6, lengths[k] - lengths[k - 1])
            let u = min(1, max(0, (d - lengths[k - 1]) / seg))
            return (points[k - 1].0 + (points[k].0 - points[k - 1].0) * u,
                    points[k - 1].1 + (points[k].1 - points[k - 1].1) * u)
        }
        events.append(TouchEvent(touchID: id, phase: .began, kind: kind, timestamp: t, x: points[0].0, y: points[0].1))
        let steps = max(2, Int(duration * 120))
        var time = t
        var paused = false
        for k in 1...steps {
            let f = Float(k) / Float(steps)
            time = t + duration * Double(f) + (paused ? pause : 0)
            if let p = pauseAt, !paused, Double(f) >= p {
                paused = true
                let q = at(f)
                var pt = time
                while pt < time + pause {   // still finger: tiny jitter keeps samples coming
                    pt += 1.0 / 60
                    events.append(TouchEvent(touchID: id, phase: .moved, kind: kind, timestamp: pt, x: q.0 + 0.5, y: q.1))
                }
                time += pause
            }
            let q = at(f)
            events.append(TouchEvent(touchID: id, phase: .moved, kind: kind, timestamp: time, x: q.0, y: q.1))
        }
        if lift {
            let q = at(1)
            events.append(TouchEvent(touchID: id, phase: .ended, kind: kind, timestamp: time, x: q.0, y: q.1))
        }
    }
}

/// Points on a circle or spiral around (cx, cy).
func spiralPoints(cx: Float = 300, cy: Float = 400, from r0: Float, to r1: Float, turns: Float,
                  startAngle: Float = 0, n: Int = 120) -> [(Float, Float)] {
    (0...n).map { k in
        let f = Float(k) / Float(n)
        let a = startAngle + f * turns * 2 * .pi
        let r = r0 + (r1 - r0) * f
        return (cx + r * cos(a), cy + r * sin(a))
    }
}

/// A zigzag of `legs` straight legs across `width`, each `height` tall.
func zigzagPoints(x: Float = 100, y: Float = 400, width: Float, height: Float, legs: Int) -> [(Float, Float)] {
    (0...legs).map { k in (x + width * Float(k) / Float(legs), y + (k % 2 == 0 ? 0 : height)) }
}

/// Runs a trace through a fresh engine, ticking at 120 Hz, and returns every event emitted.
/// A canvas with one horizontal stroke from (100, 300) to (500, 300), for contextual gestures.
final class MockInk: InkHitTesting {
    var y: Float = 300, x0: Float = 100, x1: Float = 500
    func hitStroke(x: Float, y: Float, radius: Float) -> StrokeHit? {
        guard x >= x0 - radius, x <= x1 + radius, abs(y - self.y) <= radius else { return nil }
        let cx = min(x1, max(x0, x))
        return StrokeHit(strokeID: 7, x: cx, y: self.y, along: cx - x0, length: x1 - x0)
    }
    func crossing(x0 ax: Float, y0 ay: Float, x1 bx: Float, y1 by: Float) -> StrokeCrossing? {
        guard (ay - y) * (by - y) <= 0, ay != by else { return nil }
        let t = (y - ay) / (by - ay)
        let x = ax + (bx - ax) * t
        guard x >= x0, x <= x1 else { return nil }
        return StrokeCrossing(strokeID: 7, x: x, y: y, dirX: 1, dirY: 0)
    }
}

func runTrace(_ trace: TouchTrace, config: GestureConfig = .default, tail: Double = 0.6,
              ink: InkHitTesting? = nil, canvas: (Float, Float)? = nil, idleCheck: Bool = false) -> [GestureEvent] {
    let data = try! JSONEncoder().encode(trace)
    let events = try! JSONDecoder().decode(TouchTrace.self, from: data)
        .enumerated().sorted { ($0.element.timestamp, $0.offset) < ($1.element.timestamp, $1.offset) }
        .map(\.element)
    guard let first = events.first, let last = events.last else { return [] }
    let engine = GestureEngine(config: config)
    engine.ink = ink
    if let canvas { engine.setCanvasSize(width: canvas.0, height: canvas.1) }
    var out: [GestureEvent] = []
    var t = first.timestamp
    var idx = 0
    while t <= last.timestamp + tail {
        while idx < events.count && events[idx].timestamp <= t {
            engine.process(events[idx]) { out.append($0) }
            idx += 1
        }
        engine.tick(now: t) { out.append($0) }
        t += 1.0 / 120
    }
    // Idle (G32) is ambient: hide it unless a test asks for it.
    return idleCheck ? out : out.filter { $0.gesture != .g32 }
}

extension Array where Element == GestureEvent {
    func count(_ id: GestureID, _ phase: GesturePhase) -> Int {
        filter { $0.gesture == id && $0.phase == phase }.count
    }
    func has(_ id: GestureID, _ phase: GesturePhase) -> Bool { count(id, phase) > 0 }
    func first(_ id: GestureID, _ phase: GesturePhase) -> GestureEvent? {
        first { $0.gesture == id && $0.phase == phase }
    }
}
