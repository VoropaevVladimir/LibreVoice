//
//  CapsuleUniforms.swift
//  LibreVoice
//

import simd

/// Everything the capsule shader needs for one frame.
///
/// - Important: The memory layout must match `CapsuleUniforms` in `Shaders.metal`
///   field-for-field; both sides are plain float structs to keep that trivially true.
nonisolated struct CapsuleUniforms {
    /// Seconds since rendering started.
    var time: Float = 0

    /// The smoothed microphone level driving the wave, in `0...1`.
    var level: Float = 0

    /// Slow-moving speech energy: how animated the voice has been lately.
    var energy: Float = 0

    /// Recipe blended *from* (amplitude, particles, glow, flow).
    var recipeA: SIMD4<Float> = .zero

    /// Recipe blended *to*.
    var recipeB: SIMD4<Float> = .zero

    /// Blend position between the recipes, `0...1`, eased.
    var morph: Float = 0

    /// Seconds spent in the current state, for effects that play once rather than loop:
    /// the single glow swell on completion, the brief red accent on error.
    var stateAge: Float = 0

    /// How far the wave is drawn in from the capsule's ends, `0...1`.
    ///
    /// Completion contracts the wave toward the centre before stillness — an ending
    /// that is *shown* rather than announced.
    var contraction: Float = 0

    /// How much of the error accent is mixed over the theme colour, `0...1`.
    var errorAccent: Float = 0

    /// The theme colour (premultiplied later in the shader).
    var tint: SIMD4<Float> = SIMD4(0.3, 0.6, 1.0, 1.0)

    /// Drawable size in pixels.
    var size: SIMD2<Float> = SIMD2(1, 1)

    /// Padding to keep the struct 16-byte aligned for Metal.
    var padding: SIMD2<Float> = .zero

    /// The error accent: a desaturated red, never a warning red. It is mixed in briefly
    /// and quietly, because a failure the user did not cause should not feel like an
    /// accusation.
    static let errorTint = SIMD3<Float>(0.92, 0.32, 0.30)
}
