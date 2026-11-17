/// Fade mode: a released line dissolves from its start toward its end, like a trail
/// catching up with where the finger left. Pure math, applied to already-tessellated
/// vertices, so the line itself never changes.
public struct StrokeFade: Equatable, Sendable {
    /// Seconds after lift before the trail starts to eat the line.
    public var delay: Double = 0.35
    /// Seconds for the trail to travel the whole line.
    public var duration: Double = 1.4
    /// Width of the soft edge of the trail, as a fraction of the line's length.
    public var softness: Float = 0.25

    public init() {}

    /// 0 at lift ... 1 when the line is gone.
    public func progress(age: Double) -> Float {
        Float(min(1, max(0, (age - delay) / duration)))
    }

    public func isFinished(age: Double) -> Bool { age >= delay + duration }

    /// Opacity of the point `fraction` (0 = start, 1 = end) of the line at `progress`.
    /// The trail front sweeps from before the start to past the end, with a soft edge,
    /// so the start goes first and the end last.
    public func alpha(fraction: Float, progress p: Float) -> Float {
        let front = -softness + p * (1 + softness)
        let k = (fraction - front) / softness
        let c = min(1, max(0, k))
        return c * c * (3 - 2 * c)
    }

    /// Applies the trail to vertices `range` of `vertices` that belong to one line whose
    /// total length (canvas units) is `length`. Vertices carry their distance along the
    /// line in `along`.
    public func apply(to vertices: inout [InkVertex], range: Range<Int>, length: Float, progress p: Float) {
        guard length > 0 else { return }
        for k in range {
            vertices[k].alpha *= alpha(fraction: vertices[k].along / length, progress: p)
        }
    }
}

extension Stroke {
    /// Length along the points, in canvas units.
    public var length: Float {
        guard points.count >= 2 else { return 0 }
        var total: Float = 0
        for k in 1..<points.count {
            let dx = points[k].x - points[k - 1].x, dy = points[k].y - points[k - 1].y
            total += (dx * dx + dy * dy).squareRoot()
        }
        return total
    }
}

/// Fade mode: erasing part of a shape unravels the rest of it. The fade starts where
/// the eraser touched and spreads both ways along the outline (around a closed shape,
/// the two fronts meet on the far side). Pure math on already-tessellated vertices.
public struct ShapeUnravel: Equatable, Sendable {
    /// Seconds for the fade to reach the farthest point of the shape.
    public var duration: Double = 1.1
    /// Width of the soft edge, as a fraction of the farthest distance.
    public var softness: Float = 0.2
    /// Distance along the outline (canvas units) where the eraser touched.
    public let origin: Float
    public let length: Float
    /// Closed outlines wrap around: the fade goes both ways and meets opposite the touch.
    public let closed: Bool

    public init(origin: Float, length: Float, closed: Bool) {
        self.origin = min(max(0, origin), length); self.length = length; self.closed = closed
    }

    /// Starts the unravel at the outline point nearest to (x, y).
    public init(stroke: Stroke, x: Float, y: Float) {
        var best = Float.greatestFiniteMagnitude, at: Float = 0, s: Float = 0
        for (k, p) in stroke.points.enumerated() {
            if k > 0 {
                let q = stroke.points[k - 1]
                s += ((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y)).squareRoot()
            }
            let d = (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y)
            if d < best { best = d; at = s }
        }
        var closed = stroke.filled
        if let a = stroke.points.first, let b = stroke.points.last {
            let gap = ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
            if gap <= max(a.width, b.width) * 2 { closed = true }
        }
        self.init(origin: at, length: s, closed: closed)
    }

    public func progress(age: Double) -> Float { Float(min(1, max(0, age / duration))) }
    public func isFinished(age: Double) -> Bool { age >= duration }

    /// The farthest any point is from the touch, measured along the outline.
    public var reach: Float { closed ? length * 0.5 : max(origin, length - origin) }

    /// Distance along the outline from the touch to `along`.
    public func distance(along: Float) -> Float {
        let d = abs(along - origin)
        return closed ? min(d, length - d) : d
    }

    /// Opacity at `along` (canvas units) at `progress`: the touch point goes first,
    /// the farthest point last.
    public func alpha(along: Float, progress p: Float) -> Float {
        guard reach > 0 else { return 1 - p }
        let f = distance(along: along) / reach
        let front = -softness + p * (1 + softness)
        let c = min(1, max(0, (f - front) / softness))
        return c * c * (3 - 2 * c)
    }

    public func apply(to vertices: inout [InkVertex], range: Range<Int>, progress p: Float) {
        for k in range { vertices[k].alpha *= alpha(along: vertices[k].along, progress: p) }
    }
}

extension Stroke {
    /// Point-in-polygon (even-odd) for the outline taken as closed.
    func contains(x: Float, y: Float) -> Bool {
        var inside = false
        var j = points.count - 1
        for i in points.indices {
            let a = points[i], b = points[j]
            if (a.y > y) != (b.y > y), x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
}
