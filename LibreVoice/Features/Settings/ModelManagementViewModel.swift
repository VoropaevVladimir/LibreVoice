//
//  ModelManagementViewModel.swift
//  LibreVoice
//

import Foundation
import Observation

/// Drives the model-management screen.
///
/// It joins two things the repository keeps separate: the *catalog* (what exists) and the
/// *state map* (what is downloaded or downloading). The view wants them merged into one
/// list of rows, each a model plus its current state, so that is assembled here.
@Observable
@MainActor
final class ModelManagementViewModel {
    /// One model as the list shows it.
    struct Row: Identifiable {
        let descriptor: ModelDescriptor
        var state: ModelInstallState

        var id: ModelIdentifier { descriptor.id }
    }

    private(set) var rows: [Row] = []
    private(set) var totalInstalledSize: Int64 = 0
    private(set) var hasLoaded = false

    /// Which family of models this instance manages.
    ///
    /// The same screen logic serves both families — the catalog, states, downloads and
    /// selection all behave identically. What differs is *which* repository is read and
    /// *which* settings key holds the selection, and that pair is exactly what this
    /// names.
    enum Purpose {
        /// The speech models dictation transcribes with.
        case speech

        /// The language models Precision enhances with.
        case languageModel
    }

    private let repository: any ModelRepository
    private let settings: AppSettings
    private let purpose: Purpose

    /// Compiles a newly chosen speech engine straight away, so the cost does not land on
    /// the user's next dictation. `nil` in previews and for language models.
    private let warmUp: SpeechEngineWarmUp?

    /// What that compile is doing, so a row can say so instead of looking finished when
    /// it is not yet usable without a wait.
    let warmUpStatus: SpeechWarmUpStatus?

    init(
        repository: any ModelRepository,
        settings: AppSettings,
        purpose: Purpose,
        warmUp: SpeechEngineWarmUp? = nil,
        warmUpStatus: SpeechWarmUpStatus? = nil
    ) {
        self.repository = repository
        self.settings = settings
        self.purpose = purpose
        self.warmUp = warmUp
        self.warmUpStatus = warmUpStatus
    }

    convenience init(container: any ServiceContainer) {
        self.init(
            repository: container.models,
            settings: container.settings,
            purpose: .speech,
            warmUp: container.speechWarmUp,
            warmUpStatus: container.speechWarmUpStatus
        )
    }

    /// The model in use, or `nil` when the app falls back to the best installed one
    /// (speech) or runs without a language model (Precision).
    var selectedModelID: ModelIdentifier? {
        switch purpose {
        case .speech: settings.selectedModelID
        case .languageModel: settings.selectedLanguageModelID
        }
    }

    /// Makes `id` the selected model for this purpose.
    ///
    /// For speech, this also switches the engine to whichever one owns the model. The
    /// engine is an implementation detail of the model the user picked: "Parakeet v3" and
    /// "Whisper Small" are two entries in one list, and choosing one should not leave a
    /// second setting to find. The catalog already records which engine consumes each
    /// model, so the pairing cannot drift.
    func selectAsDefault(_ id: ModelIdentifier) {
        switch purpose {
        case .speech:
            settings.selectedModelID = id
            if let engineID = rows.first(where: { $0.id == id })?.descriptor.engineID {
                settings.selectedEngineID = engineID
                // Choosing a model is the natural moment to pay its first-load cost: the
                // user is in Settings, not mid-sentence waiting for text to appear.
                if let warmUp {
                    Task { await warmUp.warmUp(engineID: engineID) }
                }
            }
        case .languageModel:
            settings.selectedLanguageModelID = id
        }
    }

    /// Clears the selection. Only meaningful for language models, where "none" is a
    /// legitimate state: Precision then runs rules and terminology only.
    func clearSelection() {
        switch purpose {
        case .speech: break
        case .languageModel: settings.selectedLanguageModelID = nil
        }
    }

    /// Loads the catalog and current states.
    func load() async {
        let models = await repository.availableModels()
        let states = await repository.currentStates()
        rows = models.map { Row(descriptor: $0, state: states[$0.id] ?? .notInstalled) }
        totalInstalledSize = await repository.totalInstalledSize()
        hasLoaded = true
    }

    /// Keeps the rows current while the screen is visible: download progress, completion,
    /// failures all arrive through this one stream.
    func observe() async {
        for await states in await repository.states() {
            apply(states)
            totalInstalledSize = await repository.totalInstalledSize()
        }
    }

    /// The combined installed size, formatted, or `nil` when nothing is installed.
    var installedSizeSummary: String? {
        guard totalInstalledSize > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: totalInstalledSize, countStyle: .file)
    }

    // MARK: - Actions

    func download(_ descriptor: ModelDescriptor) {
        Task { await repository.install(descriptor) }
    }

    func cancel(_ id: ModelIdentifier) {
        Task { await repository.cancelInstall(of: id) }
    }

    func remove(_ id: ModelIdentifier) {
        Task { await repository.remove(id) }
    }

    /// Whether this row's engine is being compiled right now.
    ///
    /// A downloaded Parakeet is not yet a *ready* Parakeet: Core ML still has to compile
    /// its encoder for the Neural Engine. The row says so rather than showing a plain
    /// checkmark that promises instant dictation it cannot deliver for another minute.
    func isPreparing(_ row: Row) -> Bool {
        guard purpose == .speech else { return false }
        return warmUpStatus?.isPreparing(row.descriptor.engineID) ?? false
    }

    private func apply(_ states: [ModelIdentifier: ModelInstallState]) {
        for index in rows.indices {
            guard let state = states[rows[index].id] else { continue }
            let wasInstalled = rows[index].state.isInstalled
            rows[index].state = state

            // A download that just finished is the best moment of all to compile: the user
            // has already accepted that this model takes time to become ready, and they
            // are watching the screen it happens on. Waiting until they select it — or
            // worse, until they dictate — moves the same delay somewhere it reads as a bug.
            if !wasInstalled, state.isInstalled {
                warmUpAfterInstall(rows[index])
            }
        }
    }

    private func warmUpAfterInstall(_ row: Row) {
        guard purpose == .speech, let warmUp else { return }
        let engineID = row.descriptor.engineID
        Task { await warmUp.warmUp(engineID: engineID) }
    }
}
