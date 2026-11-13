import QuartzCore
import Metal
import CoreHaptics
import GestureEngine
import InkModel
import ResponseMapping

/// Runs the frame loop. Data flows one way:
/// input (TouchEvents) → gesture engine (GestureEvents) → response mapper
/// (effect and haptic commands) → effect system and renderer.
///
/// Ink keeps latency down: stroke points are recorded straight from touch-down, and
/// the engine's gestures decide what happens to them:
/// - G7 began: the points show as live ink. G7 ended: they become ink.
/// - G9 scribble: the stroke is hidden and erases ink under the finger (one undo).
/// - G10 circle: the stroke snaps into a clean ring.
/// - G8 flick, G12 zigzag: the stroke is consumed by the effect; one undo brings it back.
/// - G15 dwell: blots join the stroke.
final class CanvasController: NSObject, CAMetalDisplayLinkDelegate {
    let input = TouchInput()
    let latency = LatencyMonitor()

    private var renderer: MetalRenderer?
    private var effects: EffectSystem?
    private var link: CAMetalDisplayLink?
    private var palm = PalmRejection()
    private let engine = GestureEngine()
    private let mapper: ResponseMapper
    private var brush = InkBrush.default
    private var history = InkHistory()
    private var inkDirty = false
    private var space = InkSpace(width: 1, height: 1)
    private var pixelScale: Float = 2

    // Per touch slot. Pre-allocated.
    private let builders: [StrokeBuilder] = (0..<32).map { _ in StrokeBuilder() }
    private var drawing = [Bool](repeating: false, count: 32)
    private var sparkle = [SIMD2<Float>](repeating: .zero, count: 32)
    private var scribbling = [Bool](repeating: false, count: 32)
    private var scribbleCheckpointed = [Bool](repeating: false, count: 32)
    private var consumed = [Bool](repeating: false, count: 32)
    private var snapCircle = [SIMD3<Float>?](repeating: nil, count: 32)   // center x, y, radius (points)
    private var blots = [[InkBlot]](repeating: [], count: 32)
    private var liveBlot = [InkBlot?](repeating: nil, count: 32)            // points
    private var blotKey = [UInt64](repeating: 0, count: 32)
    private var nextStrokeID: UInt32 = 1

    // Per-frame scratch, reused.
    private var liveVertices: [InkVertex] = []
    private var finishedVertices: [InkVertex] = []
    private var rebuildVertices: [InkVertex] = []
    private var sprites: [SpriteVertex] = []
    private var effectInstances: [EffectInstance] = []
    private var erased: [SIMD2<Float>] = []
    private var frameNow: Double = 0

    /// Width of the G9 eraser in points, from the dissolve recipe in the response set.
    private let eraseRadius: Float
    private static let blotCoreFrac: Float = 0.62

    #if DEBUG
    private var gestureLog: [String] = []
    #endif

    override init() {
        let haptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        mapper = ResponseMapper(set: .base, hapticsAvailable: haptics)
        eraseRadius = mapper.set.response(for: .g9)?.effects.first { $0.kind == .dissolve }?.radius ?? 18
        super.init()
        liveVertices.reserveCapacity(64 * 1024)
        finishedVertices.reserveCapacity(64 * 1024)
        sprites.reserveCapacity(64)
        effectInstances.reserveCapacity(1024)
        erased.reserveCapacity(1024)
    }

    func attach(to layer: CAMetalLayer) {
        guard let r = MetalRenderer(layer: layer, theme: mapper.set.theme) else { return }
        renderer = r
        effects = EffectSystem(theme: mapper.set.theme, particleBuffer: r.particleBuffer.contents(),
                               particleCapacity: MetalRenderer.particleCapacity, timeBase: r.startTime)
        r.warmUp()
    }

