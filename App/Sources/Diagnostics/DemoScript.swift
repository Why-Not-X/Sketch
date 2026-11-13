#if DEBUG
import QuartzCore
import Foundation
import GestureEngine

/// Debug-only scripted input for checking gestures where nobody can touch the screen
/// (headless Simulator runs). Launch with `-demo`. Events go through the normal
/// input path, injected in real time with real timestamps.
///
/// Timeline (seconds after launch + 0.5):
///  0.0 tap · 0.6 double tap · 1.4 triple tap · 2.4 hold 1.0 s and release ·
///  4.0–5.5 rhythm (4 taps, 0.5 s apart) · 6.0 fast stroke with lift
enum DemoScript {
    private struct Step { var at: Double; var id: UInt16; var phase: TouchPhase; var x: Float; var y: Float }

    static func startIfRequested(input: TouchInput, size: @escaping () -> (Float, Float)) {
        let args = ProcessInfo.processInfo.arguments
        let m3 = args.contains("-demo3"), m4 = args.contains("-demo4"), m5 = args.contains("-demo5")
        guard args.contains("-demo") || m3 || m4 || m5 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let (w, h) = size()
            let steps = m5 ? scriptM5(w: w, h: h)
                : m4 ? scriptM4(w: w, h: h) : (m3 ? scriptM3(w: w, h: h) : script(w: w, h: h))
            let t0 = CACurrentMediaTime()
            input.schedule(steps.map {
                TouchEvent(touchID: $0.id, phase: $0.phase, kind: .finger, timestamp: t0 + $0.at,
                           x: $0.x, y: $0.y, majorRadius: 12)
            })
        }
    }

    private static func script(w: Float, h: Float) -> [Step] {
        var out: [Step] = []
        func tap(_ t: Double, _ x: Float, _ y: Float, id: UInt16 = 20) {
            out.append(Step(at: t, id: id, phase: .began, x: x, y: y))
            out.append(Step(at: t + 0.07, id: id, phase: .ended, x: x, y: y))
        }
        tap(0.0, w * 0.25, h * 0.2)                                  // G1
        tap(0.6, w * 0.75, h * 0.2); tap(0.8, w * 0.75, h * 0.2)     // G2
        tap(1.4, w * 0.5, h * 0.36); tap(1.6, w * 0.5, h * 0.36); tap(1.8, w * 0.5, h * 0.36)  // G3
        out.append(Step(at: 2.4, id: 21, phase: .began, x: w * 0.3, y: h * 0.55))             // G5
        out.append(Step(at: 3.4, id: 21, phase: .ended, x: w * 0.3, y: h * 0.55))             // G6
        for k in 0..<4 { tap(4.0 + Double(k) * 0.5, w * (0.62 + 0.06 * Float(k)), h * 0.55) }  // G4
        let steps = 24
        for k in 0...steps {                                                                  // G7 + G31 trail
            let f = Float(k) / Float(steps)
            let phase: TouchPhase = k == 0 ? .began : (k == steps ? .ended : .moved)
            out.append(Step(at: 6.0 + Double(k) / 120, id: 22, phase: phase,
                            x: w * (0.15 + 0.7 * f), y: h * (0.82 - 0.08 * sin(f * .pi))))
        }
        return out
    }

    /// M3 timeline (`-demo3`), seconds after launch + 0.5:
    ///  0.0 line, 0.7 scribble across it (G9) · 2.0 circle (G10) · 3.3 inward spiral (G11) ·
    ///  4.8 zigzag (G12) · 6.0 flick (G8) · 6.6 slingshot (G13) · 7.8 hold-drag (G14) ·
    ///  9.4 stroke with a dwell (G15)
    private static func scriptM3(w: Float, h: Float) -> [Step] {
        var out: [Step] = []
        func stroke(_ t: Double, id: UInt16, _ pts: [(Float, Float)], duration: Double,
                    pauseAtStep: Int? = nil, pause: Double = 0) {
            var time = t
            for (k, p) in pts.enumerated() {
                let phase: TouchPhase = k == 0 ? .began : (k == pts.count - 1 ? .ended : .moved)
                out.append(Step(at: time, id: id, phase: phase, x: p.0, y: p.1))
                time += duration / Double(pts.count - 1)
                if k == pauseAtStep {
                    var pt = 0.0
                    while pt < pause { pt += 1.0 / 60; out.append(Step(at: time + pt, id: id, phase: .moved, x: p.0 + (Int(pt * 60) % 2 == 0 ? 0.5 : -0.5), y: p.1)) }
                    time += pause
                }
            }
        }
        func line(_ a: (Float, Float), _ b: (Float, Float), n: Int) -> [(Float, Float)] {
            (0...n).map { k in let f = Float(k) / Float(n); return (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f) }
        }
        func spiral(_ cx: Float, _ cy: Float, _ r0: Float, _ r1: Float, turns: Float, n: Int) -> [(Float, Float)] {
            (0...n).map { k in
                let f = Float(k) / Float(n), a = f * turns * 2 * .pi, r = r0 + (r1 - r0) * f
                return (cx + r * cos(a), cy + r * sin(a))
            }
        }
        // G7 line, then a G9 scribble across its middle.
        stroke(0.0, id: 20, line((w * 0.12, h * 0.16), (w * 0.88, h * 0.16), n: 40), duration: 0.4)
        var zig: [(Float, Float)] = []
        for k in 0...10 { zig.append((w * 0.42 + Float(k % 2) * 45, h * 0.13 + Float(k) * 3)) }
        stroke(0.7, id: 21, zig.flatMap { p in [p] }.enumerated().flatMap { (k, p) -> [(Float, Float)] in
            guard k > 0 else { return [p] }
            let q = zig[k - 1]
            return (1...6).map { j in let f = Float(j) / 6; return (q.0 + (p.0 - q.0) * f, q.1 + (p.1 - q.1) * f) }
        }, duration: 0.7)
        stroke(2.0, id: 22, spiral(w * 0.28, h * 0.38, 70, 70, turns: 1.02, n: 80), duration: 0.8)        // G10
        stroke(3.3, id: 23, spiral(w * 0.72, h * 0.38, 110, 15, turns: 2.2, n: 140), duration: 1.2)       // G11
        stroke(4.8, id: 24, [(w * 0.1, h * 0.6), (w * 0.28, h * 0.53), (w * 0.46, h * 0.6), (w * 0.64, h * 0.53), (w * 0.82, h * 0.6)]
            .enumerated().flatMap { (k, p) -> [(Float, Float)] in
                guard k > 0 else { return [p] }
                let q: (Float, Float) = [(w * 0.1, h * 0.6), (w * 0.28, h * 0.53), (w * 0.46, h * 0.6), (w * 0.64, h * 0.53)][k - 1]
                return (1...10).map { j in let f = Float(j) / 10; return (q.0 + (p.0 - q.0) * f, q.1 + (p.1 - q.1) * f) }
            }, duration: 0.8)                                                                               // G12
        stroke(6.0, id: 25, line((w * 0.2, h * 0.7), (w * 0.55, h * 0.66), n: 12), duration: 0.1)          // G8
        out.append(Step(at: 6.6, id: 26, phase: .began, x: w * 0.25, y: h * 0.85))                         // G13 tap
        out.append(Step(at: 6.67, id: 26, phase: .ended, x: w * 0.25, y: h * 0.85))
        stroke(6.8, id: 27, line((w * 0.25, h * 0.85), (w * 0.6, h * 0.92), n: 30), duration: 0.6)         // G13 drag
        out.append(Step(at: 7.8, id: 28, phase: .began, x: w * 0.75, y: h * 0.8))                          // G14
        stroke(8.4, id: 28, line((w * 0.75, h * 0.8), (w * 0.55, h * 0.74), n: 30), duration: 0.5)
        out.removeAll { $0.id == 28 && $0.phase == .began && $0.at > 8 }
        stroke(9.4, id: 29, line((w * 0.1, h * 0.95), (w * 0.9, h * 0.95), n: 40), duration: 0.8,         // G15
               pauseAtStep: 20, pause: 0.9)
        return out
    }

    /// M4 timeline (`-demo4`), multi-touch injected through the normal input path:
    ///  0.0 two-finger tap · 0.8 three-finger tap · 1.6 four-finger splash · 2.6 two-finger
    ///  drag (ribbon) · 3.6 pinch out (ripple) · 4.6 rotate · 5.8 orbit · 7.4 rake ·
    ///  8.6 three-finger swipe · 9.3 drumming · 10.6 five-finger gather · 12.0 spread
    private static func scriptM4(w: Float, h: Float) -> [Step] {
        var out: [Step] = []
        /// Fingers move from `from[k]` to `to[k]`; `path` (optional) overrides finger k's position at f.
        func fingers(_ t: Double, ids: [UInt16], from: [(Float, Float)], to: [(Float, Float)], duration: Double,
                     path: ((Int, Float) -> (Float, Float))? = nil) {
            for (k, id) in ids.enumerated() { out.append(Step(at: t + Double(k) * 0.015, id: id, phase: .began, x: from[k].0, y: from[k].1)) }
            let start = t + Double(ids.count) * 0.015
            let n = max(2, Int(duration * 60))
            for j in 1...n {
                let f = Float(j) / Float(n)
                for (k, id) in ids.enumerated() {
                    let p = path?(k, f) ?? (from[k].0 + (to[k].0 - from[k].0) * f, from[k].1 + (to[k].1 - from[k].1) * f)
                    out.append(Step(at: start + duration * Double(f), id: id, phase: j == n ? .ended : .moved, x: p.0, y: p.1))
                }
            }
        }
        func tapAll(_ t: Double, ids: [UInt16], _ pts: [(Float, Float)]) {
            fingers(t, ids: ids, from: pts, to: pts, duration: 0.1)
        }
        tapAll(0.0, ids: [20, 21], [(w * 0.3, h * 0.15), (w * 0.55, h * 0.15)])                              // G16
        tapAll(0.8, ids: [20, 21, 22], [(w * 0.4, h * 0.25), (w * 0.6, h * 0.25), (w * 0.5, h * 0.33)])       // G22 tap
        tapAll(1.6, ids: [20, 21, 22, 23], [(w * 0.35, h * 0.4), (w * 0.45, h * 0.37), (w * 0.55, h * 0.37), (w * 0.65, h * 0.4)]) // G23
        fingers(2.6, ids: [20, 21], from: [(w * 0.1, h * 0.45), (w * 0.3, h * 0.45)],
                to: [(w * 0.45, h * 0.6), (w * 0.65, h * 0.57)], duration: 0.7)                                // G17 ribbon
        fingers(3.6, ids: [20, 21], from: [(w * 0.45, h * 0.52), (w * 0.55, h * 0.52)],
                to: [(w * 0.25, h * 0.52), (w * 0.75, h * 0.52)], duration: 0.3)                                // G19
        let rc: (Float, Float) = (w * 0.65, h * 0.72)
        fingers(4.6, ids: [20, 21], from: [(rc.0 - 60, rc.1), (rc.0 + 60, rc.1)], to: [(0, 0), (0, 0)], duration: 0.7) { k, f in
            let a = f * 2.1 + (k == 0 ? Float.pi : 0)
            return (rc.0 + 60 * cos(a), rc.1 + 60 * sin(a))
        }                                                                                                      // G20
        let oc: (Float, Float) = (w * 0.3, h * 0.78)
        out.append(Step(at: 5.8, id: 24, phase: .began, x: oc.0, y: oc.1))                                   // G21 core
        fingers(6.0, ids: [25], from: [(oc.0 + 70, oc.1)], to: [(0, 0)], duration: 1.0) { _, f in
            (oc.0 + 70 * cos(f * 2 * .pi), oc.1 + 70 * sin(f * 2 * .pi))
        }
        out.append(Step(at: 7.1, id: 24, phase: .ended, x: oc.0, y: oc.1))
        fingers(7.4, ids: [20, 21, 22], from: [(w * 0.55, h * 0.6), (w * 0.68, h * 0.6), (w * 0.81, h * 0.6)],
                to: [(w * 0.5, h * 0.92), (w * 0.63, h * 0.92), (w * 0.76, h * 0.92)], duration: 0.9)          // G26 rake
        fingers(8.6, ids: [20, 21, 22], from: [(w * 0.1, h * 0.2), (w * 0.1, h * 0.26), (w * 0.1, h * 0.32)],
                to: [(w * 0.6, h * 0.2), (w * 0.6, h * 0.26), (w * 0.6, h * 0.32)], duration: 0.12)             // G22 swipe
        for k in 0..<6 {                                                                                      // G25
            let x = k % 2 == 0 ? w * 0.15 : w * 0.35
            out.append(Step(at: 9.3 + Double(k) * 0.14, id: UInt16(26 + k % 2), phase: .began, x: x, y: h * 0.93))
            out.append(Step(at: 9.36 + Double(k) * 0.14, id: UInt16(26 + k % 2), phase: .ended, x: x, y: h * 0.93))
        }
        let cc: (Float, Float) = (w * 0.5, h * 0.5)
        let ring = (0..<5).map { k -> Float in Float(k) / 5 * 2 * .pi }
        fingers(10.6, ids: [20, 21, 22, 23, 24], from: ring.map { (cc.0 + 150 * cos($0), cc.1 + 150 * sin($0)) },
                to: ring.map { (cc.0 + 40 * cos($0), cc.1 + 40 * sin($0)) }, duration: 0.6)                     // G24 gather
        fingers(12.0, ids: [20, 21, 22, 23, 24], from: ring.map { (cc.0 + 40 * cos($0), cc.1 + 40 * sin($0)) },
                to: ring.map { (cc.0 + 150 * cos($0), cc.1 + 150 * sin($0)) }, duration: 0.5)                   // G24 spread
        return out
    }

    /// M5 timeline (`-demo5`): 0.0 line · 0.8 tap on it (G27) · 1.8 stroke across it
    /// (G28) · 2.8 closed square (G29) · 4.6 left-edge touch, 5.2 bottom-edge touch
    /// (G30) · then quiet: idle (G32) from about 10 s, dimming after 40 s · 44 s a tap wakes it.
    private static func scriptM5(w: Float, h: Float) -> [Step] {
        var out: [Step] = []
        func stroke(_ t: Double, id: UInt16, _ pts: [(Float, Float)], duration: Double, n: Int = 40) {
            var lengths: [Float] = [0]
            for k in 1..<pts.count { lengths.append(lengths[k - 1] + hypot(pts[k].0 - pts[k - 1].0, pts[k].1 - pts[k - 1].1)) }
            let total = lengths.last!
            for j in 0...n {
                let d = Float(j) / Float(n) * total
                var k = 1
                while k < lengths.count - 1 && lengths[k] < d { k += 1 }
                let f = (d - lengths[k - 1]) / max(1e-3, lengths[k] - lengths[k - 1])
                let x = pts[k - 1].0 + (pts[k].0 - pts[k - 1].0) * f, y = pts[k - 1].1 + (pts[k].1 - pts[k - 1].1) * f
                out.append(Step(at: t + duration * Double(j) / Double(n), id: id,
                                phase: j == 0 ? .began : (j == n ? .ended : .moved), x: x, y: y))
            }
        }
        func tap(_ t: Double, _ x: Float, _ y: Float, id: UInt16 = 21) {
            out.append(Step(at: t, id: id, phase: .began, x: x, y: y))
            out.append(Step(at: t + 0.08, id: id, phase: .ended, x: x, y: y))
        }
        stroke(0.0, id: 20, [(w * 0.1, h * 0.3), (w * 0.9, h * 0.3)], duration: 0.5)                      // G7
        tap(0.8, w * 0.35, h * 0.3 + 4)                                                                   // G27
        stroke(1.8, id: 22, [(w * 0.65, h * 0.18), (w * 0.62, h * 0.45)], duration: 0.4)                  // G28
        let sq: [(Float, Float)] = [(w * 0.2, h * 0.55), (w * 0.8, h * 0.55), (w * 0.8, h * 0.8),
                                    (w * 0.2, h * 0.8), (w * 0.2 + 3, h * 0.55 + 4)]
        stroke(2.8, id: 23, sq, duration: 1.2, n: 80)                                                     // G29
        tap(4.6, 6, h * 0.45)                                                                             // G30 left
        tap(5.2, w * 0.5, h - 6)                                                                          // G30 bottom
        tap(44.0, w * 0.5, h * 0.9)                                                                       // wakes G32
        return out
    }
}
#endif
