//
//  MorphRenderer.swift
//  LibreVoice
//

import Foundation
import simd

/// Owns the blend between two experience recipes as a transition runs.
///
/// This is the mechanism behind the "never instantly switch state" rule: when the
/// coordinator changes state, nothing jumps — this type notes the time, and every frame
/// reports how far along the designed ``ExperienceTransition`` duration the morph is.
/// The shader then blends recipes (and scatters the wave into particles) by that value.
nonisolated struct MorphRenderer {
    private(set) var fromState: ExperienceState = .idle
    private(set) var toState: ExperienceState = .idle
    private var transitionStart: TimeInterval = 0
    private var duration: TimeInterval = 0.4

    /// Begins morphing toward `state` at `now`.
    ///
    /// A morph interrupted mid-flight starts from the *visual* it reached, not from the
    /// old state's recipe — so rapid state changes stay fluid rather than snapping back.
    mutating func transition(to state: ExperienceState, at now: TimeInterval) {
        guard state != toState else { return }
        let progress = self.progress(at: now)
        // Freeze the current blend as the new starting point.
        fromState = progress < 0.5 ? fromState : toState
        toState = state
        transitionStart = now
        duration = ExperienceTransition.between(fromState, state).duration
    }

    /// How far the current morph has run, `0...1`.
    func progress(at now: TimeInterval) -> Float {
        guard duration > 0 else { return 1 }
        return Float(min(1, max(0, (now - transitionStart) / duration)))
    }

    /// The two recipes and blend factor for this frame.
    func recipes(at now: TimeInterval) -> (from: SIMD4<Float>, to: SIMD4<Float>, morph: Float) {
        (
            ParticleRenderer.recipe(for: fromState.experience),
            ParticleRenderer.recipe(for: toState.experience),
            progress(at: now)
        )
    }
}
