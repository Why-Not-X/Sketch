import UIKit
import GestureEngine

/// Input layer: turns UITouches into `TouchEvent`s and queues them for the next frame.
/// It does nothing else. Everything runs on the main thread (touches and the display
/// link share the main run loop), so the queue needs no lock. The queue is
/// pre-allocated and bounded.
final class TouchInput {
    static let capacity = 4096

    private(set) var queue = ContiguousArray<TouchEvent>()
    private(set) var droppedEvents = 0
    private var slots = [ObjectIdentifier?](repeating: nil, count: 32)

    init() {
        queue.reserveCapacity(Self.capacity)
    }

    func handle(_ touches: Set<UITouch>, event: UIEvent?, phase: TouchPhase, in view: UIView) {
        for touch in touches {
            guard let id = slot(for: touch, create: phase == .began) else { continue }
            if phase == .moved {
                if let coalesced = event?.coalescedTouches(for: touch), !coalesced.isEmpty {
                    for c in coalesced { push(makeEvent(c, id: id, phase: .moved, predicted: false, in: view)) }
                } else {
                    push(makeEvent(touch, id: id, phase: .moved, predicted: false, in: view))
                }
                if let predicted = event?.predictedTouches(for: touch) {
                    for p in predicted { push(makeEvent(p, id: id, phase: .moved, predicted: true, in: view)) }
                }
            } else {
                push(makeEvent(touch, id: id, phase: phase, predicted: false, in: view))
            }
            if phase == .ended || phase == .cancelled {
                slots[Int(id)] = nil
            }
        }
    }

    /// Hands every queued event to `body` in order, then empties the queue.
    func drain(_ body: (TouchEvent) -> Void) {
        for e in queue { body(e) }
        queue.removeAll(keepingCapacity: true)
    }

    /// Queues a pre-built event (trace replay for debugging; V4 remote events later).
    func inject(_ e: TouchEvent) { push(e) }

    private func push(_ e: TouchEvent) {
        guard queue.count < Self.capacity else { droppedEvents += 1; return }
        queue.append(e)
    }

    private func slot(for touch: UITouch, create: Bool) -> UInt16? {
        let key = ObjectIdentifier(touch)
        for i in 0..<slots.count where slots[i] == key { return UInt16(i) }
        guard create else { return nil }
        for i in 0..<slots.count where slots[i] == nil {
            slots[i] = key
            return UInt16(i)
        }
        return nil
    }

    private func makeEvent(_ t: UITouch, id: UInt16, phase: TouchPhase, predicted: Bool, in view: UIView) -> TouchEvent {
        let isPencil = t.type == .pencil
        let p = t.preciseLocation(in: view)
        let force: Float = t.maximumPossibleForce > 0 ? Float(t.force / t.maximumPossibleForce) : -1
        return TouchEvent(
            touchID: id,
            phase: phase,
            kind: isPencil ? .pencil : .finger,
            timestamp: t.timestamp,
            x: Float(p.x), y: Float(p.y),
            force: force,
            altitude: isPencil ? Float(t.altitudeAngle) : .pi / 2,
            majorRadius: Float(t.majorRadius),
            isPredicted: predicted
        )
    }
}
