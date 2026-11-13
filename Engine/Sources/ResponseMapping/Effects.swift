import Foundation

/// Visual building blocks a response is made of. Response sets combine these as
/// data; the renderer knows how to draw each kind.
public enum EffectKind: String, Codable, CaseIterable, Sendable {
    /// Expanding ring.
    case ring
    /// Ring with a fast-then-slow expansion and a thicker edge.
    case shockwave
    /// Ring that repeats at the gesture's tempo, each pulse dimmer.
    case pulse
    /// Small bright point.
    case dot
    /// Brief soft disc of light.
    case flash
    /// Soft glow that blooms outward.
    case halo
    /// Ambient glowing orb that breathes; radius follows updates.
    case orb
    /// Particles flung outward with drag.
    case burst
    /// Ambient particles drifting inward toward the point, emitted at `count` per second.
    case motesInward
}

public enum Easing: String, Codable, Sendable {
    case linear, easeOut, fastThenSlow

    public func apply(_ x: Float) -> Float {
        let c = min(1, max(0, x))
        switch self {
        case .linear: return c
        case .easeOut: return 1 - (1 - c) * (1 - c) * (1 - c)
        case .fastThenSlow: return c >= 1 ? 1 : 1 - pow2(-8 * c)
        }
    }

    private func pow2(_ x: Float) -> Float { Float(exp2(Double(x))) }
}

public enum ColorRole: String, Codable, Sendable {
    case ink, glow, sparkle
}

/// Which gesture parameter drives a scale factor.
public enum ScaleSource: String, Codable, Sendable {
    case magnitude, speed, tempo
}

/// Maps an input range linearly onto an output factor range, clamped.
public struct ScaleRule: Codable, Equatable, Sendable {
    public var source: ScaleSource
    public var inMin: Float
    public var inMax: Float
    public var outMin: Float
    public var outMax: Float

    public func factor(for value: Float) -> Float {
        guard inMax != inMin else { return outMax }
        let k = min(1, max(0, (value - inMin) / (inMax - inMin)))
        return outMin + (outMax - outMin) * k
    }
}

/// Fast lifts leave a trail: copies of the effect stepped back along the motion.
public struct TrailRule: Codable, Equatable, Sendable {
    public var count: Int
    public var minSpeed: Float
    /// Trail length = speed × this, in seconds of travel.
    public var secondsOfTravel: Float
}

/// One effect inside a response definition. Optional fields fall back to defaults in
/// the mapper, so a JSON entry only lists what it changes.
public struct EffectSpec: Codable, Equatable, Sendable {
    public var kind: EffectKind
    /// Final radius in points (burst: travel distance).
    public var radius: Float
    public var startRadius: Float?
    /// Total life in seconds. Nil uses the persistence preset's fade time.
    public var duration: Double?
    public var delay: Double?
    /// Ring edge width in points.
    public var thickness: Float?
    public var intensity: Float?
    /// Particle count (burst) or particles per second (motesInward).
    public var count: Int?
    public var color: ColorRole?
    public var easing: Easing?
    /// Overrides the response's persistence for this effect.
    public var persistence: Persistence?
    public var radiusScale: ScaleRule?
    public var intensityScale: ScaleRule?
    public var trail: TrailRule?
    /// Spawning replaces any live effect from the same gesture and slot (G4: tapping
    /// elsewhere moves the pulse). Ambient effects are always keyed.
    public var replaces: Bool?
    /// Keyed effects are per touch by default; false makes one per gesture.
    public var perTouch: Bool?

    public init(kind: EffectKind, radius: Float) {
        self.kind = kind
        self.radius = radius
    }
}

// MARK: - Commands emitted by the mapper

public struct EffectSpawn: Equatable, Sendable {
    /// Nonzero for effects that can later be updated, released or replaced.
    public var key: UInt64
    public var kind: EffectKind
    public var x: Float
    public var y: Float
    public var radius: Float
    public var startRadius: Float
    /// Total life in seconds; nil while an ambient effect is held.
    public var duration: Double?
    public var delay: Double
    public var thickness: Float
    public var intensity: Float
    public var count: Int
    public var color: ColorRole
    public var easing: Easing
    public var persistence: Persistence
    public var tempo: Float
    public var directionX: Float
    public var directionY: Float
    public var speed: Float
}

public enum EffectCommand: Equatable, Sendable {
    case spawn(EffectSpawn)
    case update(key: UInt64, x: Float, y: Float, radius: Float, intensity: Float)
    /// The ambient trigger ended: fade out over `Persistence.ambientReleaseFade`.
    case release(key: UInt64)
}

public struct HapticCommand: Equatable, Sendable {
    public var name: HapticName
    public var phase: HapticPhase
    /// 0...1, from live input where the palette entry is continuous.
    public var intensity: Float
    public var key: UInt64
}

public enum HapticPhase: Sendable, Equatable {
    case play, start, update, stop
}

/// Shared lifetime rule for every effect (spec: implement persistence presets once).
public enum Lifetime {
    /// Opacity multiplier for an effect `age` seconds old.
    /// - Parameters:
    ///   - life: total life, or nil for effects that last while held (Ambient) or until cleared (Ink).
    ///   - releasedAt: age at which an ambient effect's trigger ended.
    public static func opacity(age: Double, life: Double?, releasedAt: Double? = nil) -> Float {
        if age < 0 { return 0 }
        var a: Float = 1
        if let life {
            let k = age / life
            if k >= 1 { return 0 }
            a = Float(pow(1 - k, 1.3))
        }
        if let r = releasedAt {
            let k = (age - r) / Persistence.ambientReleaseFade
            if k >= 1 { return 0 }
            a *= Float(max(0, 1 - k))
        }
        return a
    }

    public static func isAlive(age: Double, life: Double?, releasedAt: Double? = nil) -> Bool {
        if let life, age >= life { return false }
        if let r = releasedAt, age - r >= Persistence.ambientReleaseFade { return false }
        return true
    }
}
