/// Gesture IDs from Appendix A. Never reuse or renumber these.
public enum GestureID: String, Codable, CaseIterable, Sendable {
    case g1 = "G1", g2 = "G2", g3 = "G3", g4 = "G4", g5 = "G5", g6 = "G6", g7 = "G7", g8 = "G8"
    case g9 = "G9", g10 = "G10", g11 = "G11", g12 = "G12", g13 = "G13", g14 = "G14", g15 = "G15", g16 = "G16"
    case g17 = "G17", g18 = "G18", g19 = "G19", g20 = "G20", g21 = "G21", g22 = "G22", g23 = "G23", g24 = "G24"
    case g25 = "G25", g26 = "G26", g27 = "G27", g28 = "G28", g29 = "G29", g30 = "G30", g31 = "G31", g32 = "G32"
}

public enum GesturePhase: UInt8, Codable, Sendable {
    /// One-shot gestures (taps, splash) fire once.
    case fired
    /// Continuous gestures (draw, hold, pinch) begin, change and end.
    case began, changed, ended, cancelled
}

/// Output of the gesture engine. Carries enough parameters for the response mapper
/// and, later, a sound layer (V3) to subscribe as another consumer.
public struct GestureEvent: Codable, Equatable, Sendable {
    public var gesture: GestureID
    public var phase: GesturePhase
    public var timestamp: Double
    /// Location in view points (center point for multi-finger gestures).
    public var x: Float
    public var y: Float
    /// Speed in points per second.
    public var speed: Float
    /// Unit direction of motion, or zero.
    public var directionX: Float
    public var directionY: Float
    public var fingerCount: UInt8
    /// Gesture-specific magnitude: hold time, turns, spread, finger gap, etc.
    public var magnitude: Float
    /// Taps per second for rhythm and drumming gestures; zero otherwise.
    public var tempo: Float
    /// The touch that drives this gesture (the first one, for multi-finger gestures).
    public var touchID: UInt16

    public init(gesture: GestureID, phase: GesturePhase, timestamp: Double, x: Float, y: Float,
                speed: Float = 0, directionX: Float = 0, directionY: Float = 0,
                fingerCount: UInt8 = 1, magnitude: Float = 0, tempo: Float = 0, touchID: UInt16 = 0) {
        self.touchID = touchID
        self.gesture = gesture
        self.phase = phase
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.speed = speed
        self.directionX = directionX
        self.directionY = directionY
        self.fingerCount = fingerCount
        self.magnitude = magnitude
        self.tempo = tempo
    }
}

/// R2 priority classes: multi-finger beats contextual, contextual beats single-finger.
public enum GestureCategory: Int, Comparable, Sendable {
    case multiFinger = 0, contextual = 1, singleFinger = 2
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

extension GestureID {
    public var category: GestureCategory {
        switch self {
        case .g16, .g17, .g18, .g19, .g20, .g21, .g22, .g23, .g24, .g25, .g26: return .multiFinger
        case .g27, .g28, .g29, .g30: return .contextual
        default: return .singleFinger
        }
    }

    /// 0-based position, stable because IDs are never renumbered.
    public var index: Int { Int(rawValue.dropFirst())! - 1 }
}

/// Layers talk through small protocols so any one can be replaced or mocked.
public protocol GestureEventSink: AnyObject {
    func handle(_ event: GestureEvent)
}