    func start() {
        guard link == nil, let layer = renderer?.layer else { return }
        let link = CAMetalDisplayLink(metalLayer: layer)
        link.delegate = self
        // Ask for one frame of latency: the drawable is presented on the next vsync.
        link.preferredFrameLatency = 1
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        #if DEBUG
        DemoScript.startIfRequested(input: input, size: { [weak self] in
            guard let s = self?.space else { return (0, 0) }
            return (s.width, s.height)
        })
        #endif
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    func resize(to size: CGSize, scale: Float) {
        space = InkSpace(width: Float(size.width), height: Float(size.height))
        pixelScale = scale
        effects?.bounds = (space.width, space.height)
    }

    /// Reverses the last ink change (D4). The Undo button arrives with M7.
    func undo() {
        if history.undo() { inkDirty = true }
    }

    // MARK: Frame

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        guard let renderer, let effects else { return }
        frameNow = CACurrentMediaTime()

        var newestRealTouch: Double = 0
        input.drain { e in
            guard palm.accept(e) else { return }
            if !e.isPredicted { newestRealTouch = max(newestRealTouch, e.timestamp) }
            // On lift the engine decides first (shape, flick), then the ink is settled.
            if e.phase == .ended || e.phase == .cancelled {
                engine.process(e) { handle($0) }
                processInk(e)
                if !e.isPredicted { resetSlot(Int(e.touchID)) }
            } else {
                processInk(e)
                engine.process(e) { handle($0) }
            }
        }
        engine.tick(now: frameNow) { handle($0) }

        if !erased.isEmpty {
            effects.emitDissolve(erased.map { space.toPoints($0) }, now: frameNow)
            erased.removeAll(keepingCapacity: true)
        }
        if inkDirty {
            rebuildVertices.removeAll(keepingCapacity: true)
            for stroke in history.document.strokes { tessellate(stroke, into: &rebuildVertices) }
            renderer.resetCommitted(rebuildVertices)
            finishedVertices.removeAll(keepingCapacity: true)
            inkDirty = false
        } else if !finishedVertices.isEmpty {
            renderer.appendCommitted(finishedVertices)
            finishedVertices.removeAll(keepingCapacity: true)
        }

        liveVertices.removeAll(keepingCapacity: true)
        sprites.removeAll(keepingCapacity: true)
        let theme = mapper.set.theme
        for i in 0..<builders.count {
            for b in blots[i] { BlotTessellator.append(b, coreFrac: Self.blotCoreFrac, into: &liveVertices) }
            if let lb = liveBlot[i] { BlotTessellator.append(toUnits(lb), coreFrac: Self.blotCoreFrac, into: &liveVertices) }
            guard drawing[i] else { continue }
            let b = builders[i]
            guard b.isActive, let head = b.head else { continue }
            StrokeTessellator.append(b.points, taperStart: true, taperEnd: false,
                                     taperLength: brush.taperLength / space.unit,
                                     taperMinFactor: brush.taperMinFactor,
                                     glowFactor: brush.glowWidthFactor, into: &liveVertices)
            // G7: the head sparkle trails slightly behind the finger.
            sparkle[i] += (head - sparkle[i]) * (1 - theme.sparkleLag)
            sprites.append(SpriteVertex(x: sparkle[i].x, y: sparkle[i].y, size: theme.sparkleSize, alpha: 1))
        }

        effectInstances.removeAll(keepingCapacity: true)
        effects.frame(now: frameNow, into: &effectInstances)

        let pendingDowns = latency.takePendingDowns()
        let content = FrameContent(live: liveVertices, sprites: sprites, effects: effectInstances,
                                   particleCount: effects.particleDrawCount,
                                   time: effects.gpuTime(frameNow), space: space, pixelScale: pixelScale)
        renderer.render(drawable: update.drawable, content) { [latency] presentedTime in
            latency.framePresented(at: presentedTime, downs: pendingDowns, newestMove: newestRealTouch)
        }
    }

    // MARK: Gestures → ink and responses

    private func handle(_ g: GestureEvent) {
        let i = Int(g.touchID)
        let slot = i < builders.count
        switch (g.gesture, g.phase) {
        case (.g7, .began) where slot:
            drawing[i] = true
            sparkle[i] = builders[i].head ?? .zero
        case (.g7, .cancelled) where slot:
            drawing[i] = false
        case (.g9, .began) where slot:
            scribbling[i] = true
            // Erase along the scribble so far; the rest is erased as the finger moves.
            let pts = builders[i].points
            for k in pts.indices { erase(at: SIMD2(pts[k].x, pts[k].y), slot: i) }
        case (.g9, .ended), (.g9, .cancelled):
            if slot { scribbling[i] = false }
        case (.g10, .fired) where slot:
            snapCircle[i] = SIMD3(g.x, g.y, g.size)
        case (.g8, .fired) where slot, (.g12, .fired) where slot:
            consumed[i] = true
            if g.gesture == .g12 {
                effects?.pathForNextSpawn = builders[i].points.map { space.toPoints(SIMD2($0.x, $0.y)) }
            }
        default:
            break
        }
        mapper.map(g, visual: { applyVisual($0, slot: slot ? i : nil) },
                   haptic: { _ in /* Core Haptics layer arrives in M6 */ })
        #if DEBUG
        logGesture(g)
        #endif
    }

