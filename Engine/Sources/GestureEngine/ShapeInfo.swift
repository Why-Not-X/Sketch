import Foundation

/// Geometry of one finished (or in-progress) stroke path, used by the after-the-fact
/// recognizers G10 to G12 and G8 (R3). Pure and cheap: one pass plus a resample.
struct ShapeInfo {
    var count = 0
    var length: Float = 0
    var duration: Double = 0
    /// Centroid.
    var cx: Float = 0, cy: Float = 0
    var meanRadius: Float = 0
    /// Standard deviation of the radius divided by its mean (0 = perfect circle).
    var radiusVariation: Float = 0
    /// Signed angle the path sweeps around the centroid, in radians.
    var sweep: Float = 0
    /// Mean radius of the first and last fifth of the path.
    var startRadius: Float = 0
    var endRadius: Float = 0
    /// Distance from the last point back to the first.
    var closeGap: Float = 0
    /// Direction changes sharper than `zigzagTurnDot`, measured on a resampled path.
    var sharpTurns = 0
    /// Larger side of the bounding box.
    var extent: Float = 0

    var turns: Float { abs(sweep) / (2 * .pi) }

    static func analyze(_ p: [PathPoint], config c: GestureConfig) -> ShapeInfo {
        var s = ShapeInfo()
        let n = p.count
        s.count = n
        guard n >= 2 else { return s }
        s.duration = p[n - 1].t - p[0].t

        var minX = p[0].x, maxX = p[0].x, minY = p[0].y, maxY = p[0].y
        var sx: Float = 0, sy: Float = 0
        for k in 0..<n {
            let q = p[k]
            sx += q.x; sy += q.y
            minX = min(minX, q.x); maxX = max(maxX, q.x)
            minY = min(minY, q.y); maxY = max(maxY, q.y)
            if k > 0 { s.length += hypot(q.x - p[k - 1].x, q.y - p[k - 1].y) }
        }
        s.extent = max(maxX - minX, maxY - minY)
        s.cx = sx / Float(n); s.cy = sy / Float(n)
        s.closeGap = hypot(p[n - 1].x - p[0].x, p[n - 1].y - p[0].y)

        // Radius statistics and swept angle around the centroid.
        var sumR: Float = 0, sumR2: Float = 0
        var prevAngle: Float? = nil
        let fifth = max(1, n / 5)
        var headR: Float = 0, tailR: Float = 0
        for k in 0..<n {
            let dx = p[k].x - s.cx, dy = p[k].y - s.cy
            let r = (dx * dx + dy * dy).squareRoot()
            sumR += r; sumR2 += r * r
            if k < fifth { headR += r }
            if k >= n - fifth { tailR += r }
            if r > 2 {
                let a = atan2(dy, dx)
                if let pa = prevAngle {
                    var d = a - pa
                    if d > .pi { d -= 2 * .pi } else if d < -.pi { d += 2 * .pi }
                    s.sweep += d
                }
                prevAngle = a
            }
        }
        s.meanRadius = sumR / Float(n)
        let variance = max(0, sumR2 / Float(n) - s.meanRadius * s.meanRadius)
        s.radiusVariation = s.meanRadius > 0 ? variance.squareRoot() / s.meanRadius : 1
        s.startRadius = headR / Float(fifth)
        s.endRadius = tailR / Float(fifth)

        // Sharp turns on a path resampled every `zigzagSegment` points. Each direction
        // is compared with the one two segments back, because the segment that cuts a
        // corner splits the turn in half. After a turn is counted, the next two
        // segments are skipped so one corner counts once.
        var ax = p[0].x, ay = p[0].y
        var dirs = 0
        var d1X: Float = 0, d1Y: Float = 0, d2X: Float = 0, d2Y: Float = 0   // previous, two back
        var cooldown = 0
        for k in 1..<n {
            let dx = p[k].x - ax, dy = p[k].y - ay
            let d = (dx * dx + dy * dy).squareRoot()
            guard d >= c.zigzagSegment else { continue }
            let nx = dx / d, ny = dy / d
            if cooldown > 0 {
                cooldown -= 1
            } else if dirs >= 2 && nx * d2X + ny * d2Y < c.zigzagTurnDot {
                s.sharpTurns += 1
                cooldown = 2
            } else if dirs >= 1 && nx * d1X + ny * d1Y < c.zigzagTurnDot {
                s.sharpTurns += 1
                cooldown = 2
            }
            d2X = d1X; d2Y = d1Y
            d1X = nx; d1Y = ny
            dirs += 1
            ax = p[k].x; ay = p[k].y
        }
        return s
    }

    // MARK: Classifications

    func isCircle(_ c: GestureConfig) -> Bool {
        count >= 10 && meanRadius >= c.circleMinRadius
            && radiusVariation <= c.circleMaxRadiusVariation
            && abs(sweep) >= c.circleMinSweep && abs(sweep) <= c.circleMaxSweep
            && closeGap <= c.circleMaxCloseGap * meanRadius
    }

    /// +1 inward, -1 outward, 0 not a spiral.
    func spiralDirection(_ c: GestureConfig) -> Float {
        guard count >= 10, turns >= c.spiralMinTurns, startRadius > 0, endRadius > 0 else { return 0 }
        if endRadius <= startRadius * c.spiralRadiusRatio { return 1 }
        if startRadius <= endRadius * c.spiralRadiusRatio { return -1 }
        return 0
    }

    func isZigzag(_ c: GestureConfig) -> Bool {
        sharpTurns >= c.zigzagMinSharpTurns && extent >= c.zigzagMinExtent
    }
}
