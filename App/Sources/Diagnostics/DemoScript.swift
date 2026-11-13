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
        let m3 = args.contains("-demo3")
        guard args.contains("-demo") || m3 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let (w, h) = size()
            for s in (m3 ? scriptM3(w: w, h: h) : script(w: w, h: h)) {
                DispatchQueue.main.asyncAfter(deadline: .now() + s.at) {
                    input.inject(TouchEvent(touchID: s.id, phase: s.phase, kind: .finger,
                                            timestamp: CACurrentMediaTime(), x: s.x, y: s.y, majorRadius: 12))
                }
            }
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
}
#endif
