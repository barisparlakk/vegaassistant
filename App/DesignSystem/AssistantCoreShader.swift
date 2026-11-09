// The Metal source for Vega's presence, compiled at runtime with MTLDevice.makeLibrary(source:)
// so building the app doesn't need the separate Metal Toolchain.
//
// A faceted crystal star: four long points and four short diagonal ones, pyramidal facets,
// a slow sway that makes the facets catch the studio lights, refraction with slight
// dispersion, a glowing core with drifting filaments inside, and HUD rings in orbit.
enum AssistantCoreShader {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 size;
    float time;
    float energy;
    float2 tilt;
    float dark;
    float rings;
    float pulse;
    float4 accent;
};

struct VertexOut {
    float4 position [[position]];
};

vertex VertexOut coreVertex(uint id [[vertex_id]]) {
    float2 corners[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    VertexOut out;
    out.position = float4(corners[id], 0, 1);
    return out;
}

namespace vega {

constant float PI = 3.14159265;

float hash(float3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(float3 x) {
    float3 i = floor(x);
    float3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(i + float3(0, 0, 0)), hash(i + float3(1, 0, 0)), f.x),
                   mix(hash(i + float3(0, 1, 0)), hash(i + float3(1, 1, 0)), f.x), f.y),
               mix(mix(hash(i + float3(0, 0, 1)), hash(i + float3(1, 0, 1)), f.x),
                   mix(hash(i + float3(0, 1, 1)), hash(i + float3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(float3 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 3; i++) {
        value += amplitude * noise(p);
        p = p * 2.03 + float3(1.7, 9.2, 3.1);
        amplitude *= 0.5;
    }
    return value;
}

float3x3 rotX(float a) { float c = cos(a), s = sin(a); return float3x3(float3(1, 0, 0), float3(0, c, s), float3(0, -s, c)); }
float3x3 rotY(float a) { float c = cos(a), s = sin(a); return float3x3(float3(c, 0, -s), float3(0, 1, 0), float3(s, 0, c)); }
float3x3 rotZ(float a) { float c = cos(a), s = sin(a); return float3x3(float3(c, s, 0), float3(-s, c, 0), float3(0, 0, 1)); }

/// Exact 2D distance to a 4-point star with points on the axes (after Inigo Quilez).
/// m in [2, 4]: higher is sharper.
float star2(float2 p, float r, float m) {
    const float an = PI / 4.0;
    float en = PI / m;
    float2 acs = float2(cos(an), sin(an));
    float2 ecs = float2(cos(en), sin(en));
    float bn = fmod(atan2(p.x, p.y) + 2.0 * PI, 2.0 * an) - an;
    p = length(p) * float2(cos(bn), abs(sin(bn)));
    p -= r * acs;
    p += ecs * clamp(-dot(p, ecs), 0.0, r * acs.y / ecs.y);
    return length(p) * sign(p.x);
}

/// The crystal: a 2D star raised into pyramidal facets, plus four short diagonal points.
float star(float3 p) {
    float2 q = float2(p.x, p.y);
    float2 d45 = float2(q.x + q.y, q.y - q.x) * 0.70710678;
    float main = star2(q, 0.92, 3.0);     // long points: up, down, left, right
    float minor = star2(d45, 0.40, 2.8);  // short points on the diagonals
    float d = min(main, minor);
    const float slope = 1.05;
    float facets = (abs(p.z) + slope * d) * 0.6897; // 1 / sqrt(1 + slope²)
    return max(facets, d) - 0.006;
}

float3 normalAt(float3 p) {
    const float e = 0.0012;
    const float2 k = float2(1, -1);
    return normalize(k.xyy * star(p + k.xyy * e) + k.yyx * star(p + k.yyx * e) +
                     k.yxy * star(p + k.yxy * e) + k.xxx * star(p + k.xxx * e));
}

/// A studio: graded backdrop, a large key softbox upper left, a strip light right, a floor bounce.
float3 environment(float3 r, float dark) {
    float up = saturate(r.y * 0.5 + 0.5);
    float3 base = dark > 0.5
        ? mix(float3(0.012, 0.013, 0.02), float3(0.10, 0.10, 0.125), up)
        : mix(float3(0.45, 0.47, 0.53), float3(0.98, 0.98, 1.0), up);
    float3 keyDir = normalize(float3(-0.55, 0.62, 0.56));
    float3 keyU = normalize(cross(keyDir, float3(0, 0, 1)));
    float3 keyV = cross(keyU, keyDir);
    float facing = dot(r, keyDir);
    float2 q = float2(dot(r, keyU), dot(r, keyV)) / max(facing, 0.001);
    float key = facing > 0.0 ? smoothstep(0.05, 0.0, max(abs(q.x) - 0.45, abs(q.y) - 0.25)) : 0.0;
    float strip = smoothstep(0.975, 0.995, dot(normalize(float3(r.x, r.y * 0.2, r.z)), normalize(float3(0.92, 0.0, 0.38))));
    float rim = smoothstep(0.96, 0.995, dot(normalize(float3(r.x * 0.3, r.y, r.z)), normalize(float3(0.0, 0.35, -0.94))));
    return base + float3(key * 3.2) + float3(strip * 1.8) + float3(rim * 0.8);
}

float ring(float3 ro, float3 rd, float3 n, float radius, float width, float dashes, float duty,
           float arc, float phase, thread float &t) {
    float denom = dot(rd, n);
    t = 1e9;
    if (abs(denom) < 1e-4) { return 0.0; }
    t = -dot(ro, n) / denom;
    if (t < 0.0) { return 0.0; }
    float3 p = ro + rd * t;
    float d = abs(length(p) - radius);
    float line = exp(-d * d / (width * width)) + 0.22 * exp(-d * d / (16.0 * width * width));
    float3 u = normalize(cross(n, abs(n.y) < 0.99 ? float3(0, 1, 0) : float3(1, 0, 0)));
    float3 v = cross(n, u);
    float angle = fract(atan2(dot(p, v), dot(p, u)) / (2.0 * PI) + phase);
    float mask = 1.0;
    if (dashes > 0.0) {
        mask *= smoothstep(0.0, 0.08, fract(angle * dashes)) * smoothstep(duty, duty - 0.08, fract(angle * dashes));
    }
    if (arc < 1.0) {
        mask *= smoothstep(0.0, 0.02, angle) * smoothstep(arc, arc - 0.06, angle);
    }
    return line * mask;
}

} // namespace vega

fragment float4 coreFragment(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    using namespace vega;

    float scale = min(u.size.x, u.size.y) * 0.5;
    float2 uv = (in.position.xy - u.size * 0.5) / scale;
    uv.y = -uv.y;
    float px = 1.0 / scale;
    float time = u.time;
    float energy = saturate(u.energy + u.pulse * 0.45);
    float3 accent = float3(u.accent.rgb);
    float3 hot = mix(accent, float3(1.0, 0.97, 0.92), 0.65);
    float speed = 0.22 + 0.6 * u.energy;
    bool detailed = u.rings > 0.5;
    float zoom = detailed ? 1.42 : 1.08;

    // Camera (orthographic) and the star's slow turn.
    float3 ro = float3(uv * zoom, 3.0);
    float3 rd = float3(0, 0, -1);
    // Sway rather than spin, so it always reads as a star; it never turns edge-on.
    // (A still star gets a fixed time, so it holds one pose.)
    float spin = 0.62 * sin(time * 0.23 * (0.7 + speed)) + 0.14 * sin(time * 0.11);
    float3x3 model = rotY(spin + u.tilt.x) * rotX(0.28 * sin(time * 0.21) + u.tilt.y - 0.12) * rotZ(0.06 * sin(time * 0.13));
    float3x3 inverse = transpose(model);
    float3 oro = inverse * ro;
    float3 ord = inverse * rd;

    // March to the crystal.
    float t = 2.0;
    float minD = 1e9;
    bool hit = false;
    for (int i = 0; i < 96; i++) {
        float d = star(oro + ord * t);
        minD = min(minD, d);
        if (d < 0.0006) { hit = true; break; }
        t += d * 0.9;
        if (t > 4.2) { break; }
    }

    float3 col = float3(0);
    float alpha = 0.0;

    // Halo around the crystal, brighter while speaking.
    float halo = exp(-max(minD, 0.0) * (detailed ? 6.0 : 10.0)) * (hit ? 0.0 : 1.0);
    halo *= (u.dark > 0.5 ? 0.38 : 0.2) * (0.5 + 0.8 * energy);
    col += accent * halo;
    alpha += halo;

    // HUD rings.
    float3 front = float3(0);
    float frontA = 0.0;
    if (detailed) {
        float3x3 precess = rotY(time * 0.11 * speed) * rotZ(0.12 * sin(time * 0.07));
        float w = 1.7 * px * zoom;
        float t1, t2, t3;
        float r1 = ring(ro, rd, precess * normalize(float3(0.12, 1.0, 0.30)), 1.02, w, 0.0, 1.0, 1.0, 0.0, t1) * 0.6;
        float r2 = ring(ro, rd, precess * normalize(float3(-0.35, 1.0, -0.18)), 1.18, w, 72.0, 0.55, 1.0, time * 0.02 * speed, t2) * 0.4;
        float r3 = ring(ro, rd, rotY(-time * 0.2 * speed) * normalize(float3(0.55, 0.85, 0.12)), 0.94, 1.6 * w, 0.0, 1.0, 0.28, time * 0.09 * speed, t3) * 0.9;
        float3 ink = u.dark > 0.5 ? mix(accent, float3(1.0), 0.25) : accent * 0.75;
        float strength = (u.dark > 0.5 ? 1.0 : 0.85) * (0.5 + 0.5 * energy);
        float ts[3] = { t1, t2, t3 };
        float rs[3] = { r1, r2, r3 };
        for (int i = 0; i < 3; i++) {
            float k = rs[i] * strength;
            if (!hit || ts[i] < t) {
                front += ink * k;
                frontA += k;
            } else {
                col += ink * k * 0.3;
                alpha += k * 0.3;
            }
        }
    }

    if (hit) {
        float3 p = oro + ord * t;
        float3 n = normalAt(p);
        float ndv = saturate(dot(-ord, n));
        float fresnel = 0.06 + 0.94 * pow(1.0 - ndv, 5.0);
        // Reflections are evaluated in world space so the lights stay put while the star turns.
        float3 reflection = environment(model * reflect(ord, n), u.dark);

        // Into the crystal: march the refracted ray, gathering the core's light.
        float3 rdi = refract(ord, n, 1.0 / 1.6);
        float3 q = p - n * 0.004;
        float glow = 0.0;
        float filaments = 0.0;
        float travelled = 0.0;
        float3x3 swirl = rotY(time * speed * 0.6) * rotX(time * speed * 0.23);
        for (int i = 0; i < 40; i++) {
            float d = star(q);
            if (d > 0.0 && i > 2) { break; }
            float r = length(q);
            float3 fq = swirl * q * 4.0 + float3(0.0, time * speed * 0.8, time * 0.1);
            float field = fbm(fq);
            float tendril = pow(1.0 - abs(field * 2.0 - 1.0), 22.0) * smoothstep(0.06, -0.02, d + 0.02);
            float pulse = 0.85 + 0.15 * sin(time * (1.1 + 1.6 * energy));
            glow += exp(-r * r * (34.0 - 12.0 * energy)) * pulse * 0.018;
            filaments += tendril * 0.018;
            q += rdi * 0.018;
            travelled += 0.018;
        }

        // Out the back: refract per channel for a little dispersion, then tint by the path length.
        float3 nb = normalAt(q);
        float3 transmitted;
        transmitted.r = environment(model * refract(rdi, -nb, 1.58), u.dark).r;
        transmitted.g = environment(model * refract(rdi, -nb, 1.60), u.dark).g;
        transmitted.b = environment(model * refract(rdi, -nb, 1.63), u.dark).b;
        float3 absorb = exp(-(1.0 - accent) * travelled * 3.5);
        transmitted *= absorb * (u.dark > 0.5 ? 0.9 : 0.75);

        float3 raw = hot * glow * (6.0 + 5.0 * energy) + mix(accent, hot, 0.35) * filaments * (10.0 + 14.0 * energy);
        float3 inner = 1.0 - exp(-raw * 1.5);

        // Facet edges: where the surface turns sharply, add a thin bright line.
        float edge = smoothstep(0.55, 0.95, length(normalAt(p + float3(0.004)) - n));
        float3 crystal = reflection * fresnel + (transmitted * 0.55 + inner) * (1.0 - fresnel) + hot * edge * 0.35;
        crystal += accent * pow(1.0 - ndv, 3.0) * 0.25 * (0.6 + 0.6 * energy);

        col = crystal + col * 0.0;
        alpha = 1.0;
    } else if (minD < 2.0 * px) {
        // Antialiased silhouette.
        float a = smoothstep(2.0 * px, 0.0, minD);
        col = mix(col, hot * 0.6, a);
        alpha = max(alpha, a);
    }

    // A thin four-point flare that brightens with speech.
    if (detailed) {
        float2 f = abs(uv);
        float flare = (exp(-f.x * 90.0) * exp(-f.y * 2.6) + exp(-f.y * 90.0) * exp(-f.x * 2.6)) * (0.06 + 0.35 * u.pulse);
        front += hot * flare;
        frontA += flare;
    }

    col += front;
    alpha = saturate(alpha + frontA);
    col = min(col, float3(4.0));
    return float4(col, alpha);
}
"""#
}
