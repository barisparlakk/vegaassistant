// The Metal source for AssistantCore, compiled at runtime with MTLDevice.makeLibrary(source:)
// so building the app doesn't need the separate Metal Toolchain.
enum AssistantCoreShader {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

// Morning's presence: a real-time ray-traced glass sphere with a living energy core and
// orbiting HUD rings. Rendered per pixel with an orthographic camera; output is premultiplied
// so it composites over any background. Compiled at runtime by AssistantCoreRenderer.

namespace core {

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
    for (int i = 0; i < 4; i++) {
        value += amplitude * noise(p);
        p = p * 2.03 + float3(1.7, 9.2, 3.1);
        amplitude *= 0.5;
    }
    return value;
}

float3x3 rotX(float a) {
    float c = cos(a), s = sin(a);
    return float3x3(float3(1, 0, 0), float3(0, c, s), float3(0, -s, c));
}

float3x3 rotY(float a) {
    float c = cos(a), s = sin(a);
    return float3x3(float3(c, 0, -s), float3(0, 1, 0), float3(s, 0, c));
}

float3x3 rotZ(float a) {
    float c = cos(a), s = sin(a);
    return float3x3(float3(c, s, 0), float3(-s, c, 0), float3(0, 0, 1));
}

/// A studio: graded backdrop, a large key softbox upper left, a thin strip light on the right.
float3 environment(float3 r, float dark) {
    float up = saturate(r.y * 0.5 + 0.5);
    float3 base = dark > 0.5
        ? mix(float3(0.015, 0.016, 0.022), float3(0.11, 0.115, 0.135), up)
        : mix(float3(0.50, 0.52, 0.58), float3(1.0, 1.0, 1.0), up);
    // Key softbox: a rounded rectangle seen in the reflection direction.
    float3 keyDir = normalize(float3(-0.55, 0.62, 0.56));
    float3 keyU = normalize(cross(keyDir, float3(0, 0, 1)));
    float3 keyV = cross(keyU, keyDir);
    float facing = dot(r, keyDir);
    float2 q = float2(dot(r, keyU), dot(r, keyV)) / max(facing, 0.001);
    float key = facing > 0.0 ? smoothstep(0.06, 0.0, max(abs(q.x) - 0.42, abs(q.y) - 0.22)) : 0.0;
    // Strip light on the right edge.
    float strip = smoothstep(0.985, 0.998, dot(normalize(float3(r.x, r.y * 0.15, r.z)), normalize(float3(0.92, 0.0, 0.38))));
    return base + float3(key * (dark > 0.5 ? 2.6 : 4.0)) + float3(strip * 1.6);
}

/// A glowing ring in the plane through the origin with normal `n`. Returns intensity, sets `t`.
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

} // namespace core

