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
        guard ProcessInfo.processInfo.arguments.contains("-demo") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let (w, h) = size()
            for s in script(w: w, h: h) {
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
}
#endif
