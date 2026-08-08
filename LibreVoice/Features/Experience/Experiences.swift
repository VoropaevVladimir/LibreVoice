//
//  Experiences.swift
//  LibreVoice
//

import Foundation
import SwiftUI

/// The visual recipe for one ``ExperienceState``.
///
/// Each experience is data, not behaviour: how much wave, how much particle field, how
/// much glow, how fast everything flows. The renderer blends between two of these as a
/// transition runs, which is what makes every state change a morph instead of a cut.
nonisolated protocol Experience: Sendable {
    var state: ExperienceState { get }

    /// Base amplitude of the liquid wave, before voice reactivity, in `0...1`.
    var waveAmplitude: Double { get }

    /// How much the visual is particles rather than wave, in `0...1`.
    var particleMix: Double { get }

    /// Strength of the glow around the visual, in `0...1`.
    var glow: Double { get }

    /// How fast the field flows, as a time multiplier.
    var flowSpeed: Double { get }

    /// How strongly the microphone level drives the wave, in `0...1`.
    var voiceReactivity: Double { get }
}

/// Waking up: a quiet, level line drawing itself, with the glow already rising.
///
/// Deliberately almost still. This state exists to say "I am here and about to listen",
/// and a wave that moved before there was anything to hear would be a small lie the
/// user learns not to trust.
nonisolated struct PreparingExperience: Experience {
    let state: ExperienceState = .preparing
    let waveAmplitude = 0.07
    let particleMix = 0.0
    let glow = 0.30
    let flowSpeed = 0.5
    let voiceReactivity = 0.0
}

/// The wave is alive and tracking the voice — LibreVoice's signature look.
///
/// `waveAmplitude` is deliberately small: it is the line the wave rests at in silence,
/// not its working size. Everything above it comes from the voice, which is what makes
/// speaking visibly change the picture instead of nudging an already-busy ribbon.
nonisolated struct ListeningExperience: Experience {
    let state: ExperienceState = .listening
    let waveAmplitude = 0.15
    let particleMix = 0.0
    let glow = 0.55
    let flowSpeed = 1.0
    let voiceReactivity = 1.0
}

/// The wave has dissolved into particles that drift, reconnect and morph:
/// "the AI is understanding your speech". Never a spinner.
nonisolated struct ThinkingExperience: Experience {
    let state: ExperienceState = .thinking
    let waveAmplitude = 0.10
    let particleMix = 1.0
    let glow = 0.70
    let flowSpeed = 0.55
    let voiceReactivity = 0.0
}

/// Text is arriving; the field settles into a calm, forward-flowing pulse.
nonisolated struct TypingExperience: Experience {
    let state: ExperienceState = .typing
    let waveAmplitude = 0.16
    let particleMix = 0.25
    let glow = 0.50
    let flowSpeed = 1.4
    let voiceReactivity = 0.0
}

/// A brief, calm acknowledgement that it worked.
nonisolated struct CompletedExperience: Experience {
    let state: ExperienceState = .completed
    let waveAmplitude = 0.08
    let particleMix = 0.0
    let glow = 0.85
    let flowSpeed = 0.4
    let voiceReactivity = 0.0
}

/// Something failed. Quiet, not alarming — a jolt on top of a failure reads as blame.
nonisolated struct ErrorExperience: Experience {
    let state: ExperienceState = .error
    let waveAmplitude = 0.06
    let particleMix = 0.15
    let glow = 0.40
    let flowSpeed = 0.25
    let voiceReactivity = 0.0
}

/// Idle: effectively invisible; exists so every state has a recipe to blend from.
nonisolated struct IdleExperience: Experience {
    let state: ExperienceState = .idle
    let waveAmplitude = 0.02
    let particleMix = 0.0
    let glow = 0.0
    let flowSpeed = 0.3
    let voiceReactivity = 0.0
}

nonisolated extension ExperienceState {
    /// The visual recipe for this state.
    var experience: any Experience {
        switch self {
        case .idle: IdleExperience()
        case .preparing: PreparingExperience()
        case .listening: ListeningExperience()
        case .thinking: ThinkingExperience()
        case .typing: TypingExperience()
        case .completed: CompletedExperience()
        case .error: ErrorExperience()
        }
    }
}

nonisolated extension DictationMode {
    /// The mode's visual identity: Fast is blue, Smart is purple, Precision is gold.
    var themeColor: Color {
        switch self {
        case .fast: Color(red: 0.04, green: 0.52, blue: 1.0)
        case .smart: Color(red: 0.75, green: 0.35, blue: 0.95)
        case .precision: Color(red: 1.0, green: 0.72, blue: 0.20)
        }
    }
}
