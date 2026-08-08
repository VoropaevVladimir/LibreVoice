//
//  SegmentJoining.swift
//  LibreVoice
//

import Foundation

/// Joins recognised segments into running text.
///
/// This exists because of a bug worth remembering. Speech engines return each segment
/// trimmed — whisper.cpp calls `trimmingCharacters(in: .whitespacesAndNewlines)` on every
/// one — so concatenating them directly produces `"Привет.Меня зовут"`: a missing space
/// that appears only at segment boundaries, which is why it looks random. Each segment is
/// individually well punctuated; the defect is created by the join.
///
/// The rule is deliberately narrow: add a single space only where running text would
/// obviously have one, and never touch anything else. Anything cleverer would start
/// inventing whitespace the user did not dictate.
nonisolated enum SegmentJoining {
    /// The separator to place between `previous` and `next`, either `" "` or `""`.
    static func separator(between previous: String, and next: String) -> String {
        guard let tail = previous.last, let head = next.first else { return "" }

        // Either side already carries the whitespace.
        if tail.isWhitespace || head.isWhitespace { return "" }

        // Punctuation that closes a word attaches to it: "слово" + "," must not become
        // "слово ,". Quotes and brackets are left alone for the same reason.
        if attaching.contains(head) { return "" }

        // An opening bracket or quote before the next word, or any letter/digit, means a
        // word boundary — that is where the space belongs.
        return " "
    }

    /// Joins `segments` with boundary-aware separators.
    static func joined(_ segments: [String]) -> String {
        segments.reduce(into: "") { result, segment in
            result += separator(between: result, and: segment) + segment
        }
    }

    /// Characters that bind to the word before them, so no space is inserted ahead of
    /// them. Includes the Russian and Latin punctuation whisper actually emits.
    private static let attaching: Set<Character> = [
        ",", ".", "!", "?", ";", ":", ")", "]", "}", "»", "”", "’", "…", "%", "‰",
    ]
}
