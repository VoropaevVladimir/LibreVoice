//
//  TranscriptionEvent.swift
//  LibreVoice
//

import Foundation

/// A piece of recognised text.
nonisolated struct TranscriptionSegment: Sendable, Equatable, Identifiable {
    let id: UUID

    /// The recognised text.
    let text: String

    /// The span of audio this text came from, measured from the start of the session.
    /// `nil` when the engine does not report timings.
    let timeRange: ClosedRange<TimeInterval>?

    /// The engine's confidence in `text`, in `0...1`. `nil` when unreported.
    let confidence: Double?

    init(
        id: UUID = UUID(),
        text: String,
        timeRange: ClosedRange<TimeInterval>? = nil,
        confidence: Double? = nil
    ) {
        self.id = id
        self.text = text
        self.timeRange = timeRange
        self.confidence = confidence
    }
}

/// Something a ``SpeechRecognitionEngine`` produced while transcribing.
///
/// The partial/final split is what lets the UI show words as they are spoken while
/// only ever committing stable text to another app. Engines that cannot produce
/// partials simply never emit ``partial(_:)``; consumers need no special case.
nonisolated enum TranscriptionEvent: Sendable, Equatable {
    /// A best guess that may still change as more audio arrives.
    ///
    /// Must never be inserted into another application — it will be revised.
    case partial(TranscriptionSegment)

    /// Text the engine considers settled. It will not be revised.
    case final(TranscriptionSegment)

    /// The engine has consumed all audio and emitted all text.
    case completed
}
