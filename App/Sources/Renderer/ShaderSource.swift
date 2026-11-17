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
        float tint;          // stroke ID: picks the palette color (v2 themes)
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
        float4 extra;        // x: dim (1 = full brightness), y: idle shimmer amount (G32)
        float4 palette1;     // inkColor is palette[0]
        float4 palette2;
        float4 palette3;
        float4 style;        // x: palette count, y: ink mode (0 single, 1 per stroke, 2 along), z: texture (1 chalk), w: sprite
        float4 style2;       // x: core scale, y: glow falloff, z: particle gravity, w: glow takes ink color
        float4 bg0;          // background center color; a = vignette amount
        float4 bg1;          // background edge color
    };

    static float3 paletteAt(int i, constant Uniforms& U) {
        int n = max(1, int(U.style.x));
        i = ((i % n) + n) % n;
        return i == 0 ? U.inkColor.rgb : (i == 1 ? U.palette1.rgb : (i == 2 ? U.palette2.rgb : U.palette3.rgb));
    }

    static float hash21(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    // MARK: Background (theme color with an optional vignette)

    struct BackgroundOut { float4 position [[position]]; };

    vertex BackgroundOut background_vertex(uint vid [[vertex_id]]) {
        const float2 tri[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
        BackgroundOut o;
        o.position = float4(tri[vid], 0.0, 1.0);
        return o;
    }

    fragment float4 background_fragment(BackgroundOut in [[stage_in]], constant Uniforms& U [[buffer(0)]]) {
        float2 px = in.position.xy / U.pixelScale;               // points
        float2 q = (px - U.viewSize * 0.5) / (0.5 * length(U.viewSize));
        float r = length(q);
        float v = smoothstep(0.35, 1.05, r) * U.bg0.a;
        float3 c = mix(U.bg0.rgb, U.bg1.rgb, v);
        return float4(c * U.extra.x, 1.0);
    }

    // Ink distortions (G11, G14, G18, G19, G20, G22, G23, G24): displace ink vertices,
    // then let the ink return to rest as each distortion fades.
    struct Distortion {
        packed_float2 center;  // points
        float radius;
        float strength;
        float kind;            // 0 ripple, 1 twist, 2 pull, 3 wave
        float phase;           // ripple: wavefront radius; wave: distance travelled
        packed_float2 dir;     // wave direction
    };

    struct DistortionBlock {
        uint count;
        uint pad0, pad1, pad2;
        Distortion d[8];
    };

    static float2 distort(float2 p, constant DistortionBlock& D) {
        for (uint k = 0; k < D.count; k++) {
            Distortion d = D.d[k];
            float2 c = float2(d.center);
            float2 v = p - c;
            float r = length(v);
            if (d.kind < 0.5) {
                float x = (r - d.phase) / 28.0;
                float env = exp(-x * x) * d.strength * (1.0 - smoothstep(d.radius * 0.6, d.radius, r));
                p += (r > 1e-3 ? v / r : float2(0.0)) * sin(x * 3.14159) * env * 10.0;
            } else if (d.kind < 1.5) {
                float f = 1.0 - smoothstep(0.0, d.radius, r);
                float a = d.strength * f * f;
                float ca = cos(a), sa = sin(a);
                p = c + float2(v.x * ca - v.y * sa, v.x * sa + v.y * ca);
            } else if (d.kind < 2.5) {
                float f = 1.0 - smoothstep(0.0, d.radius, r);
                p = c + v * (1.0 - clamp(d.strength, 0.0, 0.99) * f);
            } else {
                float2 dir = float2(d.dir);
                float s = dot(v, dir) - d.phase;
                p += dir * exp(-(s / 40.0) * (s / 40.0)) * d.strength * 14.0;
            }
        }
        return p;
    }

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
        float along;
        float tint;
    };

    vertex InkOut ink_vertex(uint vid [[vertex_id]],
                             const device InkVertex* verts [[buffer(0)]],
                             constant Uniforms& U [[buffer(1)]],
                             constant DistortionBlock& D [[buffer(2)]]) {
        InkVertex v = verts[vid];
        InkOut o;
        float2 pt = float2(v.pos) * U.unitScale + U.center;
        o.position = ptToClip(distort(pt, D), U);
        o.uh = v.u * v.halfWidth;
        o.h = v.halfWidth;
        o.coreFrac = v.coreFrac;
        o.alpha = v.alpha;
        o.along = v.along * U.unitScale;
        o.tint = v.tint;
        return o;
    }

    // Solid warm-white core with a soft glow falling off to the edge.
    // Output is premultiplied; alpha is the core only, so glow adds light over the canvas.
    fragment float4 ink_fragment(InkOut in [[stage_in]], constant Uniforms& U [[buffer(0)]]) {
        float d = abs(in.uh / max(in.h, 1e-7));
        float aa = max(fwidth(d), 1e-4);
        float cf = in.coreFrac * U.style2.x;
        float core = 1.0 - smoothstep(cf - aa, cf + aa, d);
        float g = pow(saturate(1.0 - d), U.style2.y) * U.glowStrength;

        // Ink color by theme: one color, a palette color per stroke, or flowing along it.
        float3 ink;
        if (U.style.y < 0.5) {
            ink = U.inkColor.rgb;
        } else if (U.style.y < 1.5) {
            ink = paletteAt(int(in.tint + 0.5), U);
        } else {
            float n = max(1.0, U.style.x);
            float t = fract(in.along / 520.0 + in.tint * 0.37) * n;
            int i = int(floor(t));
            ink = mix(paletteAt(i, U), paletteAt(i + 1, U), smoothstep(0.0, 1.0, fract(t)));
        }
        float3 glow = U.style2.w > 0.5 ? ink : U.glowColor.rgb;

        // Chalk: grainy core with broken edges.
        if (U.style.z > 0.5) {
            float n1 = hash21(floor(in.position.xy / 1.6));
            float n2 = hash21(floor(in.position.xy / 5.0) + 17.0);
            core *= mix(0.45, 1.0, n1);
            if (d > cf * 0.45 && n2 < 0.4) core *= 0.25;
        }
        float3 rgb = ink * core + glow * g * (1.0 - core);
        // G32: ink shimmers softly while idle.
        float shimmer = 1.0 - U.extra.y * 0.22 * (0.5 + 0.5 * sin(U.time * 1.4 + in.along * 0.045));
        return float4(rgb * shimmer * U.extra.x, core) * in.alpha;
    }

    // MARK: Sprite shapes (sparkles and particles): 0 soft, 1 star, 2 dust, 3 graphite

    static float spriteShape(float2 pc, float kind, float seed) {
        float2 q = (pc - 0.5) * 2.0;
        float d = length(q);
        if (kind < 0.5) {
            return pow(saturate(1.0 - d), 2.0);
        } else if (kind < 1.5) {
            float star = exp(-abs(q.x) * 9.0) * exp(-abs(q.y) * 1.6) + exp(-abs(q.y) * 9.0) * exp(-abs(q.x) * 1.6);
            return saturate(star * (1.0 - d) * 1.6 + (1.0 - smoothstep(0.0, 0.25, d)));
        } else if (kind < 2.5) {
            float n = hash21(floor(pc * 5.0) + seed);
            return (1.0 - smoothstep(0.55, 1.0, d)) * step(0.35, n) * 0.85;
        }
        return (1.0 - smoothstep(0.45, 0.6, d)) * 0.9;
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
        float a;
        if (U.style.w < 0.5) {
            float d = length(pc - 0.5) * 2.0;
            float core = 1.0 - smoothstep(0.0, 0.22, d);
            float halo = pow(max(0.0, 1.0 - d), 3.0) * 0.55;
            a = core + halo;
        } else {
            a = spriteShape(pc, U.style.w, 3.0);
        }
        a *= in.alpha;
        return float4(U.sparkleColor.rgb * a * U.extra.x, a);
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

    fragment float4 effect_fragment(EffectOut in [[stage_in]], constant Uniforms& U [[buffer(0)]]) {
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
        return float4(in.color * a * U.extra.x, a);
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
        float seed;
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
            o.seed = 0.0;
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
        pos.y += 0.5 * U.style2.z * t * t;   // theme gravity (chalk dust falls)
        o.position = ptToClip(pos, U);
        o.pointSize = max(1.0, p.size * U.pixelScale * (0.6 + 0.4 * f));
        o.alpha = p.alpha * pow(f, 1.5);
        o.color = float3(p.color);
        o.seed = float(vid % 97);
        return o;
    }

    fragment float4 particle_fragment(ParticleOut in [[stage_in]], float2 pc [[point_coord]],
                                      constant Uniforms& U [[buffer(0)]]) {
        float a = spriteShape(pc, U.style.w, in.seed) * in.alpha;
        return float4(in.color * a * U.extra.x, a);
    }
    """#
}
