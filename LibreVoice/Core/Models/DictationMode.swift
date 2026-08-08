//
//  DictationMode.swift
//  LibreVoice
//

import Foundation

/// How much processing happens between recognition and insertion.
///
/// The mode is a product concept, not an engine concept: every mode uses the same
/// whisper.cpp recognition. What differs is the post-processing pipeline the transcript
/// runs through afterwards, and the visual identity the Experience Engine gives the
/// session. Keeping the enum in `Core` lets the pipeline, the settings and the UI all
/// speak the same three words.
nonisolated enum DictationMode: String, Sendable, CaseIterable, Identifiable, Codable {
    /// Voice → text → insert. No correction, minimum latency.
    case fast

    /// Voice → text → correction (capitalisation, punctuation spacing, artefact
    /// cleanup) → insert. The default.
    case smart

    /// Everything Smart does, plus the user's terminology dictionary and custom rules.
    case precision

    var id: String { rawValue }

    /// The mode used when the user has never chosen one.
    static let `default`: DictationMode = .smart

    /// The name shown in pickers.
    var displayName: String {
        switch self {
        case .fast: String(localized: "Fast")
        case .smart: String(localized: "Smart")
        case .precision: String(localized: "Precision")
        }
    }

    /// One line describing the trade-off, for the picker.
    var summary: String {
        switch self {
        case .fast: String(localized: "Instant dictation. Text is inserted exactly as recognised.")
        case .smart: String(localized: "Balanced speed and quality. Cleans up capitalisation and punctuation.")
        case .precision: String(localized: "Maximum quality. Applies your terminology and, with a local model, your personal writing style.")
        }
    }

    /// The SF Symbol shown beside the name.
    var symbolName: String {
        switch self {
        case .fast: "bolt.fill"
        case .smart: "sparkles"
        case .precision: "scope"
        }
    }
}