    /// Routes visual commands. G15 blots are ink, so they stay on the canvas side.
    private func applyVisual(_ c: EffectCommand, slot: Int?) {
        switch c {
        case .spawn(let s) where s.kind == .blot:
            if let i = slot {
                liveBlot[i] = InkBlot(x: s.x, y: s.y, radius: s.radius)
                blotKey[i] = s.key
            }
        case .update(let key, _, _, let radius, _) where slot.map({ blotKey[$0] == key && key != 0 }) == true:
            if let i = slot { liveBlot[i]?.radius = radius }
        case .release(let key) where slot.map({ blotKey[$0] == key && key != 0 }) == true:
            if let i = slot, let b = liveBlot[i] {
                blots[i].append(toUnits(b))
                liveBlot[i] = nil
                blotKey[i] = 0
            }
        default:
            effects?.apply(c, now: frameNow)
        }
    }

    // MARK: Ink

    private func processInk(_ e: TouchEvent) {
        let i = Int(e.touchID)
        guard i < builders.count else { return }
        let b = builders[i]
        let sample = StrokeSample(x: e.x, y: e.y, t: e.timestamp, force: e.force,
                                  altitude: e.altitude, isPencil: e.kind == .pencil)
        switch e.phase {
        case .began:
            b.begin(id: nextStrokeID, sample: sample, space: space, brush: brush)
            nextStrokeID &+= 1
        case .moved:
            if e.isPredicted {
                b.addPredicted(sample)
            } else {
                b.addReal(sample)
                if scribbling[i] { erase(at: space.toUnits(x: e.x, y: e.y), slot: i) }
            }
        case .ended:
            guard b.isActive else { return }
            var stroke = b.finish(final: sample)
            if let lb = liveBlot[i] { blots[i].append(toUnits(lb)); liveBlot[i] = nil }
            stroke.blots = blots[i]
            guard drawing[i], stroke.points.count >= 2 else { return }
            if let c = snapCircle[i] {
                // G10: the loop snaps into a clean ring that stays as ink.
                let center = space.toUnits(x: c.x, y: c.y)
                let first = stroke.points[0]
                let width = stroke.points.reduce(0) { $0 + $1.width } / Float(stroke.points.count)
                var ring = Stroke.circle(id: stroke.id, centerX: center.x, centerY: center.y,
                                         radius: c.z / space.unit, width: width,
                                         startAngle: atan2(first.y - center.y, first.x - center.x), t: first.t)
                ring.blots = stroke.blots
                stroke = ring
            }
            if consumed[i] {
                // G8/G12 used the stroke up. It never becomes ink, but one undo brings it back (R3).
                var withStroke = history.document
                withStroke.append(stroke)
                history.pushUndoState(withStroke)
            } else {
                history.record { $0.append(stroke) }
                tessellate(stroke, into: &finishedVertices)
            }
        case .cancelled:
            b.cancel()
        }
    }

    private func resetSlot(_ i: Int) {
        guard i < builders.count else { return }
        drawing[i] = false
        scribbling[i] = false
        scribbleCheckpointed[i] = false
        consumed[i] = false
        snapCircle[i] = nil
        blots[i].removeAll(keepingCapacity: true)
        liveBlot[i] = nil
        blotKey[i] = 0
    }

    /// G9: erases ink under the scribble. The first erase of a scribble saves an undo
    /// point, so the whole scribble undoes in one step.
    private func erase(at p: SIMD2<Float>, slot i: Int) {
        var trial = history.document
        guard trial.erase(x: p.x, y: p.y, radius: eraseRadius / space.unit, erased: &erased) else { return }
        if !scribbleCheckpointed[i] {
            history.checkpoint()
            scribbleCheckpointed[i] = true
        }
        history.continueChange { $0 = trial }
        inkDirty = true
    }

    private func tessellate(_ stroke: Stroke, into out: inout [InkVertex]) {
        StrokeTessellator.append(stroke.points, taperStart: true, taperEnd: true,
                                 taperLength: brush.taperLength / space.unit,
                                 taperMinFactor: brush.taperMinFactor,
                                 glowFactor: brush.glowWidthFactor, into: &out)
        for b in stroke.blots { BlotTessellator.append(b, coreFrac: Self.blotCoreFrac, into: &out) }
    }

    private func toUnits(_ b: InkBlot) -> InkBlot {
        let c = space.toUnits(x: b.x, y: b.y)
        return InkBlot(x: c.x, y: c.y, radius: b.radius / space.unit)
    }

    #if DEBUG
    private func logGesture(_ g: GestureEvent) {
        let mark: String
        switch g.phase {
        case .began: mark = "↓"
        case .fired: mark = "!"
        case .ended: mark = "✓"
        case .cancelled: mark = "×"
        case .changed: return
        }
        gestureLog.append(g.gesture.rawValue + mark)
        if gestureLog.count > 10 { gestureLog.removeFirst() }
        latency.note = "gestures: " + gestureLog.joined(separator: " ")
            + String(format: "\nfx %d  particles %d  undo %@", effects?.liveEffectCount ?? 0,
                     effects?.particleDrawCount ?? 0, history.canUndo ? "yes" : "no")
    }
    #endif
}
