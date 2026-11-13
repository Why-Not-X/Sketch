import Foundation
import ResponseMapping

/// One effect quad for the GPU. Matches `EffectInstance` in ShaderSource.swift (44 bytes).
struct EffectInstance {
    var x: Float
    var y: Float
    var radius: Float
    var thickness: Float
    var alpha: Float
    /// 0 ring, 1 soft disc, 2 bright dot, 3 glowing line from (x, y) to (x2, y2).
    var shape: Float
    var r: Float
    var g: Float
    var b: Float
    var x2: Float = 0
    var y2: Float = 0
}

/// One GPU particle. Matches `Particle` in ShaderSource.swift (64 bytes). Motion is
/// analytic, so the GPU animates it with no per-frame CPU work:
/// mode 0: origin + v·(1−e^(−drag·t))/drag. Mode 1: spiral around the origin, with
/// (vx, vy) = (start radius, start angle), p1 = end radius, p2 = angular speed.
struct Particle {
    var ox: Float, oy: Float
    var vx: Float, vy: Float
    var t0: Float
    var life: Float
    var size: Float
    var drag: Float
    var alpha: Float
    var r: Float, g: Float, b: Float
    var mode: Float = 0
    var p1: Float = 0
    var p2: Float = 0
    var pad: Float = 0
}

/// Executes visual commands: keeps live effects, applies the shared lifetime rule,
/// and writes particles into the renderer's shared particle buffer.
final class EffectSystem {
    static let maxEffects = 256

    private struct Live {
        var s: EffectSpawn
        var born: Double
        var releasedAt: Double?
        var lastEmit: Double
        /// Comet state, and the last emit position for trails.
        var px: Float = 0, py: Float = 0, vx: Float = 0, vy: Float = 0
        /// Arc path in points (G12).
        var path: [SIMD2<Float>] = []
        /// Where the tether was when released, for the snap-back.
        var relX: Float = 0, relY: Float = 0
    }

    private var effects: [Live] = []
    private let theme: Theme
    private let timeBase: Double
    private let particles: UnsafeMutablePointer<Particle>
    let particleCapacity: Int
    private var nextParticle = 0
    private(set) var particlesSpawned = 0
    private var lastFrame: Double = 0

    /// Canvas size in points, for comet bounces.
    var bounds: (w: Float, h: Float) = (0, 0)
    /// Path the next `.arc` spawn follows (set by the canvas just before mapping G12).
    var pathForNextSpawn: [SIMD2<Float>] = []

    init(theme: Theme, particleBuffer: UnsafeMutableRawPointer, particleCapacity: Int, timeBase: Double) {
        self.theme = theme
        self.particleCapacity = particleCapacity
        self.particles = particleBuffer.bindMemory(to: Particle.self, capacity: particleCapacity)
        self.timeBase = timeBase
        effects.reserveCapacity(Self.maxEffects)
        for i in 0..<particleCapacity {
            particles[i] = Particle(ox: 0, oy: 0, vx: 0, vy: 0, t0: -1e9, life: 0, size: 0, drag: 1, alpha: 0, r: 0, g: 0, b: 0)
        }
    }

    var particleDrawCount: Int { min(particlesSpawned, particleCapacity) }
    var liveEffectCount: Int { effects.count }

    func gpuTime(_ now: Double) -> Float { Float(now - timeBase) }

    // MARK: Commands

