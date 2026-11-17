import Foundation

/// A theme: colors, glow, ink texture, particle sprites and effect styles (v2, R9).
/// Themes are data (`theme-*.json` in this bundle). Any field a theme file leaves out
/// falls back to the v1 base look, so a theme only lists what it changes.
public struct Theme: Codable, Equatable, Sendable {
    /// How strokes take their color from the palette.
    public enum InkMode: String, Codable, Sendable {
        /// Every stroke in `palette[0]`.
        case single
        /// Each stroke takes the next palette color (by stroke ID, so it never changes).
        case perStroke
        /// Color flows through the palette along each stroke's length.
        case alongStroke
    }

    public enum InkTexture: String, Codable, Sendable {
        case smooth
        /// Grainy, slightly broken edges, like chalk.
        case chalk
    }

    public enum Sprite: String, Codable, Sendable {
        case soft, star, dust, graphite
    }

    /// How effects and particles combine with the canvas.
    public enum Blend: String, Codable, Sendable {
        /// Effects add light (dark themes).
        case add
        /// Effects paint over the canvas, so dark effects show on light themes.
        case over
    }

    /// Echo settings (Neon Echoes). Count 0 turns a part off.
    public struct Echo: Codable, Equatable, Sendable {
        /// Copies of every ring, halo, shockwave and flash.
        public var count: Int
        /// Seconds between copies.
        public var delay: Double
        /// Each copy is this much larger (0.25 = 25% per copy).
        public var growth: Float
        /// Each copy keeps this fraction of the previous one's brightness.
        public var fade: Float
        /// Offset copies a finished stroke sends outward on each side.
        public var strokeCopies: Int
        /// How far (points) the stroke copies travel before fading.
        public var strokeTravel: Float
        public var strokeDuration: Double

        public init(count: Int, delay: Double, growth: Float, fade: Float,
                    strokeCopies: Int, strokeTravel: Float, strokeDuration: Double) {
            self.count = count; self.delay = delay; self.growth = growth; self.fade = fade
            self.strokeCopies = strokeCopies; self.strokeTravel = strokeTravel; self.strokeDuration = strokeDuration
        }
    }

    public var id: String
    public var name: String
    /// Position in the theme picker.
    public var order: Int

    // Canvas
    public var background: RGBA
    /// Color toward the edges when `vignette` > 0.
    public var backgroundEdge: RGBA
    public var vignette: Float

    // Ink
    public var palette: [RGBA]
    public var inkMode: InkMode
    public var glow: RGBA
    /// Glow takes each stroke's own color instead of `glow`.
    public var glowFromInk: Bool
    /// Brightness of the halo around ink, 0...1.
    public var glowStrength: Float
    /// How fast the halo falls off (2 = v1; higher is tighter).
    public var glowFalloff: Float
    /// Scales the solid core of the line (1 = v1).
    public var coreScale: Float
    public var texture: InkTexture

    // Effects
    public var sparkle: RGBA
    /// Head sparkle size in points and how far it lags behind the finger (0 = none, 1 = frozen).
    public var sparkleSize: Float
    public var sparkleLag: Float
    /// Effects take palette colors (rotating) instead of the single glow/sparkle colors.
    public var effectPalette: Bool
    public var sprite: Sprite
    public var blend: Blend
    /// Particles fall (points per second squared); chalk dust drifts down.
    public var particleGravity: Float
    public var echo: Echo?

    /// First palette color: the v1 "ink" color.
    public var ink: RGBA { palette.first ?? RGBA(1, 1, 1) }

    public init(id: String, name: String, order: Int, background: RGBA, backgroundEdge: RGBA, vignette: Float,
                palette: [RGBA], inkMode: InkMode, glow: RGBA, glowFromInk: Bool, glowStrength: Float,
                glowFalloff: Float, coreScale: Float, texture: InkTexture, sparkle: RGBA, sparkleSize: Float,
                sparkleLag: Float, effectPalette: Bool, sprite: Sprite, blend: Blend, particleGravity: Float,
                echo: Echo?) {
        self.id = id; self.name = name; self.order = order
        self.background = background; self.backgroundEdge = backgroundEdge; self.vignette = vignette
        self.palette = palette.isEmpty ? [RGBA(1, 0.95, 0.86)] : Array(palette.prefix(4))
        self.inkMode = inkMode; self.glow = glow; self.glowFromInk = glowFromInk
        self.glowStrength = glowStrength; self.glowFalloff = glowFalloff; self.coreScale = coreScale
        self.texture = texture; self.sparkle = sparkle; self.sparkleSize = sparkleSize; self.sparkleLag = sparkleLag
        self.effectPalette = effectPalette; self.sprite = sprite; self.blend = blend
        self.particleGravity = particleGravity; self.echo = echo
    }

    /// The v1 base look (D3). Every field a theme file omits comes from here.
    public static let base = Theme(
        id: "base", name: "Base", order: 0,
        background: RGBA(0.043, 0.043, 0.051), backgroundEdge: RGBA(0.043, 0.043, 0.051), vignette: 0,
        palette: [RGBA(1.0, 0.95, 0.86)], inkMode: .single,
        glow: RGBA(1.0, 0.80, 0.58), glowFromInk: false, glowStrength: 0.38, glowFalloff: 2, coreScale: 1,
        texture: .smooth,
        sparkle: RGBA(1.0, 0.97, 0.90), sparkleSize: 22, sparkleLag: 0.45,
        effectPalette: false, sprite: .soft, blend: .add, particleGravity: 0, echo: nil)

