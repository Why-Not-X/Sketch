import Foundation
import QuartzCore
import os

/// Measures touch-to-presented latency (spec: Touch input and latency).
///
/// - Touch-down: from `UITouch.timestamp` in `touchesBegan` to the moment the first
///   frame carrying that touch is presented (`addPresentedHandler`). Each one is
///   also an os_signpost interval "TouchToPresent", visible in Instruments.
/// - Move: from the newest real (non-predicted) touch sample in a frame to that
///   frame's presentation.
///
/// Both clocks share the host-time base, so the difference is a real latency.
/// Numbers only mean something on a real device; the Simulator's present timing
/// is not representative.
final class LatencyMonitor {
    struct PendingDown {
        let timestamp: Double
        let state: OSSignpostIntervalState
    }

    var onReport: ((String) -> Void)?
    /// Extra debug line shown under the latency numbers.
    var note = ""

    private let signposter = OSSignposter(subsystem: "TouchWhiteboard", category: .pointsOfInterest)
    private let log = Logger(subsystem: "TouchWhiteboard", category: "latency")
    private var pending: [PendingDown] = []
    private var downSamples = SampleRing(capacity: 256)
    private var moveSamples = SampleRing(capacity: 512)
    private var frameIntervals = SampleRing(capacity: 240)
    private var lastPresent: Double = 0
    private var lastReport: Double = 0
    private var lastLog: Double = 0
    private var unpresented = 0

    init() { pending.reserveCapacity(16) }

    /// Called from touchesBegan.
    func touchDown(at timestamp: Double) {
        let state = signposter.beginInterval("TouchToPresent", id: signposter.makeSignpostID())
        pending.append(PendingDown(timestamp: timestamp, state: state))
    }

    /// Called once per frame, after the frame has consumed all queued touches.
    func takePendingDowns() -> [PendingDown] {
        guard !pending.isEmpty else { return [] }
        let out = pending
        pending.removeAll(keepingCapacity: true)
        return out
    }

    /// Called from the drawable's presented handler (any thread).
    func framePresented(at presentedTime: Double, downs: [PendingDown], newestMove: Double) {
        for d in downs { signposter.endInterval("TouchToPresent", d.state) }
        DispatchQueue.main.async { [self] in
            guard presentedTime > 0 else { unpresented += 1; return }
            // Skip non-causal samples (synthetic replays carry future timestamps).
            for d in downs where presentedTime >= d.timestamp { downSamples.add((presentedTime - d.timestamp) * 1000) }
            if newestMove > 0, presentedTime >= newestMove { moveSamples.add((presentedTime - newestMove) * 1000) }
            if lastPresent > 0 { frameIntervals.add((presentedTime - lastPresent) * 1000) }
            lastPresent = presentedTime
            report(now: presentedTime)
        }
    }

    private func report(now: Double) {
        guard now - lastReport > 0.25 else { return }
        lastReport = now
        let interval = frameIntervals.percentile(0.5)
        let hz = interval > 0 ? 1000 / interval : 0
        #if targetEnvironment(simulator)
        let prefix = "SIMULATOR (approximate, not a device measurement)\n"
        #else
        let prefix = ""
        #endif
        let text = prefix + String(
            format: "%.0f Hz  (frame p50 %.2f ms, p95 %.2f ms)\ndown→screen  p50 %.1f  p95 %.1f  max %.1f ms  n=%d\nmove→screen  p50 %.1f  p95 %.1f ms  n=%d",
            hz, interval, frameIntervals.percentile(0.95),
            downSamples.percentile(0.5), downSamples.percentile(0.95), downSamples.max, downSamples.count,
            moveSamples.percentile(0.5), moveSamples.percentile(0.95), moveSamples.count)
        onReport?(note.isEmpty ? text : text + "\n" + note)
        if now - lastLog > 5, downSamples.count + moveSamples.count > 0 {
            lastLog = now
            log.notice("\(text, privacy: .public)")
        }
    }
}

/// Fixed-size ring of samples with percentile readout.
struct SampleRing {
    private var values: [Double]
    private var next = 0
    private(set) var count = 0

    init(capacity: Int) { values = [Double](repeating: 0, count: capacity) }

    mutating func add(_ v: Double) {
        values[next] = v
        next = (next + 1) % values.count
        count = min(count + 1, values.count)
    }

    var max: Double { count == 0 ? 0 : values.prefix(count).max() ?? 0 }

    func percentile(_ p: Double) -> Double {
        guard count > 0 else { return 0 }
        let sorted = values.prefix(count).sorted()
        return sorted[min(count - 1, Int(Double(count - 1) * p + 0.5))]
    }
}
