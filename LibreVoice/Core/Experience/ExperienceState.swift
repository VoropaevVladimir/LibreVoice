//
//  ExperienceState.swift
//  LibreVoice
//

import Foundation

/// Where the user-facing experience is in its arc.
///
/// This is the Experience Engine's state machine — deliberately *not* the same enum as
/// ``DictationState``. Dictation states describe the pipeline (a session is preparing,
/// capturing, draining); experience states describe what the person should *feel* is
/// happening (the app is listening, understanding, writing). The two mostly line up,
/// but not always: `completed` exists only here (the pipeline is already idle while the
/// capsule still glows its success), and the mapping is the one place the difference is
/// spelled out.
///
/// Pure and `Sendable`, with the legal transitions encoded, so the arc is unit-testable
/// without a window, a renderer, or a microphone.
nonisolated enum ExperienceState: String, Sendable, Hashable, CaseIterable, Codable {
    /// Nothing happening; the capsule is hidden.
    case idle

    /// The capsule has appeared and is getting ready — the microphone is opening, the
    /// model may still be loading. Brief, but it must exist: without it the capsule
    /// would arrive already pretending to hear, and the first word of a slow start
    /// would land against a wave that was lying about being ready.
    case preparing

    /// The microphone is open; the wave is alive and tracking the voice.
    case listening

    /// Recognition is running; the wave has dissolved into thinking particles.
    case thinking

    /// Text is arriving; characters are being typed out.
    case typing

    /// The session ended well; a brief, calm acknowledgement before hiding.
    case completed

    /// Something failed; a brief, calm acknowledgement of that too.
    case error

    /// The states this state may flow into.
    ///
    /// Anything not listed is a programming error upstream — the coordinator clamps to
    /// legal transitions rather than letting the visual jump arbitrarily.
    var legalNextStates: Set<ExperienceState> {
        switch self {
        case .idle: [.preparing]
        // Cancelled before the microphone opened, or straight through to listening.
        case .preparing: [.listening, .error, .idle]
        case .listening: [.thinking, .typing, .error, .idle]
        case .thinking: [.typing, .completed, .error]
        case .typing: [.thinking, .completed, .error]
        case .completed: [.idle, .preparing]
        case .error: [.idle, .preparing]
        }
    }

    /// Whether moving from here to `next` is part of the designed arc.
    func canTransition(to next: ExperienceState) -> Bool {
        next == self || legalNextStates.contains(next)
    }

    /// Whether the capsule should be on screen in this state.
    var showsCapsule: Bool { self != .idle }
}
