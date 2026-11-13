/// Raw input, as captured by the canvas view. The input layer only produces these;
/// it never interprets them. Codable so V4 can send them between devices and so
/// tests can replay recorded traces.
public enum TouchPhase: UInt8, Codable, Sendable {
    case began, moved, ended, cancelled
}

public enum TouchKind: UInt8, Codable, Sendable {
    case finger, pencil
}

public struct TouchEvent: Codable, Equatable, Sendable {
    /// Stable for the lifetime of one touch; small (slot index), reused after lift.
    public var touchID: UInt16
    public var phase: TouchPhase
    public var kind: TouchKind
    /// Seconds on the monotonic system-uptime clock (same base as `UITouch.timestamp`).
    public var timestamp: Double
    /// Position in view points. Gesture thresholds (Appendix A) are in points.
    public var x: Float
    public var y: Float
    /// Normalized 0...1; negative when the hardware does not report force.
    public var force: Float
    /// Radians from the surface; .pi / 2 for fingers.
    public var altitude: Float
    /// Contact radius in points.
    public var majorRadius: Float
    /// True for predicted samples. They are drawn ahead of the finger and discarded
    /// as soon as real samples arrive.
    public var isPredicted: Bool

    public init(touchID: UInt16, phase: TouchPhase, kind: TouchKind, timestamp: Double,
                x: Float, y: Float, force: Float = -1, altitude: Float = .pi / 2,
                majorRadius: Float = 10, isPredicted: Bool = false) {
        self.touchID = touchID
        self.phase = phase
        self.kind = kind
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.force = force
        self.altitude = altitude
        self.majorRadius = majorRadius
        self.isPredicted = isPredicted
    }
}

/// A recorded or synthetic sequence of touch events, stored as a JSON array.
public typealias TouchTrace = [TouchEvent]