    func apply(_ c: EffectCommand, now: Double) {
        switch c {
        case .spawn(let s):
            if s.key != 0 { effects.removeAll { $0.s.key == s.key } }
            if effects.count >= Self.maxEffects { effects.removeFirst() }   // oldest first (R4)
            var live = Live(s: s, born: now, releasedAt: nil, lastEmit: now, px: s.x, py: s.y)
            switch s.kind {
            case .burst: spawnBurst(s, now: now)
            case .launch: spawnLaunch(s, now: now)
            case .vortex: spawnVortex(s, now: now)
            case .comet:
                let v = s.speed * 0.6
                live.vx = s.directionX * v; live.vy = s.directionY * v
            case .arc:
                live.path = downsample(pathForNextSpawn, to: 48)
                pathForNextSpawn.removeAll()
                spawnArcSparks(live.path, s, now: now)
            default: break
            }
            effects.append(live)
        case .update(let key, let x, let y, let radius, let intensity):
            for i in effects.indices where effects[i].s.key == key {
                effects[i].s.x = x; effects[i].s.y = y
                effects[i].s.radius = radius; effects[i].s.intensity = intensity
            }
        case .release(let key):
            for i in effects.indices where effects[i].s.key == key && effects[i].releasedAt == nil {
                effects[i].releasedAt = now
                effects[i].relX = effects[i].s.x; effects[i].relY = effects[i].s.y
            }
        }
    }

    /// G9: erased ink dissolves into particles drifting upward, styled by the live
    /// dissolve effect (if a scribble is running).
    func emitDissolve(_ points: [SIMD2<Float>], now: Double) {
        guard !points.isEmpty, let style = effects.last(where: { $0.s.kind == .dissolve && $0.releasedAt == nil })?.s else { return }
        let c = theme.color(style.color)
        let perPoint = max(1, style.count)
        let stride = max(1, points.count * perPoint / 90)   // at most ~90 particles per call
        let life = Float(style.duration ?? 1)
        var k = 0
        for p in points {
            for _ in 0..<perPoint {
                k += 1
                if k % stride != 0 { continue }
                emit(Particle(ox: p.x + Float.random(in: -3...3), oy: p.y + Float.random(in: -3...3),
                              vx: Float.random(in: -25...25), vy: Float.random(in: -80 ... -30), t0: gpuTime(now),
                              life: life * Float.random(in: 0.6...1), size: Float.random(in: 2.5...4.5),
                              drag: 0.8, alpha: style.intensity, r: c.r, g: c.g, b: c.b))
            }
        }
    }

    // MARK: Per frame

