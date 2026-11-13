// Compiled at launch with makeLibrary(source:) so the build needs no Metal Toolchain.
// Layouts must match InkVertex (InkModel), SpriteVertex and Uniforms (MetalRenderer.swift).
enum ShaderSource {
    static let code = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct InkVertex {
        packed_float2 pos;   // canvas units
        float u;             // -1...1 across the glow width
        float coreFrac;      // solid core as a fraction of the half-width
        float alpha;
        float along;
        float halfWidth;     // canvas units
    };

    struct SpriteVertex {
        packed_float2 pos;   // canvas units
        float size;          // diameter in points
        float alpha;
    };

    struct Uniforms {
        float2 viewSize;     // points
        float2 center;       // points
        float unitScale;     // points per canvas unit
        float pixelScale;    // pixels per point
        float glowStrength;
        float time;          // seconds since renderer start (particles)
        float4 inkColor;
        float4 glowColor;
        float4 sparkleColor;
    };

    static float4 ptToClip(float2 pt, constant Uniforms& U) {
        float2 ndc = pt / U.viewSize * 2.0 - 1.0;
        return float4(ndc.x, -ndc.y, 0.0, 1.0);
    }

    static float4 toClip(float2 unitPos, constant Uniforms& U) {
        float2 pt = unitPos * U.unitScale + U.center;
        float2 ndc = pt / U.viewSize * 2.0 - 1.0;
        return float4(ndc.x, -ndc.y, 0.0, 1.0);
    }

    // MARK: Ink

    struct InkOut {
        float4 position [[position]];
        float uh;            // u * halfWidth, divided per pixel (projective interpolation)
        float h;
        float coreFrac;
        float alpha;
    };

    vertex InkOut ink_vertex(uint vid [[vertex_id]],
                             const device InkVertex* verts [[buffer(0)]],
                             constant Uniforms& U [[buffer(1)]]) {
        InkVertex v = verts[vid];
        InkOut o;
        o.position = toClip(float2(v.pos), U);
        o.uh = v.u * v.halfWidth;
        o.h = v.halfWidth;
        o.coreFrac = v.coreFrac;
        o.alpha = v.alpha;
        return o;
    }

    // Solid warm-white core with a soft glow falling off to the edge.
    // Output is premultiplied; alpha is the core only, so glow adds light over the canvas.
    fragment float4 ink_fragment(InkOut in [[stage_in]], constant Uniforms& U [[buffer(0)]]) {
        float d = abs(in.uh / max(in.h, 1e-7));
        float aa = max(fwidth(d), 1e-4);
        float core = 1.0 - smoothstep(in.coreFrac - aa, in.coreFrac + aa, d);
        float g = 1.0 - d;
        g = g * g * U.glowStrength;
        float3 rgb = U.inkColor.rgb * core + U.glowColor.rgb * g * (1.0 - core);
        return float4(rgb, core) * in.alpha;
    }

    // MARK: Sprites (stroke-head sparkle)

    struct SpriteOut {
        float4 position [[position]];
        float pointSize [[point_size]];
        float alpha;
    };

    vertex SpriteOut sprite_vertex(uint vid [[vertex_id]],
                                   const device SpriteVertex* verts [[buffer(0)]],
                                   constant Uniforms& U [[buffer(1)]]) {
        SpriteVertex v = verts[vid];
        SpriteOut o;
        o.position = toClip(float2(v.pos), U);
        o.pointSize = v.size * U.pixelScale;
        o.alpha = v.alpha;
        return o;
    }

    // Additive: bright pin-point core plus a soft halo.
    fragment float4 sprite_fragment(SpriteOut in [[stage_in]],
                                    float2 pc [[point_coord]],
                                    constant Uniforms& U [[buffer(0)]]) {
        float d = length(pc - 0.5) * 2.0;
        float core = 1.0 - smoothstep(0.0, 0.22, d);
        float halo = pow(max(0.0, 1.0 - d), 3.0) * 0.55;
        float a = (core + halo) * in.alpha;
        return float4(U.sparkleColor.rgb * a, a);
    }
    // MARK: Effects (rings, discs, dots). Instanced quads, additive, in points.

    struct EffectInstance {
        packed_float2 center;
        float radius;
        float thickness;
        float alpha;
        float shape;          // 0 ring, 1 soft disc, 2 bright dot, 3 glowing line (center → p2)
        packed_float3 color;
        packed_float2 p2;
    };

    struct EffectOut {
        float4 position [[position]];
        float2 local;
        float radius;
        float thickness;
        float alpha;
        float shape;
        float3 color;
    };

