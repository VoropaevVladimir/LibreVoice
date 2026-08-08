//
//  PrecisionViewModel.swift
//  LibreVoice
//

import Foundation
import Observation

/// Drives the Precision screen: the language model, the style strength, and the memory
/// policy.
///
/// Model management is not reimplemented — it *is* a ``ModelManagementViewModel`` pointed
/// at the language-model repository, so downloads, progress and verification behave
/// identically to the speech models screen. The personal prompt has its own screen; this
/// one only reports whether it is set, because readiness is the fact a user standing here
/// needs.
@Observable
@MainActor
final class PrecisionViewModel {
    /// The language-model list, reusing the whole model-management machinery.
    let models: ModelManagementViewModel

    let settings: AppSettings
    private let profile: any WritingProfileStoring

    /// Whether a personal prompt has been written.
    private(set) var hasWritingProfile = false

    init(container: any ServiceContainer) {
        self.models = ModelManagementViewModel(
            repository: container.languageModels,
            settings: container.settings,
            purpose: .languageModel
        )
        self.settings = container.settings
        self.profile = container.writingProfile
    }

    func load() async {
        await models.load()
        hasWritingProfile = await profile.load().isConfigured
    }

    func observe() async {
        await models.observe()
    }

    /// Whether the language-model stage can actually run — the same three conditions the
    /// dictation pipeline applies, so the screen can say honestly whether Precision will
    /// enhance or fall back to rules only.
    var isEnhancementConfigured: Bool {
        settings.selectedLanguageModelID != nil
            && settings.styleStrength > 0
            && hasWritingProfile
    }
}
