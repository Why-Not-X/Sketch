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
    /// Gesture-specific size in points: circle or spiral radius, scribble extent, etc.
    public var size: Float
    /// A second point some gestures carry, such as the slingshot anchor (G13).
    public var originX: Float
    public var originY: Float
    /// Multi-finger gestures: every finger's position, flattened as x0, y0, x1, y1, ...
    public var touchPoints: [Float]
    /// Multi-finger gestures: the touches involved, in the same order as `touchPoints`.
    public var touchIDs: [UInt16]
    /// Contextual gestures: the stroke involved (G27, G28), or 0.
    public var targetID: UInt32

    public init(gesture: GestureID, phase: GesturePhase, timestamp: Double, x: Float, y: Float,
                speed: Float = 0, directionX: Float = 0, directionY: Float = 0,
                fingerCount: UInt8 = 1, magnitude: Float = 0, tempo: Float = 0, touchID: UInt16 = 0,
                size: Float = 0, originX: Float = 0, originY: Float = 0,
                touchPoints: [Float] = [], touchIDs: [UInt16] = [], targetID: UInt32 = 0) {
        self.targetID = targetID
        self.touchPoints = touchPoints
        self.touchIDs = touchIDs
        self.touchID = touchID
        self.size = size
        self.originX = originX
        self.originY = originY
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

// MARK: - Ink hit-testing

/// Where a touch landed on existing ink (G27).
public struct StrokeHit: Equatable, Sendable {
    public var strokeID: UInt32
    /// Closest point on the stroke, in view points.
    public var x: Float, y: Float
    /// Distance from the stroke's start to that point, and the stroke's total length (points).
    public var along: Float
    public var length: Float
    public init(strokeID: UInt32, x: Float, y: Float, along: Float, length: Float) {
        self.strokeID = strokeID; self.x = x; self.y = y; self.along = along; self.length = length
    }
}

/// Where a new stroke segment crosses existing ink (G28).
public struct StrokeCrossing: Equatable, Sendable {
    public var strokeID: UInt32
    public var x: Float, y: Float
    /// Unit direction of the older stroke at the crossing.
    public var dirX: Float, dirY: Float
    public init(strokeID: UInt32, x: Float, y: Float, dirX: Float, dirY: Float) {
        self.strokeID = strokeID; self.x = x; self.y = y; self.dirX = dirX; self.dirY = dirY
    }
}

/// The canvas answers questions about committed ink, so contextual recognizers can
/// stay free of UIKit and of the ink model. All values are in view points.
public protocol InkHitTesting: AnyObject {
    func hitStroke(x: Float, y: Float, radius: Float) -> StrokeHit?
    func crossing(x0: Float, y0: Float, x1: Float, y1: Float) -> StrokeCrossing?
}
