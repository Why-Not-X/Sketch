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
/// Ink is the exception that keeps latency down: stroke points are recorded straight
/// from touch-down, and the engine's G7 decides when they show and whether they are
/// kept, so the first 10 pt are never lost while the stroke is being classified.
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
    private var document = InkDocument()
    private var space = InkSpace(width: 1, height: 1)
    private var pixelScale: Float = 2

    // Pre-allocated pool of live strokes, indexed by touch slot.
    private let builders: [StrokeBuilder] = (0..<32).map { _ in StrokeBuilder() }
    /// Set by G7 began: this touch's points are ink.
    private var drawing = [Bool](repeating: false, count: 32)
    private var sparkle = [SIMD2<Float>](repeating: .zero, count: 32)
    private var nextStrokeID: UInt32 = 1

    // Per-frame scratch, reused.
    private var liveVertices: [InkVertex] = []
    private var finishedVertices: [InkVertex] = []
    private var sprites: [SpriteVertex] = []
    private var effectInstances: [EffectInstance] = []
    private var frameNow: Double = 0

    #if DEBUG
    private var gestureLog: [String] = []
    #endif

    override init() {
        let haptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        mapper = ResponseMapper(set: .base, hapticsAvailable: haptics)
        super.init()
        liveVertices.reserveCapacity(64 * 1024)
        finishedVertices.reserveCapacity(64 * 1024)
        sprites.reserveCapacity(64)
        effectInstances.reserveCapacity(1024)
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
    }

    // MARK: Frame

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        guard let renderer, let effects else { return }
        frameNow = CACurrentMediaTime()

        var newestRealTouch: Double = 0
        input.drain { e in
            guard palm.accept(e) else { return }
            if !e.isPredicted { newestRealTouch = max(newestRealTouch, e.timestamp) }
            processInk(e)
            engine.process(e) { handle($0) }
            if !e.isPredicted && (e.phase == .ended || e.phase == .cancelled), Int(e.touchID) < drawing.count {
                drawing[Int(e.touchID)] = false
            }
        }
        engine.tick(now: frameNow) { handle($0) }

        if !finishedVertices.isEmpty {
            renderer.appendCommitted(finishedVertices)
            finishedVertices.removeAll(keepingCapacity: true)
        }

        liveVertices.removeAll(keepingCapacity: true)
        sprites.removeAll(keepingCapacity: true)
        let theme = mapper.set.theme
        for i in 0..<builders.count where drawing[i] {
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

    // MARK: Gestures → responses

    private func handle(_ g: GestureEvent) {
        let i = Int(g.touchID)
        if g.gesture == .g7 && g.phase == .began && i < drawing.count {
            drawing[i] = true
            sparkle[i] = builders[i].head ?? .zero
        }
        mapper.map(g, visual: { effects?.apply($0, now: frameNow) },
                   haptic: { _ in /* Core Haptics layer arrives in M6 */ })
        #if DEBUG
        logGesture(g)
        #endif
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
            if e.isPredicted { b.addPredicted(sample) } else { b.addReal(sample) }
        case .ended:
            guard b.isActive else { return }
            let stroke = b.finish(final: sample)
            // Only touches the engine classified as G7 become ink (D1: ink stays).
            if drawing[i] && stroke.points.count >= 2 {
                document.append(stroke)
                StrokeTessellator.append(stroke.points, taperStart: true, taperEnd: true,
                                         taperLength: brush.taperLength / space.unit,
                                         taperMinFactor: brush.taperMinFactor,
                                         glowFactor: brush.glowWidthFactor, into: &finishedVertices)
            }
        case .cancelled:
            b.cancel()
        }
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
            + String(format: "\nfx %d  particles %d", effects?.liveEffectCount ?? 0, effects?.particleDrawCount ?? 0)
    }
    #endif
}
