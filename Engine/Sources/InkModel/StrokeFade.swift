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
