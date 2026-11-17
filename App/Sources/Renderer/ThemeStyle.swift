import ResponseMapping

/// A theme resolved into the values the shaders use, so a theme switch can cross-fade:
/// colors and amounts blend, while discrete choices (ink mode, texture, sprite, blend)
/// switch halfway through.
struct ThemeStyle {
    var background: SIMD4<Float>
    var edge: SIMD4<Float>
    var vignette: Float
    /// Always 4 entries; unused ones repeat the last color.
    var palette: [SIMD4<Float>]
    var paletteCount: Float
    /// 0 single, 1 per stroke, 2 along the stroke.
    var inkMode: Float
    /// 0 smooth, 1 chalk.
    var texture: Float
    /// 0 soft, 1 star, 2 dust, 3 graphite.
    var sprite: Float
    var glow: SIMD4<Float>
    var glowFromInk: Float
    var glowStrength: Float
    var glowFalloff: Float
    var coreScale: Float
    var sparkle: SIMD4<Float>
    var gravity: Float
    /// Effects paint over the canvas (light themes) instead of adding light.
    var blendOver: Bool

    init(_ t: Theme) {
        func v(_ c: RGBA) -> SIMD4<Float> { SIMD4(c.r, c.g, c.b, c.a) }
        background = v(t.background)
        edge = v(t.backgroundEdge)
        vignette = t.vignette
        var p = t.palette.prefix(4).map(v)
        while p.count < 4 { p.append(p.last ?? SIMD4(1, 1, 1, 1)) }
        palette = p
        paletteCount = Float(min(4, max(1, t.palette.count)))
        switch t.inkMode {
        case .single: inkMode = 0
        case .perStroke: inkMode = 1
        case .alongStroke: inkMode = 2
        }
        texture = t.texture == .chalk ? 1 : 0
        switch t.sprite {
        case .soft: sprite = 0
        case .star: sprite = 1
        case .dust: sprite = 2
        case .graphite: sprite = 3
        }
        glow = v(t.glow)
        glowFromInk = t.glowFromInk ? 1 : 0
        glowStrength = t.glowStrength
        glowFalloff = t.glowFalloff
        coreScale = t.coreScale
        sparkle = v(t.sparkle)
        gravity = t.particleGravity
        blendOver = t.blend == .over
    }

    static func mix(_ a: ThemeStyle, _ b: ThemeStyle, _ k: Float) -> ThemeStyle {
        guard k < 1 else { return b }
        guard k > 0 else { return a }
        func m(_ x: Float, _ y: Float) -> Float { x + (y - x) * k }
        func m4(_ x: SIMD4<Float>, _ y: SIMD4<Float>) -> SIMD4<Float> { x + (y - x) * k }
        var r = k < 0.5 ? a : b   // discrete fields switch halfway
        r.background = m4(a.background, b.background)
        r.edge = m4(a.edge, b.edge)
        r.vignette = m(a.vignette, b.vignette)
        r.palette = (0..<4).map { m4(a.palette[$0], b.palette[$0]) }
        r.glow = m4(a.glow, b.glow)
        r.glowStrength = m(a.glowStrength, b.glowStrength)
        r.glowFalloff = m(a.glowFalloff, b.glowFalloff)
        r.coreScale = m(a.coreScale, b.coreScale)
        r.sparkle = m4(a.sparkle, b.sparkle)
        r.gravity = m(a.gravity, b.gravity)
        return r
    }
}