    func frame(now: Double, into out: inout [EffectInstance]) {
        let dt = Float(lastFrame > 0 ? min(0.05, now - lastFrame) : 0)
        lastFrame = now
        var i = 0
        while i < effects.count {
            let e = effects[i]
            let s = e.s
            let age = now - e.born - s.delay
            let releasedAge = e.releasedAt.map { $0 - e.born - s.delay }
            // A released tether lives only for its snap-back.
            if s.kind == .tether, let r = releasedAge, age - r > 0.2 {
                effects.remove(at: i); continue
            }
            if age >= 0 && !Lifetime.isAlive(age: age, life: s.duration, releasedAt: releasedAge) {
                effects.remove(at: i); continue
            }
            let index = i
            i += 1
            guard age >= 0 else { continue }
            let op = Lifetime.opacity(age: age, life: s.duration, releasedAt: releasedAge)
            let p = Float(s.duration.map { age / $0 } ?? min(1, age / 0.6))
            let c = theme.color(s.color)
            let a = s.intensity * op

            func add(_ x: Float, _ y: Float, _ r: Float, _ th: Float, _ alpha: Float, _ shape: Float,
                     x2: Float = 0, y2: Float = 0) {
                out.append(EffectInstance(x: x, y: y, radius: r, thickness: th, alpha: alpha,
                                          shape: shape, r: c.r, g: c.g, b: c.b, x2: x2, y2: y2))
            }

            switch s.kind {
            case .ring:
                add(s.x, s.y, s.startRadius + (s.radius - s.startRadius) * s.easing.apply(p), s.thickness, a, 0)
            case .shockwave:
                add(s.x, s.y, s.startRadius + (s.radius - s.startRadius) * s.easing.apply(p), s.thickness * (1 + p), a, 0)
            case .pulse:
                let period = s.tempo > 0 ? 1 / Double(s.tempo) : 1
                let n = (age / period).rounded(.down)
                let ph = Float(age / period - n)
                add(s.x, s.y, s.startRadius + (s.radius - s.startRadius) * Easing.easeOut.apply(ph),
                    s.thickness, a * Float(pow(0.9, n)) * (1 - ph), 0)
            case .dot:
                add(s.x, s.y, s.radius, 0, a, 2)
            case .flash:
                add(s.x, s.y, s.radius * (0.6 + 0.4 * p), 0, a, 1)
            case .halo:
                add(s.x, s.y, s.startRadius + (s.radius - s.startRadius) * s.easing.apply(p), 0, a, 1)
            case .orb:
                let grow = Easing.easeOut.apply(Float(age / 0.5))
                let breathe = 1 + 0.06 * Float(sin(2 * Double.pi * 0.6 * age))
                let r = (s.startRadius + (s.radius - s.startRadius) * grow) * breathe
                add(s.x, s.y, r, 0, a, 1)
                add(s.x, s.y, max(4, r * 0.18), 0, a * 0.7, 2)
            case .motesInward:
                if e.releasedAt == nil { emitMotes(index: index, now: now) }
            case .trail:
                if e.releasedAt == nil { emitTrail(index: index, now: now) }
            case .comet:
                stepComet(index: index, dt: dt, now: now)
                let q = effects[index]
                add(q.px, q.py, s.radius * 3, 0, a * 0.6, 1)
                add(q.px, q.py, s.radius, 0, a, 2)
            case .tether:
                var ex = s.x, ey = s.y
                if let r = releasedAge {
                    let k = Easing.easeOut.apply(Float((age - r) / 0.15))
                    ex = e.relX + (s.originX - e.relX) * k
                    ey = e.relY + (s.originY - e.relY) * k
                }
                add(s.originX, s.originY, 0, s.thickness, s.intensity, 3, x2: ex, y2: ey)
                add(s.originX, s.originY, 6, 0, s.intensity, 2)
            case .arc:
                drawArc(e.path, s, alpha: a, into: &out, color: c)
            case .burst, .launch, .vortex, .dissolve, .blot:
                break   // particles only, a style holder, or ink handled by the canvas
            }
        }
    }

    // MARK: Effect helpers

    private func stepComet(index: Int, dt: Float, now: Double) {
        guard dt > 0 else { return }
        var q = effects[index]
        let drag = exp(-1.1 * dt)
        q.vx *= drag; q.vy *= drag
        q.px += q.vx * dt; q.py += q.vy * dt
        let r = q.s.radius
        // Soft bounces off the screen edges (a light Tick haptic arrives with M6).
        if bounds.w > 0 {
            if q.px < r { q.px = r; q.vx = abs(q.vx) * 0.7 }
            if q.px > bounds.w - r { q.px = bounds.w - r; q.vx = -abs(q.vx) * 0.7 }
            if q.py < r { q.py = r; q.vy = abs(q.vy) * 0.7 }
            if q.py > bounds.h - r { q.py = bounds.h - r; q.vy = -abs(q.vy) * 0.7 }
        }
        effects[index] = q
        let rate = Double(max(1, q.s.count))
        let due = Int((now - q.lastEmit) * rate)
        guard due > 0 else { return }
        effects[index].lastEmit += Double(due) / rate
        let c = theme.color(q.s.color)
        let op = Lifetime.opacity(age: now - q.born, life: q.s.duration)
        for _ in 0..<min(due, 6) {
            emit(Particle(ox: q.px, oy: q.py, vx: -q.vx * 0.05 + Float.random(in: -12...12),
                          vy: -q.vy * 0.05 + Float.random(in: -12...12), t0: gpuTime(now), life: 0.55,
                          size: Float.random(in: 3...6), drag: 2, alpha: q.s.intensity * op * 0.8,
                          r: c.r, g: c.g, b: c.b))
        }
    }

