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
    /// G8: a glowing head that keeps flying with drag, bounces off the screen edges
    /// and sheds a particle tail.
    case comet
    /// G13: an elastic glowing line from the origin (anchor) to the finger. Snaps back
    /// to the origin when released.
    case tether
    /// G13: particles launched from the point toward the origin.
    case launch
    /// G11: particles spiralling into the point (positive magnitude) or out of it
    /// (negative magnitude).
    case vortex
    /// G12: a flickering jagged arc along the stroke path supplied by the canvas.
    case arc
    /// G9: style for the particles that erased ink dissolves into. The canvas emits
    /// them where ink was actually erased.
    case dissolve
    /// G14: an ambient emitter leaving a short light trail wherever it moves.
    case trail
    /// G15: an ink blot. Handled by the canvas as ink, not as an effect.
    case blot
    /// G17: a ribbon of ink between two fingers. Handled by the canvas as ink.
    case ribbon
    /// Glowing lines joining the gesture's touch points (closed for 3 or more). G16, G22.
    case filament
    /// G22 swipe: a wavefront line that sweeps across the whole canvas in the gesture's direction.
    case sweep
    /// G26: faint particles drifting on the segments between the touch points.
    case shimmer
    /// Particles circling the point at about `radius`, at `count` particles. G20, G21.
    case orbitSwarm
    // Ink distortions. They displace the ink layer temporarily, then let it return (spec: Layers).
    /// A ring-shaped water ripple expanding from the point to `radius`.
    case ripple
    /// Twists ink within `radius` around the point; intensity is the angle in radians.
    case twist
    /// Pulls ink within `radius` toward the point; intensity 0...1 is how far.
    case pull
    /// A straight wavefront crossing the canvas in the gesture's direction, nudging ink.
    /// With a radius, it starts at the point and travels only that far (G30).
    case wave
    /// G27: the touched stroke vibrates like a plucked string while glows run both ways
    /// from the touch point. The canvas supplies the stroke's path.
    case pluck
    /// G28: sparks flying off along both strokes' directions at a crossing.
    case crossSparks
    /// G29: the fill of a closed shape. Handled by the canvas as ink.
    case fill
    /// G30: a glowing bar along the touched edge, like a bumper.
    case bumper
    /// G32: faint motes drifting slowly over the canvas, emitted at `count` per second.
    case drift
}

/// Where an effect sits.
public enum EffectAnchor: String, Codable, Sendable {
    /// The gesture's point (default).
    case point
    /// The gesture's origin: the slingshot anchor, the orbit's held finger.
    case origin
    /// One copy at every touch point of a multi-finger gesture.
    case eachTouch
}

/// When an effect spawns.
public enum SpawnMoment: String, Codable, Sendable {
    /// On `began` or `fired` (the default).
    case start
    /// On `ended`, such as the slingshot launch on release.
    case end
}

/// Spawns the effect only when the gesture's magnitude has this sign (G11 inward vs outward).
public enum EffectCondition: String, Codable, Sendable {
    case magnitudePositive, magnitudeNegative
    /// Only for one-shot (`fired`) events: G22 swipe rather than G22 tap.
    case fired
    /// Only for `began` events: G22 tap rather than G22 swipe.
    case began
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
    case magnitude, speed, tempo, size
}

/// Maps an input range linearly onto an output factor range, clamped.
public struct ScaleRule: Codable, Equatable, Sendable {
    public var source: ScaleSource
    public var inMin: Float
    public var inMax: Float
    public var outMin: Float
    public var outMax: Float
    /// Use the absolute value of the input (G11 turns are signed by direction).
    public var absolute: Bool?

    public func factor(for raw: Float) -> Float {
        let value = absolute == true ? abs(raw) : raw
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
    /// Scales the effect's duration (G27: stroke length sets ring time).
    public var durationScale: ScaleRule?
    public var trail: TrailRule?
    /// Spawning replaces any live effect from the same gesture and slot (G4: tapping
    /// elsewhere moves the pulse). Ambient effects are always keyed.
    public var replaces: Bool?
    /// Keyed effects are per touch by default; false makes one per gesture.
    public var perTouch: Bool?
    public var spawnOn: SpawnMoment?
    public var condition: EffectCondition?
    public var at: EffectAnchor?
    /// Share a key with another spec of the same gesture, so one can replace the
    /// other (G24: the spread replaces the gathered orb).
    public var keySlot: Int?

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
    public var magnitude: Float
    /// The gesture's size (G27: distance along the stroke).
    public var size: Float
    public var originX: Float
    public var originY: Float
    /// The gesture's touch points (x0, y0, x1, y1, ...), for multi-finger effects.
    public var points: [Float]
    /// Draw one copy at every point in `points`.
    public var atEachPoint: Bool
}

public enum EffectCommand: Equatable, Sendable {
    case spawn(EffectSpawn)
    case update(key: UInt64, x: Float, y: Float, radius: Float, intensity: Float)
    /// The ambient trigger ended: fade out over `Persistence.ambientReleaseFade`.
    case release(key: UInt64)
    /// New touch points for a keyed multi-finger effect (G26 shimmer).
    case updatePoints(key: UInt64, points: [Float])
}

public struct HapticCommand: Equatable, Sendable {
    public var name: HapticName
    public var phase: HapticPhase
    /// 0...1 strength (Core Haptics intensity control).
    public var intensity: Float
    /// 0...1 sharpness for held recipes that follow input; nil keeps the recipe's own.
    public var sharpness: Float?
    /// Ties start, update and stop of one held haptic together.
    public var key: UInt64
    /// Seconds from now.
    public var delay: Double
    /// Play a held recipe for this long only.
    public var duration: Double?
    /// Repeat every `loopPeriod` seconds for `loopFor` seconds (G4).
    public var loopPeriod: Double?
    public var loopFor: Double?

    public init(name: HapticName, phase: HapticPhase, intensity: Float, sharpness: Float? = nil, key: UInt64,
                delay: Double = 0, duration: Double? = nil, loopPeriod: Double? = nil, loopFor: Double? = nil) {
        self.name = name; self.phase = phase; self.intensity = intensity; self.sharpness = sharpness
        self.key = key; self.delay = delay; self.duration = duration
        self.loopPeriod = loopPeriod; self.loopFor = loopFor
    }
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
