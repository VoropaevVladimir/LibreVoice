//
//  GlowRenderer.swift
//  LibreVoice
//

import Foundation

/// The one-shot and cyclic effects that depend on *how long* a state has been showing,
/// rather than on the voice.
///
/// These are what turn a set of static looks into an arc with a beginning and an end:
/// a breath while thinking, a single swell on completion, a brief accent on failure.
/// All are pure functions of elapsed time, so they are trivially testable and cannot
/// drift out of step with the renderer.
nonisolated enum GlowRenderer {
    /// The glow multiplier for this frame.
    static func modulation(for state: ExperienceState, age: TimeInterval) -> Float {
        switch state {
        case .thinking:
            // A calm breath while the model works — the visual equivalent of "still
            // here", without a spinner's implication of counting.
            1.0 + 0.25 * Float(sin(age * 1.25))

        case .completed:
            // One swell and done. A repeating pulse would keep asking for attention
            // after the moment that deserved it has passed.
            1.0 + 0.55 * Float(sin(min(age, Self.completionSwell) / Self.completionSwell * .pi))

        case .error:
            // Light drains away rather than flashing: the failure is stated by the
            // absence of energy, not by an alarm.
            Float(max(0.25, 1.0 - age / Self.errorFade))

        default:
            1.0
        }
    }

    /// How far the wave is drawn in toward the centre, `0...1`.
    ///
    /// Only completion contracts: the wave gathers itself in and stops, which reads as
    /// an ending. Error deliberately does *not* — it simply loses energy in place,
    /// because a wave that tidies itself away would look like success.
    static func contraction(for state: ExperienceState, age: TimeInterval) -> Float {
        guard state == .completed else { return 0 }
        return Float(min(1, age / Self.completionSwell))
    }

    /// How strongly the error colour is mixed in, `0...1`.
    ///
    /// Rises quickly, holds briefly, then fades — present long enough to be noticed,
    /// short enough never to become the capsule's resting colour.
    static func errorAccent(for state: ExperienceState, age: TimeInterval) -> Float {
        guard state == .error else { return 0 }
        let rise = min(1, age / 0.25)
        let fall = Float(max(0, 1 - max(0, age - 0.9) / 0.8))
        return Float(rise) * fall
    }

    /// How long completion's single swell and contraction take.
    private static let completionSwell: TimeInterval = 0.9

    /// How long the error state takes to dim to its floor.
    private static let errorFade: TimeInterval = 1.4
}