    private func drawArc(_ path: [SIMD2<Float>], _ s: EffectSpawn, alpha: Float, into out: inout [EffectInstance], color c: RGBA) {
        guard path.count >= 2 else { return }
        // Fresh jitter every frame makes the arc flicker and crackle.
        let flicker = alpha * Float.random(in: 0.45...1)
        var prev = path[0]
        for k in 1..<path.count {
            var q = path[k]
            if k < path.count - 1 {
                let d = path[k + 1] - path[k - 1]
                let len = max(1e-3, (d.x * d.x + d.y * d.y).squareRoot())
                let j = Float.random(in: -6...6)
                q += SIMD2(-d.y / len * j, d.x / len * j)
            }
            out.append(EffectInstance(x: prev.x, y: prev.y, radius: 0, thickness: s.thickness, alpha: flicker,
                                      shape: 3, r: c.r, g: c.g, b: c.b, x2: q.x, y2: q.y))
            if Int.random(in: 0..<7) == 0 {   // small branching spark
                let ang = Float.random(in: 0..<(2 * .pi)), l = Float.random(in: 8...18)
                out.append(EffectInstance(x: q.x, y: q.y, radius: 0, thickness: s.thickness * 0.6, alpha: flicker * 0.7,
                                          shape: 3, r: c.r, g: c.g, b: c.b, x2: q.x + cos(ang) * l, y2: q.y + sin(ang) * l))
            }
            prev = q
        }
    }

    private func downsample(_ path: [SIMD2<Float>], to n: Int) -> [SIMD2<Float>] {
        guard path.count > n else { return path }
        return (0..<n).map { path[$0 * (path.count - 1) / (n - 1)] }
    }

    // MARK: Particles

    private func spawnBurst(_ s: EffectSpawn, now: Double) {
        let life = Float(s.duration ?? 1.5)
        let drag: Float = 2.5
        let reach = drag / (1 - exp(-drag * life))
        let c = theme.color(s.color)
        let t0 = gpuTime(now + s.delay)
        for k in 0..<max(1, s.count) {
            let angle = (Float(k) + Float.random(in: 0..<0.8)) / Float(max(1, s.count)) * 2 * .pi
            let v = s.radius * reach * Float.random(in: 0.55...1.0)
            emit(Particle(ox: s.x, oy: s.y, vx: cos(angle) * v, vy: sin(angle) * v, t0: t0,
                          life: life * Float.random(in: 0.7...1.0), size: Float.random(in: 3...6),
                          drag: drag, alpha: min(1.5, s.intensity), r: c.r, g: c.g, b: c.b))
        }
    }

    private func spawnArcSparks(_ path: [SIMD2<Float>], _ s: EffectSpawn, now: Double) {
        guard !path.isEmpty else { return }
        let c = theme.color(s.color)
        for _ in 0..<min(24, path.count) {
            let q = path[Int.random(in: 0..<path.count)]
            let ang = Float.random(in: 0..<(2 * .pi)), v = Float.random(in: 60...180)
            emit(Particle(ox: q.x, oy: q.y, vx: cos(ang) * v, vy: sin(ang) * v, t0: gpuTime(now),
                          life: Float.random(in: 0.25...0.6), size: Float.random(in: 2...3.5), drag: 4,
                          alpha: s.intensity, r: c.r, g: c.g, b: c.b))
        }
    }