    /// Color for an effect role. With `effectPalette`, glow and sparkle roles rotate
    /// through the palette by `variant`.
    public func color(_ role: ColorRole, variant: Int = 0) -> RGBA {
        switch role {
        case .ink: return ink
        case .glow: return effectPalette ? palette[abs(variant) % palette.count] : glow
        case .sparkle: return effectPalette ? palette[abs(variant + 1) % palette.count] : sparkle
        }
    }

    /// Relative luminance of the background (0 dark ... 1 light), for chrome contrast.
    public var backgroundLuminance: Float {
        0.2126 * background.r + 0.7152 * background.g + 0.0722 * background.b
    }
}

extension Theme {
    enum CodingKeys: String, CodingKey {
        case id, name, order, background, backgroundEdge, vignette, palette, ink, inkMode, glow, glowFromInk
        case glowStrength, glowFalloff, coreScale, texture, sparkle, sparkleSize, sparkleLag, effectPalette
        case sprite, blend, particleGravity, echo
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let b = Theme.base
        var palette = try c.decodeIfPresent([RGBA].self, forKey: .palette)
        if palette == nil, let ink = try c.decodeIfPresent(RGBA.self, forKey: .ink) { palette = [ink] }  // v1 files
        let background = try c.decodeIfPresent(RGBA.self, forKey: .background) ?? b.background
        self.init(
            id: try c.decodeIfPresent(String.self, forKey: .id) ?? b.id,
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? b.name,
            order: try c.decodeIfPresent(Int.self, forKey: .order) ?? b.order,
            background: background,
            backgroundEdge: try c.decodeIfPresent(RGBA.self, forKey: .backgroundEdge) ?? background,
            vignette: try c.decodeIfPresent(Float.self, forKey: .vignette) ?? b.vignette,
            palette: palette ?? b.palette,
            inkMode: try c.decodeIfPresent(InkMode.self, forKey: .inkMode) ?? b.inkMode,
            glow: try c.decodeIfPresent(RGBA.self, forKey: .glow) ?? b.glow,
            glowFromInk: try c.decodeIfPresent(Bool.self, forKey: .glowFromInk) ?? b.glowFromInk,
            glowStrength: try c.decodeIfPresent(Float.self, forKey: .glowStrength) ?? b.glowStrength,
            glowFalloff: try c.decodeIfPresent(Float.self, forKey: .glowFalloff) ?? b.glowFalloff,
            coreScale: try c.decodeIfPresent(Float.self, forKey: .coreScale) ?? b.coreScale,
            texture: try c.decodeIfPresent(InkTexture.self, forKey: .texture) ?? b.texture,
            sparkle: try c.decodeIfPresent(RGBA.self, forKey: .sparkle) ?? b.sparkle,
            sparkleSize: try c.decodeIfPresent(Float.self, forKey: .sparkleSize) ?? b.sparkleSize,
            sparkleLag: try c.decodeIfPresent(Float.self, forKey: .sparkleLag) ?? b.sparkleLag,
            effectPalette: try c.decodeIfPresent(Bool.self, forKey: .effectPalette) ?? b.effectPalette,
            sprite: try c.decodeIfPresent(Sprite.self, forKey: .sprite) ?? b.sprite,
            blend: try c.decodeIfPresent(Blend.self, forKey: .blend) ?? b.blend,
            particleGravity: try c.decodeIfPresent(Float.self, forKey: .particleGravity) ?? b.particleGravity,
            echo: try c.decodeIfPresent(Echo.self, forKey: .echo) ?? b.echo)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(order, forKey: .order)
        try c.encode(background, forKey: .background); try c.encode(backgroundEdge, forKey: .backgroundEdge)
        try c.encode(vignette, forKey: .vignette); try c.encode(palette, forKey: .palette)
        try c.encode(inkMode, forKey: .inkMode); try c.encode(glow, forKey: .glow)
        try c.encode(glowFromInk, forKey: .glowFromInk); try c.encode(glowStrength, forKey: .glowStrength)
        try c.encode(glowFalloff, forKey: .glowFalloff); try c.encode(coreScale, forKey: .coreScale)
        try c.encode(texture, forKey: .texture); try c.encode(sparkle, forKey: .sparkle)
        try c.encode(sparkleSize, forKey: .sparkleSize); try c.encode(sparkleLag, forKey: .sparkleLag)
        try c.encode(effectPalette, forKey: .effectPalette); try c.encode(sprite, forKey: .sprite)
        try c.encode(blend, forKey: .blend); try c.encode(particleGravity, forKey: .particleGravity)
        try c.encodeIfPresent(echo, forKey: .echo)
    }
}

/// Every bundled theme (`theme-*.json`), in picker order. Base is always first; a
/// theme file that fails to load is skipped (and reported), never fatal.
public enum ThemeLibrary {
    public static let all: [Theme] = {
        var themes: [Theme] = [.base]
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        for url in urls where url.lastPathComponent.hasPrefix("theme-") {
            do {
                let t = try JSONDecoder().decode(Theme.self, from: Data(contentsOf: url))
                if t.id != "base" { themes.append(t) }
            } catch {
                loadErrors.append("\(url.lastPathComponent): \(error)")
            }
        }
        return themes.sorted { ($0.order, $0.id) < ($1.order, $1.id) }
    }()

    /// Files that failed to decode, for tests and the debug log.
    public nonisolated(unsafe) static var loadErrors: [String] = []

    public static func theme(id: String) -> Theme? { all.first { $0.id == id } }
}
