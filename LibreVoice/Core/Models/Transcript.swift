//
//  Transcript.swift
//  LibreVoice
//

import Foundation

/// The text produced by a dictation session.
///
/// Separates settled text from the in-flight guess, because the two are used
/// differently: `committed` may be typed into another app, `pending` may only be shown
/// as a preview — it is still liable to change.
///
/// Held only in memory and dropped when the session ends. LibreVoice does not keep a
/// history of what was said, and this type is the reason that promise is structural
/// rather than a matter of remembering not to write a file.
nonisolated struct Transcript: Sendable, Equatable {
    /// Segments the engine considers final, in order.
    private(set) var committed: [TranscriptionSegment] = []

    /// The current partial result, if the engine is producing one.
    private(set) var pending: TranscriptionSegment?

    init() {}

    /// The settled text.
    ///
    /// Joined through ``SegmentJoining`` rather than concatenated: engines trim every
    /// segment, so a plain `joined()` swallows the space at each boundary and produces
    /// "Привет.Меня зовут".
    var committedText: String {
        SegmentJoining.joined(committed.map(\.text))
    }

    /// The settled text plus the current guess — what the user should see.
    var displayText: String {
        let settled = committedText
        guard let pending = pending?.text else { return settled }
        return settled + SegmentJoining.separator(between: settled, and: pending) + pending
    }

    /// Whether anything has been recognised yet.
    var isEmpty: Bool {
        committed.isEmpty && pending == nil
    }

    /// Applies `event`, returning the text that became final, if any.
    ///
    /// The return value is what the caller inserts into the frontmost app: it is
    /// exactly the newly settled text, so a caller that inserts it on every event
    /// types each word once and never types a partial.
    @discardableResult
    mutating func apply(_ event: TranscriptionEvent) -> String? {
        switch event {
        case .partial(let segment):
            pending = segment
            return nil

        case .final(let segment):
            pending = nil
            // The separator has to be part of what the caller inserts, not just part of
            // `committedText`: in Fast and Smart each settled segment is typed into the
            // user's app as it arrives, so a space missing here is a space missing in
            // their document.
            let separator = SegmentJoining.separator(between: committedText, and: segment.text)
            committed.append(segment)
            return separator + segment.text

        case .completed:
            // Anything still pending when the engine finishes will never be revised,
            // so promote it rather than silently dropping the user's last words.
            guard let promoted = pending else { return nil }
            pending = nil
            let separator = SegmentJoining.separator(between: committedText, and: promoted.text)
            committed.append(promoted)
            return separator + promoted.text
        }
    }

    /// Replaces everything with `text`, as a single settled segment.
    ///
    /// Exists for Precision enhancement: after the language model improves the batch,
    /// what the transcript shows must be what was actually inserted — a preview of text
    /// the user never received would be a small lie.
    mutating func replaceCommitted(with text: String) {
        committed = [TranscriptionSegment(text: text)]
        pending = nil
    }

    /// Discards all text.
    mutating func reset() {
        committed.removeAll()
        pending = nil
    }
}
