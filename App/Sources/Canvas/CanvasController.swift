import QuartzCore
import Metal
import GestureEngine
import InkModel
import ResponseMapping
import os

#if DEBUG
private let gestureLogger = Logger(subsystem: "TouchWhiteboard", category: "gestures")
#endif

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
final class CanvasController: NSObject, CAMetalDisplayLinkDelegate, InkHitTesting {
    let input = TouchInput()
    let latency = LatencyMonitor()

    private var renderer: MetalRenderer?
    private var effects: EffectSystem?
    private var link: CAMetalDisplayLink?
    private var palm = PalmRejection()
    private let engine = GestureEngine()
    private let mapper: ResponseMapper
    /// Nil where the hardware has no haptics (iPad, Simulator): visuals are boosted instead (R5).
    private let haptics: HapticsPlayer?
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

    // G17 ribbon (canvas units).
    private var ribbonA: [InkPoint] = []
    private var ribbonB: [InkPoint] = []
    private var ribbonLive = false
    private var ribbonAlpha: Float = 0.3
    // G26 rake: its lines are committed together as one undo step.
    private var rakeMembers = Set<Int>()
    private var rakeStrokes: [Stroke] = []
    private var rakeConsumed = false
    // G24: the ink gathered into the orb, restored by a spread.
    private var gathered: InkDocument?
    // G29: shapes whose fill is saved with the stroke at lift.
    private var fillShape = [Bool](repeating: false, count: 32)
    private var fillAlpha: Float = 0.16
    // Stroke bounds for hit tests, rebuilt when the ink changes.
    private var inkIndex = InkIndex()
    private var inkIndexVersion: UInt64 = .max
    // G32 idle: throttled frame rate, shimmer, and dimming after 30 s.
    private var idle = false
    private var dim: Float = 1, dimTarget: Float = 1
    private var shimmer: Float = 0
    private static let activeRate = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
    private static let idleRate = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)

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
        let set = ResponseSet.base
        haptics = HapticsPlayer(palette: set.hapticPalette)   // warmed at launch
        mapper = ResponseMapper(set: set, hapticsAvailable: haptics != nil)
        eraseRadius = mapper.set.response(for: .g9)?.effects.first { $0.kind == .dissolve }?.radius ?? 18
        super.init()
        engine.ink = self
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
        // G8: a light tick on every comet bounce.
        effects?.onBounce = { [weak self] in
            guard let self, let haptics = self.haptics else { return }
            self.mapper.haptics(for: .g8, moment: .bounce) { haptics.handle($0) }
        }
        r.warmUp()
    }

    func start() {
        guard link == nil, let layer = renderer?.layer else { return }
        let link = CAMetalDisplayLink(metalLayer: layer)
        link.delegate = self
        // Ask for one frame of latency: the drawable is presented on the next vsync.
        link.preferredFrameLatency = 1
        link.preferredFrameRateRange = Self.activeRate
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
        engine.setCanvasSize(width: space.width, height: space.height)
    }

    /// Called straight from touchesBegan: leaves idle at once, so the frame after the
    /// touch is already back at full rate (R4: any touch interrupts idle instantly).
    func wake() {
        guard idle else { return }
        idle = false
        link?.preferredFrameRateRange = Self.activeRate
        dimTarget = 1
        dim = 1
    }

    // MARK: InkHitTesting (view points in, view points out)

    func hitStroke(x: Float, y: Float, radius: Float) -> StrokeHit? {
        refreshIndex()
        let p = space.toUnits(x: x, y: y)
        guard let h = history.document.hit(x: p.x, y: p.y, radius: radius / space.unit, index: inkIndex) else { return nil }
        let q = space.toPoints(SIMD2(h.x, h.y))
        return StrokeHit(strokeID: h.strokeID, x: q.x, y: q.y, along: h.along * space.unit, length: h.length * space.unit)
    }

    func crossing(x0: Float, y0: Float, x1: Float, y1: Float) -> StrokeCrossing? {
        refreshIndex()
        let a = space.toUnits(x: x0, y: y0), b = space.toUnits(x: x1, y: y1)
        guard let c = history.document.crossing(x0: a.x, y0: a.y, x1: b.x, y1: b.y, index: inkIndex) else { return nil }
        let q = space.toPoints(SIMD2(c.x, c.y))
        return StrokeCrossing(strokeID: c.strokeID, x: q.x, y: q.y, dirX: c.dirX, dirY: c.dirY)
    }

    private func refreshIndex() {
        guard inkIndexVersion != history.version else { return }
        inkIndex = InkIndex(history.document)
        inkIndexVersion = history.version
    }

    /// Reverses the last ink change (D4). The Undo button arrives with M7.
    func undo() {
        guard history.undo() else { return }
        inkDirty = true
        if gathered != nil && !history.document.isEmpty {
            // The gather was undone: the ink is back, so the orb goes.
            gathered = nil
            effects?.apply(.release(key: mapper.keyFor(.g24, slot: 9)), now: CACurrentMediaTime())
        }
    }

    // MARK: Frame

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        guard let renderer, let effects else { return }
        frameNow = CACurrentMediaTime()
        #if DEBUG
        input.deliverScripted(upTo: frameNow)
        #endif

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
        // Idle: ease the shimmer in and out, and the dimming after 30 s.
        shimmer += ((idle ? 1 : 0) - shimmer) * 0.05
        dim += (dimTarget - dim) * 0.03
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
        if ribbonLive { tessellateRibbon(ribbonA, ribbonB, into: &liveVertices) }
        for stroke in rakeStrokes { tessellate(stroke, into: &liveVertices) }
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
                                   distortions: effects.distortionBlock(),
                                   time: effects.gpuTime(frameNow), dim: dim, shimmer: shimmer,
                                   space: space, pixelScale: pixelScale)
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
        case (.g17, .began):
            ribbonA.removeAll(); ribbonB.removeAll()
            ribbonLive = true
            extendRibbon(g)
        case (.g17, .changed):
            extendRibbon(g)
        case (.g17, .ended), (.g17, .cancelled):
            commitRibbon()
        case (.g26, .began):
            // Each rake finger's points, recorded since touch-down, now show as ink.
            rakeMembers = Set(g.touchIDs.map(Int.init))
            rakeStrokes.removeAll()
            rakeConsumed = false
            for m in rakeMembers where m < builders.count {
                drawing[m] = true
                sparkle[m] = builders[m].head ?? .zero
            }
        case (.g22, .fired):
            rakeConsumed = true   // the quick rake was a swipe: its lines go (one undo brings them back)
        case (.g27, .began):
            // The pluck vibrates the stroke that was touched.
            if let stroke = history.document.strokes.first(where: { $0.id == g.targetID }) {
                effects?.pathForNextSpawn = stroke.points.map { space.toPoints(SIMD2($0.x, $0.y)) }
            }
        case (.g29, .fired) where slot:
            fillShape[i] = true
        case (.g32, .began):
            idle = true
            link?.preferredFrameRateRange = Self.idleRate
        case (.g32, .changed):
            // Everything dims after about 30 s of quiet.
            dimTarget = g.magnitude > 30 ? max(0.35, 1 - (g.magnitude - 30) / 5 * 0.65) : 1
        case (.g32, .ended), (.g32, .cancelled):
            wake()
        case (.g24, .ended):
            if g.magnitude > 0 {
                if !history.document.isEmpty {
                    gathered = history.document
                    history.record { $0.removeAll() }
                    inkDirty = true
                }
            } else if let doc = gathered {
                history.record { $0 = doc }
                gathered = nil
                inkDirty = true
            }
        default:
            break
        }
        mapper.map(g, visual: { applyVisual($0, slot: slot ? i : nil) },
                   haptic: { haptics?.handle($0) })
        #if DEBUG
        logGesture(g)
        #endif
    }

    /// Routes visual commands. G15 blots are ink, so they stay on the canvas side.
    private func applyVisual(_ c: EffectCommand, slot: Int?) {
        switch c {
        case .spawn(let s) where s.kind == .ribbon:
            ribbonAlpha = s.intensity
        case .spawn(let s) where s.kind == .fill:
            fillAlpha = s.intensity
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
            guard drawing[i], stroke.points.count >= 2 else { finishRakeMember(i, nil); return }
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
            if fillShape[i] { stroke.filled = true }
            if rakeMembers.contains(i) {
                finishRakeMember(i, stroke)
            } else if consumed[i] {
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

    /// G26: collects each rake line; when the last finger lifts, all lines are
    /// committed (or consumed by a swipe) as one undo step.
    private func finishRakeMember(_ i: Int, _ stroke: Stroke?) {
        guard rakeMembers.contains(i) else { return }
        rakeMembers.remove(i)
        if let stroke { rakeStrokes.append(stroke) }
        guard rakeMembers.isEmpty, !rakeStrokes.isEmpty else { return }
        if rakeConsumed {
            var withLines = history.document
            for st in rakeStrokes { withLines.append(st) }
            history.pushUndoState(withLines)
        } else {
            history.record { doc in for st in rakeStrokes { doc.append(st) } }
            for st in rakeStrokes { tessellate(st, into: &finishedVertices) }
        }
        rakeStrokes.removeAll()
    }

    /// G17: adds the current finger pair to the ribbon when they have moved.
    private func extendRibbon(_ g: GestureEvent) {
        let a = space.toUnits(x: g.x, y: g.y), b = space.toUnits(x: g.originX, y: g.originY)
        let w = brush.baseWidth * 0.6 / space.unit
        if let last = ribbonA.last, let lastB = ribbonB.last {
            let moved = max(hypot(a.x - last.x, a.y - last.y), hypot(b.x - lastB.x, b.y - lastB.y)) * space.unit
            guard moved >= 1.5 else { return }
        }
        ribbonA.append(InkPoint(x: a.x, y: a.y, t: g.timestamp, width: w))
        ribbonB.append(InkPoint(x: b.x, y: b.y, t: g.timestamp, width: w))
    }

    private func commitRibbon() {
        ribbonLive = false
        guard ribbonA.count >= 2 else { return }
        let ribbon = Stroke(id: nextStrokeID, points: ribbonA, isPencil: false, partner: ribbonB)
        nextStrokeID &+= 1
        history.record { $0.append(ribbon) }
        tessellate(ribbon, into: &finishedVertices)
        ribbonA.removeAll(); ribbonB.removeAll()
    }

    private func tessellateRibbon(_ a: [InkPoint], _ b: [InkPoint], into out: inout [InkVertex]) {
        RibbonTessellator.appendFill(a, b, alpha: ribbonAlpha, into: &out)
        for edge in [a, b] {
            StrokeTessellator.append(edge, taperStart: true, taperEnd: true,
                                     taperLength: brush.taperLength / space.unit,
                                     taperMinFactor: brush.taperMinFactor,
                                     glowFactor: brush.glowWidthFactor, into: &out)
        }
    }

    private func resetSlot(_ i: Int) {
        guard i < builders.count else { return }
        drawing[i] = false
        scribbling[i] = false
        scribbleCheckpointed[i] = false
        consumed[i] = false
        fillShape[i] = false
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
        if let partner = stroke.partner {
            tessellateRibbon(stroke.points, partner, into: &out)
            return
        }
        if stroke.filled { FillTessellator.append(stroke.points, alpha: fillAlpha, into: &out) }
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
        gestureLogger.notice("\(g.gesture.rawValue, privacy: .public)\(mark, privacy: .public) mag \(g.magnitude, privacy: .public) speed \(Int(g.speed), privacy: .public) n \(g.fingerCount, privacy: .public)")
        if gestureLog.count > 10 { gestureLog.removeFirst() }
        latency.note = "gestures: " + gestureLog.joined(separator: " ")
            + String(format: "\nfx %d  particles %d  undo %@", effects?.liveEffectCount ?? 0,
                     effects?.particleDrawCount ?? 0, history.canUndo ? "yes" : "no")
    }
    #endif
}