struct Uniforms {
    float2 size;
    float time;
    float energy;
    float2 tilt;
    float dark;
    float rings;
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

fragment float4 coreFragment(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 position = in.position.xy;
    float2 size = u.size;
    float time = u.time;
    float energy = u.energy;
    float2 tilt = u.tilt;
    float dark = u.dark;
    float rings = u.rings;
    float4 accentColor = u.accent;
    using namespace core;

    float scale = min(size.x, size.y) * 0.5;
    float2 uv = (position - size * 0.5) / scale;
    uv.y = -uv.y;
    float px = 1.0 / scale;

    float3 accent = float3(accentColor.rgb);
    float3 hot = mix(accent, float3(1.0, 0.97, 0.92), 0.6);
    float speed = 0.22 + 0.6 * energy;
    float radius = rings > 0.5 ? 0.56 : 0.9;

    float3x3 view = rotY(tilt.x) * rotX(tilt.y);
    float3 ro = view * float3(uv, 3.0);
    float3 rd = view * float3(0, 0, -1);

    // Sphere intersection.
    float b = dot(ro, rd);
    float c = dot(ro, ro) - radius * radius;
    float h = b * b - c;
    float tSphere = h > 0.0 ? -b - sqrt(h) : 1e9;
    float distance = length(uv);
    float coverage = smoothstep(radius + px, radius - px, distance);

    float3 col = float3(0);
    float alpha = 0.0;

    // Halo behind the sphere.
    float glow = dark > 0.5 ? 0.42 : 0.22;
    float halo = exp(-max(distance - radius, 0.0) * (rings > 0.5 ? 7.0 : 14.0)) * (1.0 - coverage);
    halo *= glow * (0.55 + 0.7 * energy) * (0.92 + 0.08 * sin(time * 1.3));
    col += accent * halo;
    alpha += halo;

    // HUD rings: a solid orbit, a dashed scale that turns, and a short arc that sweeps.
    float3 front = float3(0);
    float frontA = 0.0;
    if (rings > 0.5) {
        float3x3 precess = rotY(time * 0.11 * speed) * rotZ(0.12 * sin(time * 0.07));
        float w = 1.7 * px;
        float t1, t2, t3;
        float r1 = ring(ro, rd, precess * normalize(float3(0.12, 1.0, 0.30)), 0.74, w, 0.0, 1.0, 1.0, 0.0, t1) * 0.7;
        float r2 = ring(ro, rd, precess * normalize(float3(-0.35, 1.0, -0.18)), 0.86, w, 72.0, 0.55, 1.0, time * 0.02 * speed, t2) * 0.45;
        float r3 = ring(ro, rd, rotY(-time * 0.2 * speed) * normalize(float3(0.55, 0.85, 0.12)), 0.66, 1.6 * w, 0.0, 1.0, 0.28, time * 0.09 * speed, t3) * 0.95;
        float3 ringInk = dark > 0.5 ? mix(accent, float3(1.0), 0.25) : accent * 0.75;
        float strength = (dark > 0.5 ? 1.0 : 0.9) * (0.6 + 0.5 * energy);
        float ts[3] = { t1, t2, t3 };
        float rs[3] = { r1, r2, r3 };
        for (int i = 0; i < 3; i++) {
            float k = rs[i] * strength;
            if (ts[i] < tSphere || coverage < 0.5) {
                front += ringInk * k;
                frontA += k;
            } else {
                col += ringInk * k * 0.35;  // seen through the glass
                alpha += k * 0.35;
            }
        }
    }

    // The glass sphere.
    if (h > 0.0) {
        float3 p = ro + rd * tSphere;
        float3 n = normalize(p);
        float ndv = saturate(dot(-rd, n));
        float fresnel = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);
        float3 reflection = environment(reflect(rd, n), dark);

        // March the refracted ray through the interior.
        float3 rdi = refract(rd, n, 1.0 / 1.45);
        float bi = dot(p, rdi);
        float ci = dot(p, p) - radius * radius;
        float tExit = -bi + sqrt(max(bi * bi - ci, 0.0));
        const int steps = 26;
        float dt = tExit / float(steps);
        float coreAcc = 0.0;
        float tendrilAcc = 0.0;
        float3x3 swirl = rotY(time * speed * 0.6) * rotX(time * speed * 0.23);
        for (int i = 0; i < steps; i++) {
            float3 q = p + rdi * (dt * (float(i) + 0.5));
            float d = length(q) / radius;
            float3 qq = swirl * (q / radius) * 3.0;
            float3 flow = float3(0.0, time * speed * 0.8, time * 0.1);
            // Two crossing ridge fields make thin electric filaments.
            float fieldA = fbm(qq + flow);
            float fieldB = fbm(rotX(1.1) * qq * 1.3 - flow * 0.7 + float3(4.1, 2.3, 7.7));
            float tendril = max(pow(1.0 - abs(fieldA * 2.0 - 1.0), 30.0), 0.7 * pow(1.0 - abs(fieldB * 2.0 - 1.0), 36.0));
            // Only some regions carry filaments, so the crystal stays mostly dark.
            tendril *= smoothstep(0.48, 0.72, noise(qq * 0.55 + flow * 0.35 + float3(9.0)));
            float pulse = 0.85 + 0.15 * sin(time * (1.1 + 1.6 * energy));
            coreAcc += exp(-d * d * (24.0 - 7.0 * energy)) * pulse * dt;
            tendrilAcc += tendril * smoothstep(0.95, 0.15, d) * dt;
        }
        coreAcc /= radius;
        tendrilAcc /= radius;
        // Light inside the crystal, tone-mapped so the core glows white-hot without clipping.
        float3 raw = hot * coreAcc * (3.4 + 2.2 * energy) + mix(accent, hot, 0.35) * tendrilAcc * (9.0 + 12.0 * energy);
        float3 inner = 1.0 - exp(-raw * 1.6);

        // Smoky dark crystal: the glow and the studio reflections carry the form.
        float3 body = float3(0.018, 0.02, 0.03);
        float rim = pow(1.0 - ndv, 3.0);
        float3 reflected = reflection * fresnel * (dark > 0.5 ? 1.0 : 0.9);
        float3 sphere = reflected + (inner + body) * (1.0 - fresnel) + accent * rim * 0.28 * (0.6 + 0.6 * energy);
        // Soft occlusion toward the lower right sells the volume.
        sphere *= 0.82 + 0.18 * saturate(dot(n, normalize(float3(-0.5, 0.6, 0.6))) * 0.5 + 0.5);
        float sphereA = saturate(0.9 + fresnel) * coverage;
        sphere *= coverage;

        col = sphere + col * (1.0 - sphereA);
        alpha = sphereA + alpha * (1.0 - sphereA);
    }

    col += front;
    alpha = saturate(alpha + frontA);
    col = min(col, float3(4.0));
    return float4(col, alpha);
}
"""#
}
