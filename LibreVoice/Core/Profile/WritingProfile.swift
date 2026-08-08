//
//  WritingProfile.swift
//  LibreVoice
//

import Foundation

/// The user's personal prompt: one piece of plain text, and nothing else.
///
/// This replaces an earlier design of six Markdown files (PROMPT, STYLE, TERMINOLOGY,
/// VOCABULARY, FORMATTING, EXAMPLES) that were imported separately and assembled at run
/// time. That scheme asked the user to manage a small filesystem and asked the app to
/// parse it; both were complexity in service of something a single prompt does better.
/// What reaches the model is now exactly what the user can see and edit — no assembly,
/// no parsing, no hidden transformation.
nonisolated struct WritingProfile: Sendable, Equatable {
    /// The prompt, verbatim. Passed to the model as its system prompt.
    var prompt: String

    init(prompt: String = "") {
        self.prompt = prompt
    }

    /// Whether this profile can drive an enhancement.
    ///
    /// An empty prompt is not an error — it is simply a profile that has not been
    /// written yet, and Precision falls back to rules-only correction.
    var isConfigured: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The largest prompt accepted. Generous for prose; small enough that a pasted
    /// dataset or a mis-copied document is caught before it reaches a model whose whole
    /// context it would consume.
    static let characterLimit = 20_000

    /// The starting prompt, used on first run and by "Reset to default".
    ///
    /// Deliberately conservative: it corrects and nothing more. A default that tried to
    /// impose a voice would be the app writing on the user's behalf, which is precisely
    /// what the personal prompt exists to prevent. Written in English because it is
    /// addressed to the model, not to the reader — the dictated text keeps its own
    /// language, and rule four says so explicitly.
    static let defaultPrompt = """
    You are my personal editor for dictated text.

    Improve punctuation, spacing, capitalisation and obvious grammatical slips.

    Preserve everything else exactly as I said it:
    - Keep my words, my word order and my phrasing.
    - Keep every fact, name, number and technical term unchanged.
    - Keep the language I dictated in.
    - Never add, remove, summarise, expand or explain anything.

    Reply with the corrected text and nothing else.
    """

    /// The default profile.
    static let `default` = WritingProfile(prompt: defaultPrompt)
}

/// Why a prompt could not be saved.
nonisolated enum WritingProfileError: LocalizedError, Sendable, Equatable {
    /// The prompt is longer than ``WritingProfile/characterLimit``.
    case tooLong(characters: Int, limit: Int)

    /// The prompt could not be written to disk.
    case notSaved(reason: String)

    var errorDescription: String? {
        switch self {
        case .tooLong(let characters, let limit):
            String(localized: "The prompt is \(characters) characters — longer than the \(limit) character limit.")
        case .notSaved(let reason):
            String(localized: "The prompt couldn't be saved: \(reason)")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .tooLong:
            String(localized: "A personal prompt is a short set of instructions, not a document. Shorten it and try again.")
        case .notSaved:
            String(localized: "Check that LibreVoice can write to your Application Support folder.")
        }
    }
}
