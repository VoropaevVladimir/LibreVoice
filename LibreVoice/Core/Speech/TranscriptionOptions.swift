//
//  TranscriptionOptions.swift
//  LibreVoice
//

import Foundation

/// How a single transcription run should behave.
///
/// Passed per-run rather than set on the engine, so an engine instance holds no
/// mutable configuration and two runs can never interfere with each other.
nonisolated struct TranscriptionOptions: Sendable, Equatable {
    /// The language to transcribe.
    let locale: Locale

    /// Whether the engine should emit ``TranscriptionEvent/partial(_:)`` events.
    ///
    /// Partials cost extra work, so an engine may skip them when nothing is displaying
    /// live text.
    let includePartialResults: Bool

    init(locale: Locale = .current, includePartialResults: Bool = true) {
        self.locale = locale
        self.includePartialResults = includePartialResults
    }

    /// Live transcription in the user's current language.
    static let `default` = TranscriptionOptions()
}
