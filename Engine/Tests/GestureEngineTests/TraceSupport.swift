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
}

/// Runs a trace through a fresh engine, ticking at 120 Hz, and returns every event emitted.
func runTrace(_ trace: TouchTrace, config: GestureConfig = .default, tail: Double = 0.6) -> [GestureEvent] {
    let data = try! JSONEncoder().encode(trace)
    let events = try! JSONDecoder().decode(TouchTrace.self, from: data)
        .enumerated().sorted { ($0.element.timestamp, $0.offset) < ($1.element.timestamp, $1.offset) }
        .map(\.element)
    guard let first = events.first, let last = events.last else { return [] }
    let engine = GestureEngine(config: config)
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
    return out
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
