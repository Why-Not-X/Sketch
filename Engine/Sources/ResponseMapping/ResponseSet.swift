import Foundation
import GestureEngine

/// Appendix B haptic palette names. Recipes are data and arrive with M6.
public enum HapticName: String, Codable, CaseIterable, Sendable {
    case tick = "Tick", thud = "Thud", snap = "Snap", softRumble = "Soft rumble"
    case swell = "Swell", pulse = "Pulse", texture = "Texture", burst = "Burst"
    case crackle = "Crackle", settle = "Settle", none = "None"
}

/// Appendix B persistence presets, implemented once in `Lifetime`.
public enum Persistence: String, Codable, CaseIterable, Sendable {
    case instant = "Instant", short = "Short", medium = "Medium", long = "Long"
    case ink = "Ink", ambient = "Ambient"

    /// Fade duration in seconds. Nil means the effect lasts until cleared (Ink) or
    /// while its trigger holds (Ambient, which then fades over `ambientReleaseFade`).
    public var fadeDuration: Double? {
        switch self {
        case .instant: return 0.25
        case .short: return 1
        case .medium: return 4
        case .long: return 12
        case .ink, .ambient: return nil
        }
    }

    public static let ambientReleaseFade: Double = 1
}

public struct RGBA: Codable, Equatable, Sendable {
    public var r: Float, g: Float, b: Float, a: Float
    public init(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public init(from decoder: Decoder) throws {
        // Stored in JSON as [r, g, b] or [r, g, b, a].
        var c = try decoder.unkeyedContainer()
        r = try c.decode(Float.self); g = try c.decode(Float.self); b = try c.decode(Float.self)
        a = c.isAtEnd ? 1 : try c.decode(Float.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(r); try c.encode(g); try c.encode(b); try c.encode(a)
    }
}

/// Colors and effect styles. V2 swaps these; effect code must read them from here.
public struct Theme: Codable, Equatable, Sendable {
    public var background: RGBA
    public var ink: RGBA
    public var glow: RGBA
    public var sparkle: RGBA
    /// Brightness of the halo around ink, 0...1.
    public var glowStrength: Float
    /// Head sparkle size in points and how far it lags behind the finger (0 = none, 1 = frozen).
    public var sparkleSize: Float
    public var sparkleLag: Float

    public func color(_ role: ColorRole) -> RGBA {
        switch role {
        case .ink: return ink
        case .glow: return glow
        case .sparkle: return sparkle
        }
    }
}

/// What one gesture does. Field names follow the Appendix A columns; `effects` is the
/// renderable part.
public struct ResponseDefinition: Codable, Equatable, Sendable {
    public var visual: String
    public var haptics: [HapticName]
    public var persistence: Persistence
    public var inherits: String
    public var effects: [EffectSpec]
    /// What actually plays: when, how strong, and what live input drives it.
    public var hapticCues: [HapticCue]
}

/// A swappable bundle of reactions. Swapping it changes every reaction without
/// touching engine code (R9).
public struct ResponseSet: Codable, Equatable, Sendable {
    public var name: String
    public var theme: Theme
    /// R5: on hardware without haptics, each reaction's peak is scaled by this.
    public var visualBoostWhenNoHaptics: Float
    /// Keyed by gesture ID raw value ("G1"...), so the JSON stays readable.
    public var responses: [String: ResponseDefinition]
    /// Appendix B palette, keyed by haptic name ("Tick"...).
    public var hapticPalette: [String: HapticRecipe]

    public func recipe(_ name: HapticName) -> HapticRecipe? { hapticPalette[name.rawValue] }

    public func response(for id: GestureID) -> ResponseDefinition? { responses[id.rawValue] }

    public static func load(from data: Data) throws -> ResponseSet {
        try JSONDecoder().decode(ResponseSet.self, from: data)
    }

    /// The v1 base look (D3), loaded from the bundled BaseResponseSet.json.
    public static let base: ResponseSet = {
        guard let url = Bundle.module.url(forResource: "BaseResponseSet", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("BaseResponseSet.json is missing from the ResponseMapping bundle")
        }
        do { return try load(from: data) } catch {
            fatalError("BaseResponseSet.json is invalid: \(error)")
        }
    }()
}
