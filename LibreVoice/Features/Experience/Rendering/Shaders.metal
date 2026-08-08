//
//  Shaders.metal
//  LibreVoice
//
//  The capsule's entire visual: an organic liquid wave (listening), a particle field
//  (thinking), and everything between them as a continuous morph. One full-screen
//  triangle, one fragment shader, no textures — cheap enough for 120 Hz.
//

#include <metal_stdlib>
using namespace metal;

// Must match CapsuleUniforms.swift field-for-field.
struct CapsuleUniforms {
    float  time;
    float  level;
    float  energy;
    float4 recipeA;   // x amplitude, y particleMix, z glow, w flowSpeed
    float4 recipeB;
    float  morph;
    float  stateAge;
    float  contraction;
    float  errorAccent;
    float4 tint;
    float2 size;
    float2 padding;
};

struct FullscreenVertex {
    float4 position [[position]];
    float2 uv;
};

// One triangle that covers the screen; uv in 0...1.
vertex FullscreenVertex capsule_vertex(uint vertexID [[vertex_id]]) {
    float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    FullscreenVertex out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = positions[vertexID] * 0.5 + 0.5;
    return out;
}

// ---- Noise ------------------------------------------------------------------

static float hash21(float2 p) {
    p = fract(p * float2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

static float2 hash22(float2 p) {
    return float2(hash21(p), hash21(p + 17.17));
}

// Smooth value noise, enough organic wobble for a wave; no texture fetches.
static float noise21(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ---- The liquid wave (listening) -------------------------------------------

// Height of the wave centreline at x (0...1), in -0.5...0.5-ish units.
// `seed` shifts the phases so parallax layers never move in lockstep.
static float waveHeight(float x, float time, float level, float energy, float amplitude, float flow, float seed, float contraction) {
    // Volume drives *tempo* as well as height, but gently. An earlier version coupled
    // them hard and the result read as jittery rather than alive — the crest snapped
    // about instead of rolling. Water moves slowly even in a storm; what changes with
    // force is its size and texture, much more than its speed.
    float t = time * flow * (1.0 + level * 0.35) + seed * 7.31;

    // Finer harmonics fade in with volume, so a loud passage grows new detail rather
    // than scaling the same three sine waves — the difference between "louder" and
    // "more animated".
    float detail = 0.35 + level * 0.75;
    // Drifting layers at irrational frequency ratios — never repeats, reads as liquid
    // rather than oscilloscope. The time multipliers are deliberately low: they set how
    // fast the surface travels, and this is the single biggest lever on whether the
    // capsule feels calm or frantic.
    float h = sin(x * 6.2831 * 1.7 + t * 0.85 + seed) * 0.42
            + sin(x * 6.2831 * 3.1 - t * 0.55 + seed * 2.0) * 0.27
            + sin(x * 6.2831 * 5.3 + t * 1.40) * 0.16 * detail
            + sin(x * 6.2831 * 8.9 - t * 1.95 + seed) * 0.10 * level;

    // Organic wobble so the crest line is never geometric; it roughens as the voice
    // gets louder.
    h += (noise21(float2(x * 4.0 + seed * 3.0, t * 0.28)) - 0.5) * (0.5 + level * 1.1);

    // The voice dominates the height. `amplitude` is now only the resting line the
    // wave settles to in silence, not the bulk of its size.
    float drive = amplitude + level * 1.45 + energy * 0.30;
    // Soften toward the capsule's ends so the wave lives in the middle. `contraction`
    // pulls those ends inward, drawing the wave into the centre as a session closes.
    float inset = 0.18 + contraction * 0.30;
    float envelope = smoothstep(0.0, inset, x) * smoothstep(1.0, 1.0 - inset, x);
    // `tanh` saturates instead of clipping: a shout still reads as louder than speech,
    // but the crest can never run off the top of the capsule and cut flat against the
    // edge — which a linear scale did as soon as the pill got short.
    return tanh(h * drive * envelope * 1.5) * 0.34;
}

/// Wave light contribution: `x` is core brightness, `y` is a white-highlight factor.
///
/// Three crests at different depths give the water parallax; exponential falloff
/// instead of hard smoothsteps is what makes the light *bloom* instead of banding.
static float2 waveField(float2 uv, constant CapsuleUniforms& u, float amplitude, float flow) {
    float aspect = u.size.x / max(u.size.y, 1.0);
    float field = 0.0;
    float highlight = 0.0;

    // (depth seed, speed, amplitude share, brightness)
    const float4 layers[3] = {
        float4(0.0, 1.00, 1.00, 1.00),   // main crest
        float4(1.0, 0.62, 0.80, 0.38),   // slower wave behind it
        float4(2.0, 1.45, 0.55, 0.22),   // faster shimmer in front
    };

    for (int i = 0; i < 3; i++) {
        float4 L = layers[i];
        float centre = waveHeight(uv.x, u.time, u.level, u.energy, amplitude * L.z, flow * L.y, L.x, u.contraction);
        float d = fabs(uv.y - 0.5 - centre);
        // The core's thickness is measured in *pixels*, not in fractions of the capsule.
        // Expressed as a UV falloff it would thin out every time the pill got shorter,
        // until the crest aliased into a flickering hairline; in pixels it stays the
        // same crisp ~2px filament at any capsule size.
        float dPx = d * u.size.y;
        float core = exp(-dPx * dPx * 0.16);
        float bloom = exp(-d * 9.0) * 0.30;
        field += (core + bloom) * L.w;
        // The main crest carries a white glint where it peaks — sunlight on water.
        if (i == 0) {
            float peak = clamp(fabs(centre) * (6.0 + u.level * 8.0), 0.0, 1.0);
            highlight += core * peak;
        }
    }

    // A faint mirrored shimmer below the waterline adds depth for almost nothing.
    float reflected = waveHeight(uv.x, u.time, u.level, u.energy, amplitude, flow, 0.0, u.contraction);
    float dr = fabs(uv.y - 0.5 + reflected * 1.6);
    field += exp(-dr * 11.0) * 0.10;

    (void)aspect;
    return float2(field, highlight);
}

// ---- The particle field (thinking) -----------------------------------------

// Grid-cell particles that drift, twinkle and reconnect. Procedural — no buffers.
static float particleField(float2 uv, constant CapsuleUniforms& u, float flow) {
    float t = u.time * flow;
    float2 grid = uv * float2(14.0, 4.0);
    float2 cell = floor(grid);
    float field = 0.0;

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 neighbour = cell + float2(x, y);
            float2 seed = hash22(neighbour);
            // Each particle orbits inside its cell, at its own pace and radius.
            float2 orbit = 0.5 + 0.38 * float2(sin(t * (0.6 + seed.x) + seed.y * 6.28),
                                               cos(t * (0.5 + seed.y) + seed.x * 6.28));
            float2 position = (neighbour + orbit) / float2(14.0, 4.0);
            float d = length((uv - position) * float2(u.size.x / u.size.y, 1.0));
            // Sized in pixels, for the same reason the wave's core is: a UV-relative
            // radius shrinks with the capsule, and the swarm fades to dust on a short
            // pill. Individual radii and a slow twinkle keep it from looking stamped
            // out of one template.
            float dPx = d * u.size.y;
            float sharpness = 0.10 + seed.x * 0.18;
            float twinkle = 0.70 + 0.30 * sin(t * (2.0 + seed.y * 3.0) + seed.x * 40.0);
            // Bright kernel + soft halo; overlapping halos read as connections.
            field += (exp(-dPx * dPx * sharpness) + exp(-dPx * 0.35) * 0.16) * twinkle;
        }
    }
    // Vertical envelope keeps particles inside the capsule.
    field *= smoothstep(0.0, 0.25, uv.y) * smoothstep(1.0, 0.75, uv.y);
    return field;
}

// ---- Composition ------------------------------------------------------------

fragment float4 capsule_fragment(FullscreenVertex in [[stage_in]],
                                 constant CapsuleUniforms& u [[buffer(0)]]) {
    // Eased blend between the two recipes: every state change is a morph.
    float m = smoothstep(0.0, 1.0, u.morph);
    float amplitude = mix(u.recipeA.x, u.recipeB.x, m);
    float particles = mix(u.recipeA.y, u.recipeB.y, m);
    float glow      = mix(u.recipeA.z, u.recipeB.z, m);
    float flow      = mix(u.recipeA.w, u.recipeB.w, m);

    float2 wave = waveField(in.uv, u, amplitude, flow) * (1.0 - particles);
    float dots = particleField(in.uv, u, flow) * particles;
    float field = wave.x + dots;

    // During the morph itself, scatter the wave: it visibly dissolves into particles
    // rather than crossfading. Strongest mid-transition.
    float dissolve = particles * (1.0 - particles) * 4.0 * m * (1.0 - m);
    field += particleField(in.uv * 1.7 + 3.1, u, flow * 1.6) * dissolve * 0.5;

    // A whisper of ambient light inside the glass, so the capsule reads as a lit
    // volume rather than a black slot; follows the voice a little.
    float ambient = exp(-fabs(in.uv.y - 0.5) * 3.5) * (0.05 + u.level * 0.05) * glow;

    // The error accent, mixed over the theme colour rather than replacing it. Kept
    // desaturated and brief: a failure the user did not cause should register, not
    // accuse. `errorAccent` is already faded in and out on the CPU side.
    float3 baseTint = mix(u.tint.rgb, float3(0.92, 0.32, 0.30), u.errorAccent);

    // Colour grading: the tint carries the field; crest highlights lift toward white;
    // glow deepens the tint's own bloom.
    float3 colour = baseTint * (field + field * glow * 0.8 + ambient);
    // Highlights stay white while listening but take the accent's colour during an
    // error, so nothing sparkles cheerfully over a failure.
    colour += mix(float3(1.0), baseTint, u.errorAccent) * wave.y * 0.55;

    // Filmic-ish soft knee instead of a hard clamp — no clipped, flat cores.
    colour = colour / (colour + 0.55);
    colour *= 1.35;

    float alpha = clamp(1.0 - exp(-(field + ambient) * 1.6), 0.0, 0.92);
    return float4(colour * alpha, alpha);
}
