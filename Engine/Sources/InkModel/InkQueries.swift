import Foundation

/// Bounding boxes of every stroke, so hit tests skip far-away ink cheaply. Rebuild it
/// whenever the document changes (commit, erase, undo).
public struct InkIndex: Sendable {
    public struct Box: Sendable { public var minX, minY, maxX, maxY: Float }
    public private(set) var boxes: [Box] = []

    public init() {}

    public init(_ doc: InkDocument) {
        boxes = doc.strokes.map { s in
            var b = Box(minX: .greatestFiniteMagnitude, minY: .greatestFiniteMagnitude,
                        maxX: -.greatestFiniteMagnitude, maxY: -.greatestFiniteMagnitude)
            var pad: Float = 0
            for p in s.points {
                b.minX = min(b.minX, p.x); b.maxX = max(b.maxX, p.x)
                b.minY = min(b.minY, p.y); b.maxY = max(b.maxY, p.y)
                pad = max(pad, p.width * 0.5)
            }
            for p in s.partner ?? [] {
                b.minX = min(b.minX, p.x); b.maxX = max(b.maxX, p.x)
                b.minY = min(b.minY, p.y); b.maxY = max(b.maxY, p.y)
            }
            b.minX -= pad; b.minY -= pad; b.maxX += pad; b.maxY += pad
            return b
        }
    }

    func near(_ k: Int, x0: Float, y0: Float, x1: Float, y1: Float, pad: Float) -> Bool {
        guard k < boxes.count else { return false }
        let b = boxes[k]
        return max(x0, x1) + pad >= b.minX && min(x0, x1) - pad <= b.maxX
            && max(y0, y1) + pad >= b.minY && min(y0, y1) - pad <= b.maxY
    }
}

/// Answers from ink queries, in canvas units.
public struct InkHit: Equatable, Sendable {
    public var strokeID: UInt32
    public var x: Float, y: Float
    public var along: Float
    public var length: Float
}

public struct InkCrossing: Equatable, Sendable {
    public var strokeID: UInt32
    public var x: Float, y: Float
    public var dirX: Float, dirY: Float
}

extension InkDocument {
    /// G27: the stroke line nearest to (x, y) within `radius` (plus half its width).
    public func hit(x: Float, y: Float, radius: Float, index: InkIndex) -> InkHit? {
        var best: InkHit? = nil
        var bestD = Float.greatestFiniteMagnitude
        for (k, s) in strokes.enumerated() where s.points.count >= 2 {
            guard index.near(k, x0: x, y0: y, x1: x, y1: y, pad: radius) else { continue }
            var along: Float = 0
            var total: Float = 0
            for j in 1..<s.points.count { total += hypot(s.points[j].x - s.points[j - 1].x, s.points[j].y - s.points[j - 1].y) }
            for j in 1..<s.points.count {
                let a = s.points[j - 1], b = s.points[j]
                let dx = b.x - a.x, dy = b.y - a.y
                let len2 = dx * dx + dy * dy
                let t = len2 > 0 ? max(0, min(1, ((x - a.x) * dx + (y - a.y) * dy) / len2)) : 0
                let px = a.x + dx * t, py = a.y + dy * t
                let d = hypot(x - px, y - py)
                let reach = radius + max(a.width, b.width) * 0.5
                if d <= reach && d < bestD {
                    bestD = d
                    best = InkHit(strokeID: s.id, x: px, y: py, along: along + len2.squareRoot() * t, length: total)
                }
                along += len2.squareRoot()
            }
        }
        return best
    }