    vertex EffectOut effect_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                   const device EffectInstance* inst [[buffer(0)]],
                                   constant Uniforms& U [[buffer(1)]]) {
        EffectInstance e = inst[iid];
        const float2 corners[6] = { float2(-1, -1), float2(1, -1), float2(-1, 1),
                                    float2(1, -1), float2(1, 1), float2(-1, 1) };
        EffectOut o;
        float2 c = corners[vid];
        if (e.shape > 2.5) {
            // Line: a quad along the segment, in segment space (x along, y across).
            float2 a = float2(e.center), b = float2(e.p2);
            float len = length(b - a);
            float2 dir = len > 1e-3 ? (b - a) / len : float2(1, 0);
            float2 nrm = float2(-dir.y, dir.x);
            float ext = max(e.thickness, 0.5) * 3.0;
            float lx = c.x < 0.0 ? -ext : len + ext;
            float ly = c.y * ext;
            o.local = float2(lx, ly);
            o.position = ptToClip(a + dir * lx + nrm * ly, U);
            o.radius = len;
        } else {
            float extent = e.shape < 0.5 ? e.radius + e.thickness * 3.0
                         : (e.shape < 1.5 ? e.radius : e.radius * 2.0);
            o.local = c * extent;
            o.position = ptToClip(float2(e.center) + o.local, U);
            o.radius = e.radius;
        }
        o.thickness = e.thickness;
        o.alpha = e.alpha;
        o.shape = e.shape;
        o.color = float3(e.color);
        return o;
    }

    fragment float4 effect_fragment(EffectOut in [[stage_in]]) {
        float d = length(in.local);
        float a;
        if (in.shape > 2.5) {
            float along = in.local.x - clamp(in.local.x, 0.0, in.radius);
            float dl = length(float2(along, in.local.y)) / max(in.thickness, 0.5);
            a = exp(-dl * dl) + 0.6 * exp(-dl * dl * 9.0);
        } else if (in.shape < 0.5) {
            float x = (d - in.radius) / max(in.thickness, 0.5);
            a = exp(-x * x);
        } else if (in.shape < 1.5) {
            float k = saturate(1.0 - d / max(in.radius, 0.5));
            a = k * k;
        } else {
            float core = 1.0 - smoothstep(in.radius * 0.45, in.radius, d);
            float halo = pow(saturate(1.0 - d / (in.radius * 2.0)), 3.0) * 0.5;
            a = core + halo;
        }
        a *= in.alpha;
        return float4(in.color * a, a);
    }

    // MARK: Particles. Analytic motion on the GPU: origin + v * (1 - e^(-drag t)) / drag.

    struct Particle {
        packed_float2 origin;
        packed_float2 vel;
        float t0;
        float life;
        float size;
        float drag;
        float alpha;
        packed_float3 color;
        float mode;           // 0 linear with drag, 1 spiral around origin
        float p1;             // spiral: end radius
        float p2;             // spiral: angular speed (rad/s)
        float pad;
    };

    struct ParticleOut {
        float4 position [[position]];
        float pointSize [[point_size]];
        float alpha;
        float3 color;
    };

    vertex ParticleOut particle_vertex(uint vid [[vertex_id]],
                                       const device Particle* ps [[buffer(0)]],
                                       constant Uniforms& U [[buffer(1)]]) {
        Particle p = ps[vid];
        float t = U.time - p.t0;
        ParticleOut o;
        if (t < 0.0 || t > p.life) {
            o.position = float4(-2.0, -2.0, 0.0, 1.0);
            o.pointSize = 1.0;
            o.alpha = 0.0;
            o.color = float3(0.0);
            return o;
        }
        float f = 1.0 - t / p.life;
        float2 pos;
        if (p.mode > 0.5) {
            // vel = (start radius, start angle). Radius eases toward p1; angle spins at p2.
            float e = 1.0 - pow(f, 2.0);
            float r = mix(p.vel.x, p.p1, e);
            float ang = p.vel.y + p.p2 * t;
            pos = float2(p.origin) + r * float2(cos(ang), sin(ang));
        } else {
            float k = max(p.drag, 1e-3);
            pos = float2(p.origin) + float2(p.vel) * (1.0 - exp(-k * t)) / k;
        }
        o.position = ptToClip(pos, U);
        o.pointSize = max(1.0, p.size * U.pixelScale * (0.6 + 0.4 * f));
        o.alpha = p.alpha * pow(f, 1.5);
        o.color = float3(p.color);
        return o;
    }

    fragment float4 particle_fragment(ParticleOut in [[stage_in]], float2 pc [[point_coord]]) {
        float d = length(pc - 0.5) * 2.0;
        float a = pow(saturate(1.0 - d), 2.0) * in.alpha;
        return float4(in.color * a, a);
    }
    """#
}
