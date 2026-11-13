import Foundation
import QuartzCore
import os

/// M8 performance measurement. Records, per frame:
/// - CPU time spent on the frame (touch processing, effects, tessellation, encoding),
/// - the interval between presented frames, and whether a frame was dropped
///   (an interval longer than 1.5× the target frame time),
/// - frames skipped because the GPU was still busy,
/// - live particles and effects.
///
/// Each frame is also an os_signpost interval "Frame" (subsystem TouchWhiteboard,
/// Points of Interest), so Instruments can line it up with GPU activity.
/// Reports every 5 s to the log (category "perf"). Simulator numbers are not device
/// numbers.
final class PerfMonitor {
    struct Snapshot {
        var frames = 0
        var dropped = 0
        var skipped = 0
        var cpuP50: Double = 0, cpuP95: Double = 0, cpuMax: Double = 0
        var intervalP50: Double = 0, intervalP95: Double = 0, intervalMax: Double = 0
        var peakParticles = 0
        var peakEffects = 0
    }

    private let signposter = OSSignposter(subsystem: "TouchWhiteboard", category: .pointsOfInterest)
    private let log = Logger(subsystem: "TouchWhiteboard", category: "perf")
    private var frameState: OSSignpostIntervalState?
    private var frameStart: Double = 0

    private var cpu = SampleRing(capacity: 1200)
    private var intervals = SampleRing(capacity: 1200)
    private var lastPresented: Double = 0
    /// Target frame time in seconds (1/120 or 1/60), from the display link.
    var targetFrameTime: Double = 1.0 / 120

    private(set) var window = Snapshot()
    private var windowStart: Double = 0
    /// Totals since the last `reset()` (the stress test reads these).
    private(set) var total = Snapshot()

    func frameBegan(at t: Double) {
        frameStart = t
        frameState = signposter.beginInterval("Frame", id: signposter.makeSignpostID())
    }

    func frameEnded(particles: Int, effects: Int, skippedTotal: Int) {
        if let s = frameState { signposter.endInterval("Frame", s) }
        frameState = nil
        let ms = (CACurrentMediaTime() - frameStart) * 1000
        cpu.add(ms)
        record(&window, ms: ms, particles: particles, effects: effects)
        record(&total, ms: ms, particles: particles, effects: effects)
        lastSkipped = skippedTotal
        window.skipped = skippedTotal - windowSkippedBase
        total.skipped = skippedTotal - totalSkippedBase
    }

    private var lastSkipped = 0, windowSkippedBase = 0, totalSkippedBase = 0

    private func record(_ s: inout Snapshot, ms: Double, particles: Int, effects: Int) {
        s.frames += 1
        s.cpuMax = max(s.cpuMax, ms)
        s.peakParticles = max(s.peakParticles, particles)
        s.peakEffects = max(s.peakEffects, effects)
    }

    /// From the presented handler (main thread).
    func presented(at t: Double) {
        guard t > 0 else { return }
        if lastPresented > 0 {
            let dt = t - lastPresented
            // Ignore long gaps (idle throttling, app in background): they are not drops.
            if dt < 0.25 {
                intervals.add(dt * 1000)
                window.intervalMax = max(window.intervalMax, dt * 1000)
                total.intervalMax = max(total.intervalMax, dt * 1000)
                if dt > targetFrameTime * 1.5 { window.dropped += 1; total.dropped += 1 }
            }
        }
        lastPresented = t
        if windowStart == 0 { windowStart = t }
        if t - windowStart >= 5 {
            report()
            windowStart = t
        }
    }

    func reset() {
        total = Snapshot()
        window = Snapshot()
        totalSkippedBase = lastSkipped
        windowSkippedBase = lastSkipped
        cpu = SampleRing(capacity: 1200)
        intervals = SampleRing(capacity: 1200)
    }

    /// Percentiles over the recent rings (up to the last 1200 frames).
    func summary(_ s: Snapshot) -> String {
        String(format: "frames %d  dropped %d  skipped %d  cpu p50 %.2f p95 %.2f max %.2f ms  interval p50 %.2f p95 %.2f max %.2f ms  peak particles %d  peak effects %d",
               s.frames, s.dropped, s.skipped, cpu.percentile(0.5), cpu.percentile(0.95), s.cpuMax,
               intervals.percentile(0.5), intervals.percentile(0.95), s.intervalMax, s.peakParticles, s.peakEffects)
    }

    var hudLine: String {
        String(format: "cpu p95 %.1f ms  dropped %d/%d  particles %d", cpu.percentile(0.95), window.dropped,
               window.frames, window.peakParticles)
    }

    private func report() {
        #if targetEnvironment(simulator)
        let prefix = "SIMULATOR (not a device measurement) "
        #else
        let prefix = ""
        #endif
        log.notice("\(prefix, privacy: .public)\(self.summary(self.window), privacy: .public)")
        window = Snapshot()
        windowSkippedBase = lastSkipped
    }
}