    /// G28: where the segment from (x0, y0) to (x1, y1) first crosses a stroke line.
    public func crossing(x0: Float, y0: Float, x1: Float, y1: Float, index: InkIndex) -> InkCrossing? {
        var best: InkCrossing? = nil
        var bestT = Float.greatestFiniteMagnitude
        let rx = x1 - x0, ry = y1 - y0
        for (k, s) in strokes.enumerated() where s.points.count >= 2 {
            guard index.near(k, x0: x0, y0: y0, x1: x1, y1: y1, pad: 0) else { continue }
            for j in 1..<s.points.count {
                let a = s.points[j - 1], b = s.points[j]
                let sx = b.x - a.x, sy = b.y - a.y
                let denom = rx * sy - ry * sx
                guard abs(denom) > 1e-12 else { continue }
                let qx = a.x - x0, qy = a.y - y0
                let t = (qx * sy - qy * sx) / denom      // along the new segment
                let u = (qx * ry - qy * rx) / denom      // along the stroke segment
                guard t >= 0, t <= 1, u >= 0, u <= 1, t < bestT else { continue }
                bestT = t
                let len = max(1e-9, (sx * sx + sy * sy).squareRoot())
                best = InkCrossing(strokeID: s.id, x: x0 + rx * t, y: y0 + ry * t, dirX: sx / len, dirY: sy / len)
            }
        }
        return best
    }
}

/// G29: fills the inside of a closed stroke. The outline is resampled to at most
/// `maxPoints` and triangulated by ear clipping; a self-intersecting outline falls
/// back to a fan from its centroid.
public enum FillTessellator {
    public static func append(_ outline: [InkPoint], alpha: Float, maxPoints: Int = 96, into out: inout [InkVertex]) {
        guard outline.count >= 3 else { return }
        let step = max(1, outline.count / maxPoints)
        var poly: [SIMD2<Float>] = stride(from: 0, to: outline.count, by: step).map { SIMD2(outline[$0].x, outline[$0].y) }
        if poly.count >= 2, hypot(poly[0].x - poly[poly.count - 1].x, poly[0].y - poly[poly.count - 1].y) < 1e-6 { poly.removeLast() }
        guard poly.count >= 3 else { return }
        func v(_ p: SIMD2<Float>) -> InkVertex { InkVertex(x: p.x, y: p.y, u: 0, coreFrac: 1, alpha: alpha, along: 0, halfWidth: 1) }
        if let tris = earClip(poly) {
            for t in tris { out.append(v(poly[t.0])); out.append(v(poly[t.1])); out.append(v(poly[t.2])) }
        } else {
            let c = poly.reduce(SIMD2<Float>(0, 0), +) / Float(poly.count)
            for k in 0..<poly.count { out.append(v(c)); out.append(v(poly[k])); out.append(v(poly[(k + 1) % poly.count])) }
        }
    }

    /// Ear clipping for a simple polygon. Returns nil if it gets stuck (self-intersecting).
    static func earClip(_ p: [SIMD2<Float>]) -> [(Int, Int, Int)]? {
        var area: Float = 0
        for k in 0..<p.count { let a = p[k], b = p[(k + 1) % p.count]; area += a.x * b.y - b.x * a.y }
        let ccw = area > 0
        var idx = Array(p.indices)
        var tris: [(Int, Int, Int)] = []
        func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        func inside(_ q: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
            let d1 = cross(a, b, q), d2 = cross(b, c, q), d3 = cross(c, a, q)
            let neg = d1 < 0 || d2 < 0 || d3 < 0, pos = d1 > 0 || d2 > 0 || d3 > 0
            return !(neg && pos)
        }
        var guardCount = 0
        while idx.count > 3 {
            guardCount += 1
            if guardCount > p.count * p.count { return nil }
            var clipped = false
            for k in 0..<idx.count {
                let i0 = idx[(k + idx.count - 1) % idx.count], i1 = idx[k], i2 = idx[(k + 1) % idx.count]
                let c = cross(p[i0], p[i1], p[i2])
                guard ccw ? c > 0 : c < 0 else { continue }
                var ear = true
                for j in idx where j != i0 && j != i1 && j != i2 {
                    if inside(p[j], p[i0], p[i1], p[i2]) { ear = false; break }
                }
                guard ear else { continue }
                tris.append((i0, i1, i2))
                idx.remove(at: k)
                clipped = true
                break
            }
            if !clipped { return nil }
        }
        tris.append((idx[0], idx[1], idx[2]))
        return tris
    }
}
