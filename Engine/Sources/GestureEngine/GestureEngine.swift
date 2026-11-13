/// The arbiter. Consumes TouchEvents, keeps shared per-touch state, runs every
/// recognizer in priority order (R2: multi-finger, then contextual, then
/// single-finger) and emits GestureEvents through a non-escaping callback, with no
/// allocation per event.
///
/// Call `tick(now:)` once per frame. Time-based gestures (long press, tap timeouts)
/// fire from the tick, not from touch events.
public final class GestureEngine {
    public let config: GestureConfig
    private let state: EngineState
    private let recognizers: [Recognizer]

    public init(config: GestureConfig = .default) {
        self.config = config
        state = EngineState(config: config)
        let ordered: [Recognizer] = [
            // Multi-finger first (R2).
            MultiFingerRecognizer(), DrummingRecognizer(),
            TapRecognizer(), DoubleTapRecognizer(), TripleTapRecognizer(), RhythmRecognizer(),
            LongPressRecognizer(), HoldDragRecognizer(), HoldReleaseRecognizer(),
            // These claim a stroke, so they run before G7 on every move.
            SlingshotRecognizer(), ScribbleRecognizer(), DwellRecognizer(),
            // After-the-fact shapes, first match wins at lift.
            CircleRecognizer(), SpiralRecognizer(), ZigzagRecognizer(), FlickRecognizer(),
            DrawRecognizer(),
            LiftOffRecognizer(),   // fallback: must stay last
        ]
        // Stable sort by category. Within a category, list order is kept.
        recognizers = ordered.enumerated()
            .sorted { ($0.element.category, $0.offset) < ($1.element.category, $1.offset) }
            .map(\.element)
    }

    /// Feeds one touch event. Predicted samples are ignored: they are for drawing
    /// ahead of the finger, never for classification.
    public func process(_ e: TouchEvent, emit: (GestureEvent) -> Void) {
        guard !e.isPredicted else { return }
        let i = Int(e.touchID) & 63
        state.now = max(state.now, e.timestamp)
        switch e.phase {
        case .began:
            let wasSingle = state.fingersDown == 1
            state.begin(i, e)
            if e.kind == .finger && state.fingersDown > 1 && wasSingle {
                for j in 0..<state.tracks.count where j != i && state.tracks[j].active {
                    for r in recognizers { r.yieldToMultiFinger(j, state, emit) }
                }
            }
            for r in recognizers { r.began(i, state, emit) }
        case .moved:
            guard state.tracks[i].active else { return }
            state.move(i, e)
            for r in recognizers { r.moved(i, state, emit) }
        case .ended:
            guard state.tracks[i].active else { return }
            state.touchLift(i, e)
            for r in recognizers { r.ended(i, state, emit) }
            state.end(i)
        case .cancelled:
            guard state.tracks[i].active else { return }
            for r in recognizers { r.cancelled(i, state, emit) }
            state.end(i)
        }
    }

    /// Advances time-based recognizers. `now` uses the same clock as touch timestamps.
    public func tick(now: Double, emit: (GestureEvent) -> Void) {
        state.now = max(state.now, now)
        for r in recognizers { r.tick(state, emit) }
    }

    /// Number of fingers currently down (Pencil excluded).
    public var fingersDown: Int { state.fingersDown }
}
