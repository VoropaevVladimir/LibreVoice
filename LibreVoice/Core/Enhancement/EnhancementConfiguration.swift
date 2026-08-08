//
//  EnhancementConfiguration.swift
//  LibreVoice
//

import Foundation

/// Everything the Precision enhancement stage needs to know from the user's settings.
///
/// A value, captured once at the start of a dictation session, so a mid-session settings
/// change cannot switch models or strength halfway through one utterance. The coordinator
/// builds it on the main actor and hands it across to the enhancer, which keeps the
/// enhancer free of any dependency on `AppSettings`.
nonisolated struct EnhancementConfiguration: Sendable, Equatable {
    /// The local language model to enhance with, or `nil` if none is selected.
    let modelID: ModelIdentifier?

    /// How strongly the user's personal style should be preserved, `0...1`.
    ///
    /// `0` disables the language-model stage entirely — Precision then behaves exactly
    /// as it does without a model: rules and terminology only.
    let styleStrength: Double

    /// How long the model stays in memory after its last use before being unloaded.
    let unloadTimeout: TimeInterval

    init(modelID: ModelIdentifier?, styleStrength: Double, unloadTimeout: TimeInterval) {
        self.modelID = modelID
        self.styleStrength = min(max(styleStrength, 0), 1)
        self.unloadTimeout = max(unloadTimeout, 0)
    }
}
