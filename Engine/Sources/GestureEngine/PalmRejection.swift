/// R6: finger gestures stay finger-only, with palm rejection on.
/// A finger touch is rejected for its whole lifetime if it lands while the Pencil is
/// down, or if its contact radius looks like a palm. Allocation-free.
public struct PalmRejection: Sendable {
    public var maxFingerRadius: Float
    private var rejected = [Bool](repeating: false, count: 64)
    private var pencilsDown = 0

    public init(maxFingerRadius: Float = GestureConfig.default.palmMaxFingerRadius) {
        self.maxFingerRadius = maxFingerRadius
    }

    /// Returns true if the event should reach the gesture engine.
    public mutating func accept(_ e: TouchEvent) -> Bool {
        let slot = Int(e.touchID) & 63
        if e.kind == .pencil {
            if !e.isPredicted {
                if e.phase == .began { pencilsDown += 1 }
                if e.phase == .ended || e.phase == .cancelled { pencilsDown = max(0, pencilsDown - 1) }
            }
            return true
        }
        switch e.phase {
        case .began:
            let reject = pencilsDown > 0 || e.majorRadius > maxFingerRadius
            rejected[slot] = reject
            return !reject
        case .moved:
            return !rejected[slot]
        case .ended, .cancelled:
            let wasRejected = rejected[slot]
            rejected[slot] = false
            return !wasRejected
        }
    }
}
