/// One input sample for a live stroke, in view points.
public struct StrokeSample: Sendable {
    public var x: Float
    public var y: Float
    public var t: Double
    /// Normalized 0...1, negative when unavailable.
    public var force: Float
    public var altitude: Float
    public var isPencil: Bool

    public init(x: Float, y: Float, t: Double, force: Float = -1, altitude: Float = .pi / 2, isPencil: Bool = false) {
        self.x = x; self.y = y; self.t = t; self.force = force; self.altitude = altitude; self.isPencil = isPencil
    }
}

/// Builds one live stroke from real and predicted samples.
/// `points` holds the real points followed by `predictedCount` predicted ones.
/// Predicted points are dropped as soon as a real sample arrives.
/// Reusable: call `begin` again after `finish` without reallocating.
public final class StrokeBuilder {
    public private(set) var points: [InkPoint] = []
    public private(set) var predictedCount = 0
    public private(set) var strokeID: UInt32 = 0
    public private(set) var isPencil = false
    /// Farthest distance (points) any real sample got from the touch-down point.
    public private(set) var maxDisplacement: Float = 0
    public private(set) var isActive = false

    private var space = InkSpace(width: 1, height: 1)
    private var brush = InkBrush.default
    private var startX: Float = 0, startY: Float = 0
    private var lastX: Float = 0, lastY: Float = 0, lastT: Double = 0
    private var smoothedSpeed: Float = 0

    public init(capacity: Int = 4096) {
        points.reserveCapacity(capacity)
    }

    /// Last point including predictions, in canvas units.
    public var head: SIMD2<Float>? {
        guard let p = points.last else { return nil }
        return SIMD2(p.x, p.y)
    }

    public var realPointCount: Int { points.count - predictedCount }

    public func begin(id: UInt32, sample s: StrokeSample, space: InkSpace, brush: InkBrush) {
        points.removeAll(keepingCapacity: true)
        predictedCount = 0
        strokeID = id
        isPencil = s.isPencil
        self.space = space
        self.brush = brush
        startX = s.x; startY = s.y
        lastX = s.x; lastY = s.y; lastT = s.t
        smoothedSpeed = 0
        maxDisplacement = 0
        isActive = true
        append(s)
    }

    public func addReal(_ s: StrokeSample) {
        guard isActive else { return }
        dropPredicted()
        let dx = s.x - lastX, dy = s.y - lastY
        let d = (dx * dx + dy * dy).squareRoot()
        if d < brush.minPointSpacing { return }
        let dt = Float(s.t - lastT)
        if dt > 0 {
            smoothedSpeed += brush.speedSmoothing * (d / dt - smoothedSpeed)
        }
        lastX = s.x; lastY = s.y; lastT = s.t
        let ox = s.x - startX, oy = s.y - startY
        maxDisplacement = max(maxDisplacement, (ox * ox + oy * oy).squareRoot())
        append(s)
    }

    public func addPredicted(_ s: StrokeSample) {
        guard isActive else { return }
        append(s)
        predictedCount += 1
    }

    public func dropPredicted() {
        if predictedCount > 0 {
            points.removeLast(predictedCount)
            predictedCount = 0
        }
    }

    /// Ends the stroke and returns it. Predicted points never become ink.
    public func finish(final s: StrokeSample?) -> Stroke {
        if let s { addReal(s) }
        dropPredicted()
        isActive = false
        return Stroke(id: strokeID, points: points, isPencil: isPencil)
    }

    public func cancel() {
        points.removeAll(keepingCapacity: true)
        predictedCount = 0
        isActive = false
    }

    /// Current smoothed speed in points per second.
    public var speed: Float { smoothedSpeed }

    private func append(_ s: StrokeSample) {
        let p = space.toUnits(x: s.x, y: s.y)
        let w = widthInPoints(s) / space.unit
        points.append(InkPoint(x: p.x, y: p.y, t: s.t, width: w, force: s.force))
    }

    private func widthInPoints(_ s: StrokeSample) -> Float {
        if s.isPencil {
            // R6: pressure and tilt set width.
            let f = s.force >= 0 ? min(1, s.force) : 0.5
            let tilt = 1 - min(1, max(0, s.altitude) / (.pi / 2))
            let forceFactor = brush.pencilMinForceFactor + brush.pencilForceGain * f
            return brush.baseWidth * forceFactor * (1 + brush.pencilTiltWiden * tilt * tilt)
        }
        // G7: line thins as speed rises.
        let x = min(1, max(0, smoothedSpeed / brush.speedForMinWidth))
        let eased = x * x * (3 - 2 * x)
        return brush.baseWidth * (1 - (1 - brush.minSpeedWidthFactor) * eased)
    }
}
