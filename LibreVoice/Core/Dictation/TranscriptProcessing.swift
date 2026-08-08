//
//  TranscriptProcessing.swift
//  LibreVoice
//

import Foundation

/// Turns raw recognised text into the text that is actually inserted.
///
/// This is the seam behind the three dictation modes. Recognition is identical in every
/// mode; what differs is this step: ``DictationMode/fast`` passes text through
/// untouched, ``DictationMode/smart`` cleans it up, ``DictationMode/precision`` also
/// applies the user's own terminology. Keeping it a protocol keeps
/// ``DictationCoordinator`` ignorant of what any mode does — and keeps the correction
/// logic a pure, exhaustively testable function from string to string.
nonisolated protocol TranscriptProcessing: Sendable {
    /// Processes settled text according to `mode`.
    ///
    /// Called only for *final* text, never partials: a correction that appears and then
    /// mutates mid-preview would make the live text look unstable, and partials are
    /// never inserted anywhere.
    func process(_ text: String, mode: DictationMode) -> String
}

/// A ``TranscriptProcessing`` that changes nothing, whatever the mode.
///
/// The default for tests and previews, so a ``DictationCoordinator`` under test asserts
/// on the engine's exact output rather than on whatever the current Smart rules do.
nonisolated struct PassthroughTranscriptProcessing: TranscriptProcessing {
    init() {}

    func process(_ text: String, mode: DictationMode) -> String { text }
}
