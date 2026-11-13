import Foundation

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

/// G15: a round ink blot soaking into the page, in canvas units.
public struct InkBlot: Codable, Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var radius: Float
    public init(x: Float, y: Float, radius: Float) { self.x = x; self.y = y; self.radius = radius }
}

public struct Stroke: Codable, Equatable, Sendable {
    public var id: UInt32
    public var points: [InkPoint]
    public var isPencil: Bool
    /// Blots left by dwelling (G15) while drawing this stroke.
    public var blots: [InkBlot]
    /// G17 ribbon: the second edge, one point per point of `points`. The space between
    /// the two edges is filled.
    public var partner: [InkPoint]?
    /// G29: the stroke closes a shape whose inside is filled.
    public var filled: Bool

    public init(id: UInt32, points: [InkPoint], isPencil: Bool, blots: [InkBlot] = [],
                partner: [InkPoint]? = nil, filled: Bool = false) {
        self.id = id; self.points = points; self.isPencil = isPencil; self.blots = blots
        self.partner = partner; self.filled = filled
    }

    public var isRibbon: Bool { partner != nil }

    /// A closed, evenly sampled circle (G10 "snaps into a clean ring").
    public static func circle(id: UInt32, centerX: Float, centerY: Float, radius: Float,
                              width: Float, startAngle: Float = 0, t: Double = 0) -> Stroke {
        let n = max(24, Int(radius * 2 * .pi / 0.004))   // about one point per 0.004 units
        let pts = (0...n).map { k -> InkPoint in
            let a = startAngle + Float(k) / Float(n) * 2 * .pi
            return InkPoint(x: centerX + radius * cos(a), y: centerY + radius * sin(a), t: t, width: width)
        }
        return Stroke(id: id, points: pts, isPencil: false)
    }
}

/// All committed ink. A value type, so an undo snapshot is a cheap copy-on-write copy.
public struct InkDocument: Codable, Equatable, Sendable {
    public private(set) var strokes: [Stroke] = []
    public init() {}

    public mutating func append(_ stroke: Stroke) { strokes.append(stroke) }

    public mutating func removeAll() { strokes.removeAll() }

    public var isEmpty: Bool { strokes.isEmpty }

    /// G9: erases ink inside a circle (canvas units). Strokes are split around the
    /// erased part; pieces shorter than two points and blots inside are removed.
    /// Erased point positions are appended to `erased` (for the dissolve effect).
    /// Returns true if anything changed.
    @discardableResult
    public mutating func erase(x: Float, y: Float, radius: Float, erased: inout [SIMD2<Float>]) -> Bool {
        let r2 = radius * radius
        var changed = false
        var out: [Stroke] = []
        out.reserveCapacity(strokes.count)
        for stroke in strokes {
            guard stroke.intersects(x: x, y: y, radius: radius) else { out.append(stroke); continue }
            if let partner = stroke.partner {
                // Ribbons are removed whole when the eraser touches either edge or the fill.
                func inside(_ px: Float, _ py: Float) -> Bool {
                    let dx = px - x, dy = py - y
                    return dx * dx + dy * dy <= r2
                }
                var hit = false
                for (a, b) in zip(stroke.points, partner) {
                    let mx: Float = (a.x + b.x) * 0.5
                    let my: Float = (a.y + b.y) * 0.5
                    if inside(a.x, a.y) || inside(b.x, b.y) || inside(mx, my) { hit = true; break }
                }
                if hit {
                    changed = true
                    for p in stroke.points { erased.append(SIMD2(p.x, p.y)) }
                } else {
                    out.append(stroke)
                }
                continue
            }
            var pieces: [[InkPoint]] = [[]]
            var hit = false
            for p in stroke.points {
                let dx = p.x - x, dy = p.y - y
                let reach = radius + p.width * 0.5
                if dx * dx + dy * dy <= reach * reach {
                    hit = true
                    erased.append(SIMD2(p.x, p.y))
                    if !pieces[pieces.count - 1].isEmpty { pieces.append([]) }
                } else {
                    pieces[pieces.count - 1].append(p)
                }
            }
            var blots = stroke.blots
            let before = blots.count
            blots.removeAll { b in
                let dx = b.x - x, dy = b.y - y
                return dx * dx + dy * dy <= r2 + b.radius * b.radius
            }
            if blots.count != before { hit = true }
            guard hit else { out.append(stroke); continue }
            changed = true
            var first = true
            for piece in pieces where piece.count >= 2 {
                out.append(Stroke(id: stroke.id, points: piece, isPencil: stroke.isPencil, blots: first ? blots : []))
                first = false
            }
            if first && !blots.isEmpty {
                // The line is gone but blots outside the eraser remain.
                out.append(Stroke(id: stroke.id, points: [], isPencil: stroke.isPencil, blots: blots))
            }
        }
        if changed { strokes = out }
        return changed
    }
}

extension Stroke {
    /// Cheap bounding-box test (canvas units).
    func intersects(x: Float, y: Float, radius: Float) -> Bool {
        guard !points.isEmpty || !blots.isEmpty else { return false }
        var minX = Float.greatestFiniteMagnitude, minY = minX, maxX = -minX, maxY = -minX
        var pad: Float = 0
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y)
            pad = max(pad, p.width)
        }
        for p in partner ?? [] {
            minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        for b in blots {
            minX = min(minX, b.x - b.radius); maxX = max(maxX, b.x + b.radius)
            minY = min(minY, b.y - b.radius); maxY = max(maxY, b.y + b.radius)
        }
        return x + radius >= minX - pad && x - radius <= maxX + pad
            && y + radius >= minY - pad && y - radius <= maxY + pad
    }
}

/// Undo history (D4, R3). Every change to ink goes through `record`, so a wrong
/// guess by an after-the-fact gesture costs exactly one undo.
public struct InkHistory: Sendable {
    public private(set) var document = InkDocument() { didSet { version &+= 1 } }
    /// Changes every time the document does (for caches such as the hit-test index).
    public private(set) var version: UInt64 = 0
    private var undoStack: [InkDocument] = []
    public let limit: Int

    public init(limit: Int = 64) { self.limit = limit }

    public var canUndo: Bool { !undoStack.isEmpty }

    /// Applies a change as one undoable step.
    public mutating func record(_ change: (inout InkDocument) -> Void) {
        let before = document
        change(&document)
        guard document != before else { return }
        push(before)
    }

    /// Saves the current state as an undo point without changing it. Use before a
    /// change that is applied gradually (a scribble erasing over many frames).
    public mutating func checkpoint() { push(document) }

    /// Changes the document without adding an undo step (continuing a checkpointed change).
    public mutating func continueChange(_ change: (inout InkDocument) -> Void) { change(&document) }

    /// Records `undoState` as the state undo returns to, while the document stays as
    /// it is. Used when a gesture consumes a stroke that was never committed (G8 flick,
    /// G12 zigzag): undo brings the stroke back as ink.
    public mutating func pushUndoState(_ undoState: InkDocument) { push(undoState) }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let last = undoStack.popLast() else { return false }
        document = last
        return true
    }

    private mutating func push(_ d: InkDocument) {
        undoStack.append(d)
        if undoStack.count > limit { undoStack.removeFirst() }
    }
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
