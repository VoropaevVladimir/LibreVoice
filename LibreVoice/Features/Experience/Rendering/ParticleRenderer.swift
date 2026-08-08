//
//  ParticleRenderer.swift
//  LibreVoice
//

import Foundation
import simd

/// Packs an ``Experience`` into the recipe vector the shader consumes.
///
/// The particle system itself is procedural, computed per-pixel in `Shaders.metal` — no
/// buffers to fill, nothing to allocate per frame, which is much of why 120 Hz costs so
/// little. What the CPU contributes is this packing: how much of the field is particles,
/// how bright, how fast it flows.
nonisolated enum ParticleRenderer {
    /// The shader's recipe layout: x amplitude, y particleMix, z glow, w flowSpeed.
    static func recipe(for experience: any Experience) -> SIMD4<Float> {
        SIMD4(
            Float(experience.waveAmplitude),
            Float(experience.particleMix),
            Float(experience.glow),
            Float(experience.flowSpeed)
        )
    }
}
