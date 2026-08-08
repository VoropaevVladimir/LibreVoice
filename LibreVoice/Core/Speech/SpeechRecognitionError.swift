//
//  SpeechRecognitionError.swift
//  LibreVoice
//

import Foundation

/// Something that stopped a speech engine from transcribing.
nonisolated enum SpeechRecognitionError: LocalizedError, Sendable, Equatable {
    /// No engine is registered under this identifier.
    ///
    /// In practice this means a previously selected engine was removed from the build
    /// while its identifier is still stored in the user's settings.
    case unknownEngine(SpeechEngineID)

    /// The engine exists but cannot run on this Mac — wrong chip, missing framework.
    case engineUnavailable(reason: String)

    /// The engine needs a model that has not been downloaded yet.
    case modelNotInstalled(name: String)

    /// The engine cannot transcribe the requested language.
    case unsupportedLocale(Locale)

    /// The engine failed while transcribing.
    case transcriptionFailed(reason: String)

    /// Transcription was cancelled before it finished.
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unknownEngine(let id):
            String(localized: "The speech engine “\(id.rawValue)” isn't available in this version of LibreVoice.")
        case .engineUnavailable(let reason):
            String(localized: "This speech engine can't run on your Mac: \(reason)")
        case .modelNotInstalled(let name):
            String(localized: "The speech model “\(name)” hasn't been downloaded yet.")
        case .unsupportedLocale(let locale):
            String(localized: "This engine can't transcribe \(locale.identifier).")
        case .transcriptionFailed(let reason):
            String(localized: "Transcription failed: \(reason)")
        case .cancelled:
            String(localized: "Transcription was cancelled.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unknownEngine, .engineUnavailable:
            String(localized: "Choose a different speech engine in LibreVoice Settings.")
        case .modelNotInstalled:
            String(localized: "Download the model in LibreVoice Settings › Speech Engine.")
        case .unsupportedLocale:
            String(localized: "Choose a different language, or a different engine.")
        case .transcriptionFailed, .cancelled:
            nil
        }
    }
}
