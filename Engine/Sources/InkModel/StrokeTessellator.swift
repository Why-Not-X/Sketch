import Foundation

/// One ink vertex, laid out to match `InkVertex` in ShaderSource.swift (7 x Float, 28 bytes).
public struct InkVertex: Equatable, Sendable {
    public var x: Float
    public var y: Float
    /// Across the stroke: -1 (right edge of glow) to +1 (left edge of glow).
    public var u: Float
    /// Fraction of the half-width that is solid core; the rest is glow.
    public var coreFrac: Float
    public var alpha: Float
    /// Distance along the stroke in canvas units (for later wave effects, G27).
    public var along: Float
    /// Half-width of the glow at this vertex, in canvas units. The shader interpolates
    /// u·halfWidth and halfWidth separately and divides, which keeps the core edge
    /// straight across tapered quads instead of zigzagging at the triangle diagonal.
    public var halfWidth: Float

    public init(x: Float, y: Float, u: Float, coreFrac: Float, alpha: Float, along: Float, halfWidth: Float = 1) {
        self.x = x; self.y = y; self.u = u; self.coreFrac = coreFrac; self.alpha = alpha; self.along = along
        self.halfWidth = halfWidth
    }
}

/// Turns a polyline with per-point widths into a triangle list with tapered ends and
/// a glow halo. Allocation-free apart from growing `out`.
public enum StrokeTessellator {
    /// - Parameters:
    ///   - taperLength: in canvas units.
    ///   - taperEnd: false while the stroke is live, so the head stays full width.
    public static func append(_ points: [InkPoint], taperStart: Bool, taperEnd: Bool,
                              taperLength: Float, taperMinFactor: Float,
                              glowFactor: Float, alpha: Float = 1,
                              into out: inout [InkVertex]) {
        let n = points.count
        guard n >= 2 else { return }

        var total: Float = 0
        for i in 1..<n { total += distance(points[i - 1], points[i]) }
        let taper = min(taperLength, total * 0.5)
        let coreFrac = 1 / max(1, glowFactor)

        var s: Float = 0
        var prevL = SIMD2<Float>.zero, prevR = SIMD2<Float>.zero, prevS: Float = 0, prevH: Float = 0

        for i in 0..<n {
            if i > 0 { s += distance(points[i - 1], points[i]) }
            let a = points[max(i - 1, 0)], b = points[min(i + 1, n - 1)]
            var tx = b.x - a.x, ty = b.y - a.y
            let len = (tx * tx + ty * ty).squareRoot()
            if len > 1e-7 { tx /= len; ty /= len } else { tx = 1; ty = 0 }
            let nx = -ty, ny = tx

            var f: Float = 1
            if taper > 0 {
                if taperStart { f = min(f, taperCurve(s / taper, min: taperMinFactor)) }
                if taperEnd { f = min(f, taperCurve((total - s) / taper, min: taperMinFactor)) }
            }
            let h = points[i].width * 0.5 * f * glowFactor
            let p = SIMD2(points[i].x, points[i].y)
            let l = p + SIMD2(nx, ny) * h
            let r = p - SIMD2(nx, ny) * h

            if i > 0 {
                out.append(InkVertex(x: prevL.x, y: prevL.y, u: 1, coreFrac: coreFrac, alpha: alpha, along: prevS, halfWidth: prevH))
                out.append(InkVertex(x: prevR.x, y: prevR.y, u: -1, coreFrac: coreFrac, alpha: alpha, along: prevS, halfWidth: prevH))
                out.append(InkVertex(x: l.x, y: l.y, u: 1, coreFrac: coreFrac, alpha: alpha, along: s, halfWidth: h))
                out.append(InkVertex(x: prevR.x, y: prevR.y, u: -1, coreFrac: coreFrac, alpha: alpha, along: prevS, halfWidth: prevH))
                out.append(InkVertex(x: r.x, y: r.y, u: -1, coreFrac: coreFrac, alpha: alpha, along: s, halfWidth: h))
                out.append(InkVertex(x: l.x, y: l.y, u: 1, coreFrac: coreFrac, alpha: alpha, along: s, halfWidth: h))
            }
            prevL = l; prevR = r; prevS = s; prevH = h
        }
    }

    @inline(__always)
    static func distance(_ a: InkPoint, _ b: InkPoint) -> Float {
        let dx = b.x - a.x, dy = b.y - a.y
        return (dx * dx + dy * dy).squareRoot()
    }

    @inline(__always)
    static func taperCurve(_ x: Float, min m: Float) -> Float {
        // Linear: straight-sided taper, so the per-point steps line up into a clean cone.
        let c = Swift.min(1, Swift.max(0, x))
        return m + (1 - m) * c
    }
}

/// G15 blots: a filled disc drawn with the ink shader. A fan from the center (u = 0)
/// to the rim (u = 1), so the shader's core edge and glow give a soft, feathered rim.
public enum BlotTessellator {
    public static func append(_ b: InkBlot, coreFrac: Float, alpha: Float = 1, segments: Int = 40,
                              into out: inout [InkVertex]) {
        guard b.radius > 0 else { return }
        let outer = b.radius / max(0.05, coreFrac)
        for k in 0..<segments {
            let a0 = Float(k) / Float(segments) * 2 * .pi
            let a1 = Float(k + 1) / Float(segments) * 2 * .pi
            out.append(InkVertex(x: b.x, y: b.y, u: 0, coreFrac: coreFrac, alpha: alpha, along: 0, halfWidth: 1))
            out.append(InkVertex(x: b.x + outer * cos(a0), y: b.y + outer * sin(a0), u: 1, coreFrac: coreFrac, alpha: alpha, along: 0, halfWidth: 1))
            out.append(InkVertex(x: b.x + outer * cos(a1), y: b.y + outer * sin(a1), u: 1, coreFrac: coreFrac, alpha: alpha, along: 0, halfWidth: 1))
        }
    }
}
