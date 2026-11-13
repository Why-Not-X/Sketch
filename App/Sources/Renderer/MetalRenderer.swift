import Metal
import QuartzCore
import InkModel
import ResponseMapping

/// Point sprite for the stroke-head sparkle. Matches `SpriteVertex` in ShaderSource.swift.
struct SpriteVertex {
    var x: Float
    var y: Float
    /// Diameter in points.
    var size: Float
    var alpha: Float
}

/// Matches `Uniforms` in ShaderSource.swift (96 bytes).
struct Uniforms {
    var viewSize: SIMD2<Float>
    var center: SIMD2<Float>
    var unitScale: Float
    var pixelScale: Float
    var glowStrength: Float
    var time: Float
    var inkColor: SIMD4<Float>
    var glowColor: SIMD4<Float>
    var sparkleColor: SIMD4<Float>
    /// x: dim (1 = full brightness), y: idle shimmer amount.
    var extra: SIMD4<Float> = SIMD4(1, 0, 0, 0)
}

/// Matches `Distortion` in ShaderSource.swift (32 bytes).
struct Distortion {
    var x: Float, y: Float
    var radius: Float
    var strength: Float
    var kind: Float          // 0 ripple, 1 twist, 2 pull, 3 wave
    var phase: Float
    var dirX: Float, dirY: Float
}

/// Matches `DistortionBlock` in ShaderSource.swift: a count and up to 8 distortions.
struct DistortionBlock {
    static let capacity = 8
    var count: UInt32 = 0
    var pad: (UInt32, UInt32, UInt32) = (0, 0, 0)
    var d: (Distortion, Distortion, Distortion, Distortion, Distortion, Distortion, Distortion, Distortion) =
        (.zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero)

    mutating func set(_ list: [Distortion]) {
        count = UInt32(min(list.count, Self.capacity))
        withUnsafeMutableBytes(of: &d) { raw in
            let p = raw.bindMemory(to: Distortion.self)
            for k in 0..<Int(count) { p[k] = list[k] }
        }
    }
}

extension Distortion {
    static let zero = Distortion(x: 0, y: 0, radius: 0, strength: 0, kind: 0, phase: 0, dirX: 0, dirY: 0)
}

/// Everything one frame draws, gathered by the controller.
struct FrameContent {
    var live: [InkVertex]
    var sprites: [SpriteVertex]
    var effects: [EffectInstance]
    var particleCount: Int
    var distortions: DistortionBlock
    var time: Float
    /// G32: overall brightness and ink shimmer.
    var dim: Float = 1
    var shimmer: Float = 0
    var space: InkSpace
    var pixelScale: Float
}

/// Executes visual commands in Metal. Draw order: committed ink, live ink, effects,
/// particles, stroke-head sparkles. Effects and particles blend additively over the ink.
final class MetalRenderer {
    static let particleCapacity = 3000   // R4: particle cap

    let layer: CAMetalLayer
    let startTime = CACurrentMediaTime()
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let inkPipeline: MTLRenderPipelineState
    private let spritePipeline: MTLRenderPipelineState
    private let effectPipeline: MTLRenderPipelineState
    private let particlePipeline: MTLRenderPipelineState
    private let theme: Theme

    private var committed: MTLBuffer
    private var committedCount = 0
    let particleBuffer: MTLBuffer

    private static let framesInFlight = 3
    private var liveBuffers: [MTLBuffer]
    private var spriteBuffers: [MTLBuffer]
    private var effectBuffers: [MTLBuffer]
    private var frameIndex = 0
    private let inflight = DispatchSemaphore(value: MetalRenderer.framesInFlight)

