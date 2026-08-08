//
//  TextEnhancing.swift
//  LibreVoice
//

import Foundation

/// Improves recognised text with the user's personal writing profile.
///
/// This is the seam between dictation and the local language model. The coordinator
/// knows only this protocol: it asks whether enhancement is worth attempting, and if so
/// hands over the finished transcript. Everything behind it — profile files, context
/// building, model loading and unloading — is the enhancer's business.
///
/// The contract is deliberately failure-tolerant: `enhance` may throw, and the caller's
/// duty is to fall back to the unenhanced text. Dictation that loses the user's words
/// because a language model failed would be worse than no enhancement at all.
nonisolated protocol TextEnhancing: Sendable {
    /// Whether enhancement can actually run under `configuration`.
    ///
    /// `false` when anything required is missing — no model selected, the model not
    /// installed, the style strength at zero, or no user prompt imported. The caller
    /// uses this *before* a session to decide between per-segment insertion and
    /// batch-then-enhance, so it must be cheap and must not load the model.
    func isReady(_ configuration: EnhancementConfiguration) async -> Bool

    /// Returns `text` improved according to the user's profile.
    ///
    /// Meaning, structure and terminology must survive; only punctuation, grammar,
    /// formatting and readability may change. Implementations enforce this through the
    /// runtime context they build — see `RuntimeContextBuilder`.
    func enhance(_ text: String, configuration: EnhancementConfiguration) async throws -> String
}

/// Why enhancement could not run or produce a result.
nonisolated enum EnhancementError: LocalizedError, Sendable, Equatable {
    /// No language-model runtime is embedded in this build.
    case runtimeUnavailable

    /// The selected model is not installed (or none is selected).
    case modelNotInstalled

    /// The user has no personal prompt, which is required by design: LibreVoice never
    /// writes the system prompt itself.
    case promptMissing

    /// The model failed to load or generate.
    case generationFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            String(localized: "This build has no local language model runtime.")
        case .modelNotInstalled:
            String(localized: "The selected language model isn't installed.")
        case .promptMissing:
            String(localized: "Your writing profile is empty.")
        case .generationFailed(let reason):
            String(localized: "The language model couldn't improve the text: \(reason)")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .runtimeUnavailable:
            String(localized: "Update LibreVoice to a build that includes the language model runtime.")
        case .modelNotInstalled:
            String(localized: "Download a language model in Settings › Precision.")
        case .promptMissing:
            String(localized: "Write your personal prompt in Settings › Writing Profile.")
        case .generationFailed:
            String(localized: "Your dictated text was inserted unchanged.")
        }
    }
}
