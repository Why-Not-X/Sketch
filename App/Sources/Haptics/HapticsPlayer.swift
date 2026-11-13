import CoreHaptics
import Foundation
import os
import ResponseMapping

/// Executes haptic commands with Core Haptics (spec: Haptics and iPad).
///
/// - Exists only where `supportsHaptics` is true, checked at runtime, never by model.
///   iPads have no Taptic Engine and get stronger visuals instead (R5).
/// - The engine starts at launch, stays running, and restarts if the system stops it.
/// - Every palette entry is built once into a small pool of reusable players, so the
///   first haptic is as fast as the hundredth.
/// - All Core Haptics calls run on a private serial queue, off the frame loop.
final class HapticsPlayer {
    private static let poolSize = 4

    private let queue = DispatchQueue(label: "TouchWhiteboard.haptics", qos: .userInteractive)
    private let palette: [String: HapticRecipe]
    private let engine: CHHapticEngine
    private var pools: [String: [CHHapticAdvancedPatternPlayer]] = [:]
    private var next: [String: Int] = [:]
    /// Held haptics currently playing, by command key.
    private var held: [UInt64: CHHapticAdvancedPatternPlayer] = [:]
    private let log = Logger(subsystem: "TouchWhiteboard", category: "haptics")

    /// Returns nil on hardware without haptics (iPad, Simulator).
    init?(palette: [String: HapticRecipe]) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = try? CHHapticEngine() else { return nil }
        self.palette = palette
        self.engine = engine
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = false
        engine.stoppedHandler = { [weak self] reason in
            self?.log.notice("haptic engine stopped: \(reason.rawValue, privacy: .public); restarting")
            self?.queue.async { self?.restart() }
        }
        engine.resetHandler = { [weak self] in
            self?.queue.async { self?.restart() }
        }
        queue.async { self.restart() }
    }

    func handle(_ c: HapticCommand) {
        queue.async { self.run(c) }
    }

    // MARK: Engine

    /// Starts the engine and (re)builds every player. Players die with a reset.
    private func restart() {
        do {
            try engine.start()
        } catch {
            log.error("haptic engine failed to start: \(error.localizedDescription, privacy: .public)")
            return
        }
        held.removeAll()
        pools.removeAll()
        for (name, recipe) in palette {
            guard let pattern = try? Self.pattern(recipe) else {
                log.error("bad haptic recipe \(name, privacy: .public)")
                continue
            }
            pools[name] = (0..<Self.poolSize).compactMap { _ in try? engine.makeAdvancedPlayer(with: pattern) }
        }
    }

    private static func pattern(_ r: HapticRecipe) throws -> CHHapticPattern {
        let events = r.events.map { e -> CHHapticEvent in
            let params = [CHHapticEventParameter(parameterID: .hapticIntensity, value: e.intensity),
                          CHHapticEventParameter(parameterID: .hapticSharpness, value: e.sharpness)]
            switch e.type {
            case .transient:
                return CHHapticEvent(eventType: .hapticTransient, parameters: params, relativeTime: e.time)
            case .continuous:
                return CHHapticEvent(eventType: .hapticContinuous, parameters: params,
                                     relativeTime: e.time, duration: e.duration ?? 0.3)
            }
        }
        var curves: [CHHapticParameterCurve] = []
        if let points = r.intensityCurve, points.count >= 2 {
            curves.append(CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: points.map { CHHapticParameterCurve.ControlPoint(relativeTime: $0[0], value: Float($0[1])) },
                relativeTime: 0))
        }
        return try CHHapticPattern(events: events, parameterCurves: curves)
    }

    // MARK: Commands

    private func run(_ c: HapticCommand) {
        let name = c.name.rawValue
        let at = c.delay > 0 ? engine.currentTime + c.delay : CHHapticTimeImmediate
        do {
            switch c.phase {
            case .play:
                guard let p = nextPlayer(name) else { return }
                try p.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                                               value: c.intensity, relativeTime: 0)], atTime: at)
                if let period = c.loopPeriod, let span = c.loopFor {
                    p.loopEnabled = true
                    p.loopEnd = period
                    try p.start(atTime: at)
                    try p.stop(atTime: (at == CHHapticTimeImmediate ? engine.currentTime : at) + span)
                } else {
                    p.loopEnabled = false
                    try p.start(atTime: at)
                    if let d = c.duration {
                        try p.stop(atTime: (at == CHHapticTimeImmediate ? engine.currentTime : at) + d)
                    }
                }
            case .start:
                guard let p = nextPlayer(name) else { return }
                p.loopEnabled = false
                try p.sendParameters(parameters(c), atTime: at)
                try p.start(atTime: at)
                held[c.key] = p
            case .update:
                try held[c.key]?.sendParameters(parameters(c), atTime: CHHapticTimeImmediate)
            case .stop:
                try held.removeValue(forKey: c.key)?.stop(atTime: CHHapticTimeImmediate)
            }
        } catch {
            log.error("haptic \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func parameters(_ c: HapticCommand) -> [CHHapticDynamicParameter] {
        var p = [CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: c.intensity, relativeTime: 0)]
        if let sharp = c.sharpness, let base = palette[c.name.rawValue]?.events.first?.sharpness {
            // Sharpness control is an offset from the recipe's own sharpness.
            p.append(CHHapticDynamicParameter(parameterID: .hapticSharpnessControl,
                                              value: max(-1, min(1, sharp - base)), relativeTime: 0))
        }
        return p
    }

    /// Round-robin through the pool, skipping players held by a running haptic.
    private func nextPlayer(_ name: String) -> CHHapticAdvancedPatternPlayer? {
        guard let pool = pools[name], !pool.isEmpty else { return nil }
        let busy = Set(held.values.map(ObjectIdentifier.init))
        var k = next[name] ?? 0
        for _ in 0..<pool.count {
            let p = pool[k % pool.count]
            k += 1
            if !busy.contains(ObjectIdentifier(p)) { next[name] = k; return p }
        }
        next[name] = k
        return pool[k % pool.count]
    }
}
