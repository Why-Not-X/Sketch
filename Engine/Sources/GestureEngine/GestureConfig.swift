/// Every time, distance, count and finger limit used by recognizers, taken from the
/// Input column of Appendix A. Tune here, never in recognizer logic.
/// Values marked "assumed" are not stated in the spec and need tuning on device.
public struct GestureConfig: Codable, Equatable, Sendable {
    // Taps (G1 to G4)
    public var tapMaxDuration: Double = 0.250
    public var tapMaxMovement: Float = 10
    public var multiTapMaxInterval: Double = 0.300
    public var doubleTapMaxDistance: Float = 30
    public var rhythmMinTaps: Int = 4
    public var rhythmTempoTolerance: Float = 0.20
    public var rhythmPulseDuration: Double = 8
    public var rhythmMaxInterval: Double = 1.5          // assumed: slowest tempo that counts
    public var multiTapMaxDistanceForTriple: Float = 30 // assumed: spec gives no distance for G3

    // Holds (G5, G6, G14)
    public var longPressMinDuration: Double = 0.400
    public var longPressMaxMovement: Float = 10          // assumed: same as tap
    public var holdReleaseStrengthCap: Double = 2.0

    // Strokes (G7 to G15)
    public var drawMinMovement: Float = 10
    public var scribbleMinReversals: Int = 3
    public var scribbleWindow: Double = 1.0
    public var scribbleMaxExtent: Float = 120           // assumed: "small area"
    public var spiralMinTurns: Float = 1.5
    public var zigzagMinSharpTurns: Int = 3
    public var dwellMinDuration: Double = 0.300
    public var retroactiveConfidence: Float = 0.75      // assumed (R3)

    // Multi-finger (G16 to G26)
    public var multiFingerTapMaxDuration: Double = 0.250
    public var splashMinFingers: Int = 4
    public var rakeMinFingers: Int = 3
    public var gatherFingers: Int = 5
    public var drummingMinTaps: Int = 4
    public var drummingWindow: Double = 1.0

    // Contextual and ambient (G27 to G32)
    public var edgeZone: Float = 20
    public var idleDelay: Double = 5
    public var idleDimAfter: Double = 30

    // Input hygiene (R6)
    public var palmMaxFingerRadius: Float = 40           // assumed

    public init() {}

    public static let `default` = GestureConfig()
}