    init?(layer: CAMetalLayer, theme: Theme) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: ShaderSource.code, options: nil) else { return nil }
        self.layer = layer
        self.device = device
        self.queue = queue
        self.theme = theme

        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = true

        func pipeline(_ v: String, _ f: String, additive: Bool) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: v)
            d.fragmentFunction = library.makeFunction(name: f)
            let c = d.colorAttachments[0]!
            c.pixelFormat = .bgra8Unorm
            c.isBlendingEnabled = true
            c.rgbBlendOperation = .add
            c.alphaBlendOperation = .add
            c.sourceRGBBlendFactor = .one
            c.sourceAlphaBlendFactor = .one
            c.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
            c.destinationAlphaBlendFactor = additive ? .one : .oneMinusSourceAlpha
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        guard let ink = pipeline("ink_vertex", "ink_fragment", additive: false),
              let sprite = pipeline("sprite_vertex", "sprite_fragment", additive: true),
              let effect = pipeline("effect_vertex", "effect_fragment", additive: true),
              let particle = pipeline("particle_vertex", "particle_fragment", additive: true) else { return nil }
        inkPipeline = ink
        spritePipeline = sprite
        effectPipeline = effect
        particlePipeline = particle

        let stride = MemoryLayout<InkVertex>.stride
        guard let c = device.makeBuffer(length: 256 * 1024 * stride, options: .storageModeShared),
              let p = device.makeBuffer(length: Self.particleCapacity * MemoryLayout<Particle>.stride,
                                        options: .storageModeShared) else { return nil }
        committed = c
        particleBuffer = p
        liveBuffers = (0..<Self.framesInFlight).compactMap { _ in
            device.makeBuffer(length: 64 * 1024 * stride, options: .storageModeShared)
        }
        spriteBuffers = (0..<Self.framesInFlight).compactMap { _ in
            device.makeBuffer(length: 256 * MemoryLayout<SpriteVertex>.stride, options: .storageModeShared)
        }
        effectBuffers = (0..<Self.framesInFlight).compactMap { _ in
            device.makeBuffer(length: 1024 * MemoryLayout<EffectInstance>.stride, options: .storageModeShared)
        }
    }

    /// Draws every pipeline once off-screen so the first real touch is as fast as the hundredth.
    func warmUp() {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 8, height: 8, mipmapped: false)
        d.usage = .renderTarget
        d.storageMode = .private
        guard let tex = device.makeTexture(descriptor: d), let cb = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = tex
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .dontCare
        var u = uniforms(space: InkSpace(width: 8, height: 8), pixelScale: 1, time: 0)
        let verts = [InkVertex(x: 0, y: 0, u: 1, coreFrac: 0.3, alpha: 1, along: 0),
                     InkVertex(x: 0.1, y: 0, u: -1, coreFrac: 0.3, alpha: 1, along: 0),
                     InkVertex(x: 0, y: 0.1, u: 1, coreFrac: 0.3, alpha: 1, along: 0)]
        var sprite = SpriteVertex(x: 0, y: 0, size: 4, alpha: 1)
        var effect = EffectInstance(x: 4, y: 4, radius: 2, thickness: 1, alpha: 1, shape: 0, r: 1, g: 1, b: 1)
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        var dist = DistortionBlock()
        dist.set([Distortion(x: 4, y: 4, radius: 8, strength: 0.1, kind: 1, phase: 0, dirX: 1, dirY: 0)])
        enc.setVertexBytes(&dist, length: MemoryLayout<DistortionBlock>.stride, index: 2)
        enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.setRenderPipelineState(inkPipeline)
        verts.withUnsafeBytes { enc.setVertexBytes($0.baseAddress!, length: $0.count, index: 0) }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.setRenderPipelineState(effectPipeline)
        enc.setVertexBytes(&effect, length: MemoryLayout<EffectInstance>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: 1)
        enc.setRenderPipelineState(particlePipeline)
        enc.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: 1)
        enc.setRenderPipelineState(spritePipeline)
        enc.setVertexBytes(&sprite, length: MemoryLayout<SpriteVertex>.stride, index: 0)
        enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: 1)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
    }

    /// Replaces all committed ink (after an erase, undo or snap). Uses a fresh buffer so
    /// frames still in flight keep reading the old one.
    func resetCommitted(_ vertices: [InkVertex]) {
        let stride = MemoryLayout<InkVertex>.stride
        let length = max(committed.length, vertices.count * stride)
        guard let fresh = device.makeBuffer(length: length, options: .storageModeShared) else { return }
        if !vertices.isEmpty {
            vertices.withUnsafeBytes { src in _ = memcpy(fresh.contents(), src.baseAddress!, src.count) }
        }
        committed = fresh
        committedCount = vertices.count
    }

    func appendCommitted(_ vertices: [InkVertex]) {
        let stride = MemoryLayout<InkVertex>.stride
        let needed = (committedCount + vertices.count) * stride
        if needed > committed.length {
            // Grow. Rare; the old buffer stays alive while in-flight frames use it.
            guard let bigger = device.makeBuffer(length: max(needed, committed.length * 2), options: .storageModeShared) else { return }
            memcpy(bigger.contents(), committed.contents(), committedCount * stride)
            committed = bigger
        }
        vertices.withUnsafeBytes { src in
            _ = memcpy(committed.contents() + committedCount * stride, src.baseAddress!, src.count)
        }
        committedCount += vertices.count
    }

    /// Frames skipped because the GPU was still busy with earlier ones.
    private(set) var skippedFrames = 0

    func render(drawable: CAMetalDrawable, _ f: FrameContent, presented: @escaping (Double) -> Void) {
        // Never block the main thread (where touches arrive) on the GPU: if three
        // frames are still in flight, skip this one.
        guard inflight.wait(timeout: .now()) == .success else { skippedFrames += 1; return }
        frameIndex = (frameIndex + 1) % Self.framesInFlight
        let liveBuffer = upload(f.live, into: &liveBuffers[frameIndex])
        let spriteBuffer = upload(f.sprites, into: &spriteBuffers[frameIndex])
        let effectBuffer = upload(f.effects, into: &effectBuffers[frameIndex])

        guard let cb = queue.makeCommandBuffer() else { inflight.signal(); return }
        let bg = theme.background
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let dim = Double(f.dim)
        pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(bg.r) * dim, green: Double(bg.g) * dim,
                                                            blue: Double(bg.b) * dim, alpha: 1)

        var u = uniforms(space: f.space, pixelScale: f.pixelScale, time: f.time)
        u.extra = SIMD4(f.dim, f.shimmer, 0, 0)
        var dist = f.distortions
        if let enc = cb.makeRenderCommandEncoder(descriptor: pass) {
            enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
            enc.setVertexBytes(&dist, length: MemoryLayout<DistortionBlock>.stride, index: 2)
            enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)

            enc.setRenderPipelineState(inkPipeline)
            if committedCount > 0 {
                enc.setVertexBuffer(committed, offset: 0, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: committedCount)
            }
            if !f.live.isEmpty, let liveBuffer {
                enc.setVertexBuffer(liveBuffer, offset: 0, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: f.live.count)
            }
            if !f.effects.isEmpty, let effectBuffer {
                enc.setRenderPipelineState(effectPipeline)
                enc.setVertexBuffer(effectBuffer, offset: 0, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: f.effects.count)
            }
            if f.particleCount > 0 {
                enc.setRenderPipelineState(particlePipeline)
                enc.setVertexBuffer(particleBuffer, offset: 0, index: 0)
                enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: f.particleCount)
            }
            if !f.sprites.isEmpty, let spriteBuffer {
                enc.setRenderPipelineState(spritePipeline)
                enc.setVertexBuffer(spriteBuffer, offset: 0, index: 0)
                enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: f.sprites.count)
            }
            enc.endEncoding()
        }

        let sem = inflight
        #if targetEnvironment(simulator)
        // The Simulator SDK has no presented handler. Use GPU completion as a stand-in;
        // these numbers are approximate and not a real latency measurement.
        cb.addCompletedHandler { _ in
            sem.signal()
            presented(CACurrentMediaTime())
        }
        #else
        drawable.addPresentedHandler { d in presented(d.presentedTime) }
        cb.addCompletedHandler { _ in sem.signal() }
        #endif
        cb.present(drawable)
        cb.commit()
    }

    private func upload<T>(_ items: [T], into buffer: inout MTLBuffer) -> MTLBuffer? {
        guard !items.isEmpty else { return buffer }
        let bytes = items.count * MemoryLayout<T>.stride
        if bytes > buffer.length {
            guard let bigger = device.makeBuffer(length: bytes * 2, options: .storageModeShared) else { return nil }
            buffer = bigger
        }
        items.withUnsafeBytes { src in _ = memcpy(buffer.contents(), src.baseAddress!, src.count) }
        return buffer
    }

    private func uniforms(space: InkSpace, pixelScale: Float, time: Float) -> Uniforms {
        func v(_ c: RGBA) -> SIMD4<Float> { SIMD4(c.r, c.g, c.b, c.a) }
        return Uniforms(
            viewSize: SIMD2(space.width, space.height),
            center: SIMD2(space.centerX, space.centerY),
            unitScale: space.unit,
            pixelScale: pixelScale,
            glowStrength: theme.glowStrength,
            time: time,
            inkColor: v(theme.ink),
            glowColor: v(theme.glow),
            sparkleColor: v(theme.sparkle)
        )
    }
}
