import Foundation

/// Appendix B haptic palette, as data. Each entry is a small Core Haptics pattern the
/// app builds once at launch. Values are starting points to tune on a real iPhone.
public struct HapticRecipe: Codable, Equatable, Sendable {
    public struct Event: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case transient, continuous }
        public var type: Kind
        public var time: Double
        public var intensity: Float
        public var sharpness: Float
        /// Continuous events only.
        public var duration: Double?
    }

    public var events: [Event]
    /// Optional intensity-control curve, as [time, value] pairs (Swell rises, Settle falls).
    public var intensityCurve: [[Double]]?
    /// Held recipes (Texture, Soft rumble, Swell when it follows input) run until
    /// stopped; their single continuous event is long and gets cut off on stop.
    public var held: Bool?
}

/// When a haptic cue plays relative to its gesture.
public enum HapticMoment: String, Codable, Sendable {
    /// On `began` or `fired` (the default).
    case start
    /// On `ended`.
    case end
    /// When the gesture's effect bounces off a screen edge (G8 comet).
    case bounce
}

/// One haptic a gesture plays. Gesture definitions list these as data.
public struct HapticCue: Codable, Equatable, Sendable {
    public var name: HapticName
    public var on: HapticMoment?
    public var delay: Double?
    public var condition: EffectCondition?
    /// Overall strength, 0...1 (multiplies the recipe).
    public var intensity: Float?
    /// For held recipes: live input that drives intensity while the gesture continues.
    public var follow: ScaleRule?
    /// For held recipes: live input that drives sharpness (0...1).
    public var followSharpness: ScaleRule?
    /// Plays a held recipe as a one-shot of this length instead of holding it.
    public var duration: Double?
    /// Repeats at the gesture's tempo (G4 Pulse) for this many seconds.
    public var loopFor: Double?
    /// Plays again every time the gesture's magnitude passes another multiple of this
    /// (G21: once per revolution).
    public var everyMagnitude: Float?

    public init(name: HapticName) { self.name = name }
}
