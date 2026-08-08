//
//  ExperienceTransition.swift
//  LibreVoice
//

import Foundation

/// One movement between two ``ExperienceState``s, with how long it should take.
///
/// The brief's rule is "never instantly switch state": every visual change is a timed
/// morph, and the durations are design decisions that belong in one reviewable place —
/// here — rather than scattered as magic numbers through a renderer.
nonisolated struct ExperienceTransition: Sendable, Hashable {
    let from: ExperienceState
    let to: ExperienceState

    /// How long the morph between the two visuals runs.
    let duration: TimeInterval

    init(from: ExperienceState, to: ExperienceState, duration: TimeInterval) {
        self.from = from
        self.to = to
        self.duration = duration
    }

    /// The designed duration for a transition, tuned per pair.
    ///
    /// The distinctive ones: dissolving the wave into thinking particles is the
    /// signature moment and gets time to breathe; error never snaps, because a jolt on
    /// top of a failure reads as blame.
    static func duration(from: ExperienceState, to: ExperienceState) -> TimeInterval {
        switch (from, to) {
        // Waking up: the capsule is still sliding out of the notch, so the visual
        // settles at about the same pace the window arrives.
        case (.idle, .preparing): 0.45
        // Quick, because the user is already speaking by now — a slow bloom here would
        // lag behind their first word.
        case (.preparing, .listening): 0.30
        case (.listening, .thinking): 0.60
        case (.thinking, .typing): 0.35
        case (.typing, .thinking): 0.35
        case (_, .completed): 0.45
        case (.completed, .idle): 0.80
        case (_, .error): 0.50
        case (.error, .idle): 0.60
        default: 0.40
        }
    }

    /// The transition between two states, with its designed duration.
    static func between(_ from: ExperienceState, _ to: ExperienceState) -> ExperienceTransition {
        ExperienceTransition(from: from, to: to, duration: duration(from: from, to: to))
    }

    /// How long ``ExperienceState/completed`` lingers before flowing home to idle.
    static let completedLinger: TimeInterval = 1.2

    /// How long ``ExperienceState/error`` lingers before flowing home to idle.
    static let errorLinger: TimeInterval = 2.2
}
