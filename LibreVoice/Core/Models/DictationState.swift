//
//  DictationState.swift
//  LibreVoice
//

import Foundation

/// Something that went wrong during a dictation session.
///
/// Wraps the failures of the individual services into one type the UI can present,
/// so views never switch over four unrelated error enums.
nonisolated enum DictationError: LocalizedError, Sendable, Equatable {
    case audio(AudioCaptureError)
    case speech(SpeechRecognitionError)
    case textInsertion(TextInsertionError)

    /// No speech engine is available on this Mac.
    case noEngineAvailable

    var errorDescription: String? {
        switch self {
        case .audio(let error): error.errorDescription
        case .speech(let error): error.errorDescription
        case .textInsertion(let error): error.errorDescription
        case .noEngineAvailable: String(localized: "No speech engine is available.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .audio(let error): error.recoverySuggestion
        case .speech(let error): error.recoverySuggestion
        case .textInsertion(let error): error.recoverySuggestion
        case .noEngineAvailable: String(localized: "Check LibreVoice Settings › Speech Engine.")
        }
    }
}

/// Where a dictation session currently is.
///
/// The live audio level is deliberately *not* a payload of `.listening`. Attaching it
/// would republish the state dozens of times a second and redraw every view observing
/// it, when only the meter cares. The level lives beside the state instead.
nonisolated enum DictationState: Sendable, Equatable {
    /// Not dictating. The resting state.
    case idle

    /// Starting up: checking permissions, loading the engine, opening the microphone.
    case preparing

    /// Capturing audio and transcribing it.
    case listening

    /// The microphone is closed; the engine is finishing the last of the audio.
    case finishing

    /// The session ended in failure. Carries the reason so the UI can explain it.
    case failed(DictationError)

    /// Whether a session is underway.
    var isActive: Bool {
        switch self {
        case .preparing, .listening, .finishing: true
        case .idle, .failed: false
        }
    }

    /// Whether the toggle should read "start" rather than "stop".
    var canStart: Bool {
        switch self {
        case .idle, .failed: true
        case .preparing, .listening, .finishing: false
        }
    }
}