    /// G13: particles fly from the release point toward the anchor.
    private func spawnLaunch(_ s: EffectSpawn, now: Double) {
        let dx = s.originX - s.x, dy = s.originY - s.y
        let base = atan2(dy, dx)
        let life = Float(s.duration ?? 1.2)
        let drag: Float = 2
        let reach = drag / (1 - exp(-drag * life))
        let c = theme.color(s.color)
        for _ in 0..<max(1, s.count) {
            let ang = base + Float.random(in: -0.3...0.3)
            let v = s.radius * reach * Float.random(in: 0.6...1.1)
            emit(Particle(ox: s.x, oy: s.y, vx: cos(ang) * v, vy: sin(ang) * v, t0: gpuTime(now),
                          life: life * Float.random(in: 0.7...1), size: Float.random(in: 3...5.5), drag: drag,
                          alpha: s.intensity, r: c.r, g: c.g, b: c.b))
        }
    }

    /// G11: inward (magnitude > 0) particles spiral into the center; outward ones swirl away.
    private func spawnVortex(_ s: EffectSpawn, now: Double) {
        let inward = s.magnitude >= 0
        let life = Float(s.duration ?? 1.2)
        let c = theme.color(s.color)
        for _ in 0..<max(1, s.count) {
            let r0 = inward ? s.radius * Float.random(in: 0.35...1) : Float.random(in: 0...12)
            let r1 = inward ? s.radius * 0.02 : s.radius * Float.random(in: 0.6...1.2)
            let spin = (inward ? Float.random(in: 5...8) : Float.random(in: 2.5...4.5))
            emit(Particle(ox: s.x, oy: s.y, vx: r0, vy: Float.random(in: 0..<(2 * .pi)), t0: gpuTime(now),
                          life: life * Float.random(in: 0.75...1), size: Float.random(in: 2.5...5), drag: 1,
                          alpha: s.intensity, r: c.r, g: c.g, b: c.b, mode: 1, p1: r1, p2: spin))
        }
    }

    private func emitMotes(index: Int, now: Double) {
        let s = effects[index].s
        let rate = Double(max(1, s.count))
        let due = Int((now - effects[index].lastEmit) * rate)
        guard due > 0 else { return }
        effects[index].lastEmit += Double(due) / rate
        let c = theme.color(s.color)
        let life: Float = 1.2, drag: Float = 2
        let reach = drag / (1 - exp(-drag * life))
        for _ in 0..<min(due, 8) {
            let angle = Float.random(in: 0..<(2 * .pi))
            let d = s.radius * Float.random(in: 0.7...1.2)
            let v = d * 0.9 * reach
            emit(Particle(ox: s.x + cos(angle) * d, oy: s.y + sin(angle) * d,
                          vx: -cos(angle) * v, vy: -sin(angle) * v, t0: gpuTime(now),
                          life: life, size: 2.5, drag: drag, alpha: s.intensity, r: c.r, g: c.g, b: c.b))
        }
    }

    /// G14: drops short-lived glow particles behind the moving orb.
    private func emitTrail(index: Int, now: Double) {
        let s = effects[index].s
        let rate = Double(max(1, s.count))
        let due = Int((now - effects[index].lastEmit) * rate)
        guard due > 0 else { return }
        effects[index].lastEmit += Double(due) / rate
        let c = theme.color(s.color)
        let lx = effects[index].px, ly = effects[index].py
        guard hypot(s.x - lx, s.y - ly) > 0.5 else { return }
        for k in 0..<min(due, 6) {
            let f = Float(k + 1) / Float(min(due, 6))
            emit(Particle(ox: lx + (s.x - lx) * f, oy: ly + (s.y - ly) * f, vx: 0, vy: 0, t0: gpuTime(now),
                          life: 0.7, size: s.radius, drag: 1, alpha: s.intensity, r: c.r, g: c.g, b: c.b))
        }
        effects[index].px = s.x; effects[index].py = s.y
    }

    /// Writes into the ring buffer. At the cap the oldest particle is overwritten (R4).
    /// A slot may be rewritten while an in-flight frame reads it; the worst case is one
    /// particle drawn in a mixed state for one frame.
    private func emit(_ p: Particle) {
        particles[nextParticle] = p
        nextParticle = (nextParticle + 1) % particleCapacity
        particlesSpawned += 1
    }
}
