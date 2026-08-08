//
//  ModeTranscriptProcessor.swift
//  LibreVoice
//

import Foundation

/// The shipped ``TranscriptProcessing``: dispatches each mode to its pipeline.
///
/// Every stage here is deterministic text manipulation, on purpose. "AI correction"
/// as a marketing phrase is easy; shipping a network call or a bundled LLM is not — and
/// v1 promises everything runs offline. What Smart mode actually does is the honest
/// subset that reliably improves Whisper output: whitespace and punctuation hygiene and
/// sentence capitalisation. Precision adds the user's terminology on top. The seams are
/// in place for something heavier later without the coordinator noticing.
nonisolated struct ModeTranscriptProcessor: TranscriptProcessing {
    private let terminology: TerminologyDictionary

    init(terminology: TerminologyDictionary = TerminologyDictionary()) {
        self.terminology = terminology
    }

    func process(_ text: String, mode: DictationMode) -> String {
        switch mode {
        case .fast:
            // Fast promises "exactly as recognised" — only outer whitespace goes,
            // because trailing newlines from the engine are never wanted in a document.
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .smart:
            return SmartTextCorrector.correct(text)
        case .precision:
            return terminology.apply(to: SmartTextCorrector.correct(text))
        }
    }
}

/// The Smart-mode cleanup pass: pure functions over the recognised string.
nonisolated enum SmartTextCorrector {
    /// Applies every correction in reading order.
    static func correct(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        result = collapseWhitespace(in: result)
        result = normalisePunctuationSpacing(in: result)
        result = capitaliseSentences(in: result)
        return result
    }

    /// Runs of spaces and tabs become one space; newlines survive.
    static func collapseWhitespace(in text: String) -> String {
        text.replacing(/[ \t]{2,}/, with: " ")
    }

    /// No space *before* `,.!?;:`, exactly one space (or end/newline) after.
    ///
    /// Whisper occasionally emits " ," when segments join, and "word,next" when they
    /// abut; both read as typos the user then has to fix by hand.
    static func normalisePunctuationSpacing(in text: String) -> String {
        var result = text.replacing(/[ \t]+([,.!?;:])/) { match in
            String(match.output.1)
        }
        result = result.replacing(/([,.!?;:])(\p{L})/) { match in
            "\(match.output.1) \(match.output.2)"
        }
        return result
    }

    /// Uppercases the first letter of the text and of every sentence.
    ///
    /// Locale-independent by design: `uppercased()` on a single `Character` handles
    /// Cyrillic and Latin alike, and text may legitimately mix both mid-dictation.
    static func capitaliseSentences(in text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)

        var atSentenceStart = true
        for character in text {
            if atSentenceStart, character.isLetter {
                result.append(contentsOf: String(character).uppercased())
                atSentenceStart = false
                continue
            }
            switch character {
            case ".", "!", "?", "\n":
                atSentenceStart = true
            case " ", "\t":
                break // space keeps whatever state we were in
            default:
                atSentenceStart = false
            }
            result.append(character)
        }
        return result
    }
}

/// The user's own vocabulary: exact phrases the recogniser keeps getting wrong,
/// replaced with what they actually mean. The Precision-mode dictionary.
///
/// v1 ships the mechanism with a small built-in seed; the editing UI comes later. The
/// type is a value — the whole dictionary is handed in at construction — so tests can
/// exercise it without any storage existing.
nonisolated struct TerminologyDictionary: Sendable {
    /// Replacement pairs, applied longest-first so "libre voice app" wins over "libre voice".
    private let replacements: [(pattern: String, replacement: String)]

    init(replacements: [String: String] = TerminologyDictionary.seed) {
        self.replacements = replacements
            .map { (pattern: $0.key, replacement: $0.value) }
            .sorted { $0.pattern.count > $1.pattern.count }
    }

    /// Corrections that ship in the box: the product's own name, which no Whisper model
    /// can know how to spell.
    static let seed: [String: String] = [
        "либре войс": "LibreVoice",
        "либревойс": "LibreVoice",
        "libre voice": "LibreVoice",
    ]

    /// Replaces every known phrase, case-insensitively, preserving surrounding text.
    func apply(to text: String) -> String {
        var result = text
        for (pattern, replacement) in replacements {
            result = result.replacing(pattern, with: replacement, caseInsensitive: true)
        }
        return result
    }
}

private nonisolated extension String {
    /// Case-insensitive literal replacement without regular-expression escaping worries.
    func replacing(_ pattern: String, with replacement: String, caseInsensitive: Bool) -> String {
        guard !pattern.isEmpty else { return self }
        var result = ""
        var remaining = Substring(self)
        let options: String.CompareOptions = caseInsensitive ? [.caseInsensitive] : []

        while let range = remaining.range(of: pattern, options: options) {
            result += remaining[..<range.lowerBound]
            result += replacement
            remaining = remaining[range.upperBound...]
        }
        result += remaining
        return result
    }
}
