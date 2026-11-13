/// Ink is kept as data, not pixels, so it stays interactive (hit-testing for G9, G27,
/// G28) and survives rotation.
///
/// Coordinates are resolution-independent "canvas units": a point's offset from the
/// canvas center divided by the canvas's shorter side. A rotation or size change
/// therefore keeps ink centered and at the same physical scale relative to the screen.

public struct InkPoint: Codable, Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var t: Double
    /// Full line width in canvas units.
    public var width: Float
    /// Normalized 0...1, negative when unavailable.
    public var force: Float

    public init(x: Float, y: Float, t: Double, width: Float, force: Float = -1) {
        self.x = x; self.y = y; self.t = t; self.width = width; self.force = force
    }
}

public struct Stroke: Codable, Equatable, Sendable {
    public var id: UInt32
    public var points: [InkPoint]
    public var isPencil: Bool

    public init(id: UInt32, points: [InkPoint], isPencil: Bool) {
        self.id = id; self.points = points; self.isPencil = isPencil
    }
}

/// All committed ink. Undo, Clear and erase arrive in M3 and M7.
public struct InkDocument: Codable, Equatable, Sendable {
    public private(set) var strokes: [Stroke] = []
    public init() {}
    public mutating func append(_ stroke: Stroke) { strokes.append(stroke) }
}

/// Maps view points to canvas units and back for the current canvas size.
public struct InkSpace: Equatable, Sendable {
    public private(set) var width: Float
    public private(set) var height: Float
    public var centerX: Float { width * 0.5 }
    public var centerY: Float { height * 0.5 }
    /// Points per canvas unit (the shorter side).
    public var unit: Float { max(1, min(width, height)) }

    public init(width: Float, height: Float) {
        self.width = width; self.height = height
    }

    public func toUnits(x: Float, y: Float) -> SIMD2<Float> {
        SIMD2((x - centerX) / unit, (y - centerY) / unit)
    }

    public func toPoints(_ p: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(p.x * unit + centerX, p.y * unit + centerY)
    }
}

/// Line-shape parameters. A theme supplies these in V2; they are never hard-coded in
/// effect code.
public struct InkBrush: Codable, Equatable, Sendable {
    /// Finger line width at rest, in points.
    public var baseWidth: Float = 5
    /// G7: line thins as speed rises, down to this fraction of base width.
    public var minSpeedWidthFactor: Float = 0.45
    /// Speed (pt/s) at which the line reaches its thinnest.
    public var speedForMinWidth: Float = 2200
    /// Weight of each new speed sample in the running average.
    public var speedSmoothing: Float = 0.3
    /// Pencil: width at zero force as a fraction of base, and how much tilt widens it.
    public var pencilMinForceFactor: Float = 0.3
    public var pencilForceGain: Float = 1.0
    public var pencilTiltWiden: Float = 1.2
    /// Length of the tapered ends, in points.
    public var taperLength: Float = 22
    /// Narrowest a tapered tip gets, as a fraction of the width.
    public var taperMinFactor: Float = 0.04
    /// Glow halo width as a multiple of the core width.
    public var glowWidthFactor: Float = 3.2
    /// Samples closer than this (points) to the last one are skipped.
    public var minPointSpacing: Float = 0.75

    public init() {}
    public static let `default` = InkBrush()
}
