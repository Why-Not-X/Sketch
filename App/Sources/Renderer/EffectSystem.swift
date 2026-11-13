import Foundation
import ResponseMapping

/// One effect quad for the GPU. Matches `EffectInstance` in ShaderSource.swift (36 bytes).
struct EffectInstance {
    var x: Float
    var y: Float
    var radius: Float
    var thickness: Float
    var alpha: Float
    /// 0 ring, 1 soft disc, 2 bright dot.
    var shape: Float
    var r: Float
    var g: Float
    var b: Float
}

/// One GPU particle. Matches `Particle` in ShaderSource.swift (48 bytes). Motion is
/// analytic (origin + v·(1−e^(−drag·t))/drag), so the GPU animates it with no
/// per-frame CPU work.
struct Particle {
    var ox: Float, oy: Float
    var vx: Float, vy: Float
    var t0: Float
    var life: Float
    var size: Float
    var drag: Float
    var alpha: Float
    var r: Float, g: Float, b: Float
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
    }

    private var effects: [Live] = []
    private let theme: Theme
    private let timeBase: Double
    private let particles: UnsafeMutablePointer<Particle>
    let particleCapacity: Int
    private var nextParticle = 0
    private(set) var particlesSpawned = 0

    init(theme: Theme, particleBuffer: UnsafeMutableRawPointer, particleCapacity: Int, timeBase: Double) {
        self.theme = theme
        self.particleCapacity = particleCapacity
        self.particles = particleBuffer.bindMemory(to: Particle.self, capacity: particleCapacity)
        self.timeBase = timeBase
        effects.reserveCapacity(Self.maxEffects)
        // Start with every slot dead.
        for i in 0..<particleCapacity { particles[i] = Particle(ox: 0, oy: 0, vx: 0, vy: 0, t0: -1e9, life: 0, size: 0, drag: 1, alpha: 0, r: 0, g: 0, b: 0) }
    }

    /// Particle slots that may hold live particles (draw count).
    var particleDrawCount: Int { min(particlesSpawned, particleCapacity) }

    var liveEffectCount: Int { effects.count }

    func gpuTime(_ now: Double) -> Float { Float(now - timeBase) }

    // MARK: Commands

    func apply(_ c: EffectCommand, now: Double) {
        switch c {
        case .spawn(let s):
            if s.key != 0 { effects.removeAll { $0.s.key == s.key } }
            if effects.count >= Self.maxEffects { effects.removeFirst() }   // oldest first (R4)
            if s.kind == .burst { spawnBurst(s, now: now) }
            effects.append(Live(s: s, born: now, releasedAt: nil, lastEmit: now))
        case .update(let key, let x, let y, let radius, let intensity):
            for i in effects.indices where effects[i].s.key == key {
                effects[i].s.x = x; effects[i].s.y = y
                effects[i].s.radius = radius; effects[i].s.intensity = intensity
            }
        case .release(let key):
            for i in effects.indices where effects[i].s.key == key && effects[i].releasedAt == nil {
                effects[i].releasedAt = now
            }
        }
    }

    // MARK: Per frame

    func frame(now: Double, into out: inout [EffectInstance]) {
        var i = 0
        while i < effects.count {
            let e = effects[i]
            let s = e.s
            let age = now - e.born - s.delay
            let releasedAge = e.releasedAt.map { $0 - e.born - s.delay }
            if age >= 0 && !Lifetime.isAlive(age: age, life: s.duration, releasedAt: releasedAge) {
                effects.remove(at: i)
                continue
            }
            i += 1
            guard age >= 0 else { continue }
            let op = Lifetime.opacity(age: age, life: s.duration, releasedAt: releasedAge)
            let p = Float(s.duration.map { age / $0 } ?? min(1, age / 0.6))
            let c = theme.color(s.color)
            let a = s.intensity * op

            func add(_ r: Float, _ th: Float, _ alpha: Float, _ shape: Float) {
                out.append(EffectInstance(x: s.x, y: s.y, radius: r, thickness: th, alpha: alpha,
                                          shape: shape, r: c.r, g: c.g, b: c.b))
            }

            switch s.kind {
            case .ring:
                add(s.startRadius + (s.radius - s.startRadius) * s.easing.apply(p), s.thickness, a, 0)
            case .shockwave:
                add(s.startRadius + (s.radius - s.startRadius) * s.easing.apply(p), s.thickness * (1 + p), a, 0)
            case .pulse:
                let period = s.tempo > 0 ? 1 / Double(s.tempo) : 1
                let n = (age / period).rounded(.down)
                let ph = Float(age / period - n)
                let dim = Float(pow(0.9, n))
                add(s.startRadius + (s.radius - s.startRadius) * Easing.easeOut.apply(ph),
                    s.thickness, a * dim * (1 - ph), 0)
            case .dot:
                add(s.radius, 0, a, 2)
            case .flash:
                add(s.radius * (0.6 + 0.4 * p), 0, a, 1)
            case .halo:
                add(s.startRadius + (s.radius - s.startRadius) * s.easing.apply(p), 0, a, 1)
            case .orb:
                let grow = Easing.easeOut.apply(Float(age / 0.5))
                let breathe = 1 + 0.06 * Float(sin(2 * Double.pi * 0.6 * age))
                let r = (s.startRadius + (s.radius - s.startRadius) * grow) * breathe
                add(r, 0, a, 1)
                add(max(4, r * 0.18), 0, a * 0.7, 2)
            case .burst:
                break   // particles only
            case .motesInward:
                if e.releasedAt == nil { emitMotes(index: i - 1, now: now) }
            }
        }
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

    /// Writes into the ring buffer. At the cap the oldest particle is overwritten (R4).
    /// A slot may be rewritten while an in-flight frame reads it; the worst case is one
    /// particle drawn in a mixed state for one frame.
    private func emit(_ p: Particle) {
        particles[nextParticle] = p
        nextParticle = (nextParticle + 1) % particleCapacity
        particlesSpawned += 1
    }
}
