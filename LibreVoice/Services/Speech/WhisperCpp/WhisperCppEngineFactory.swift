//
//  WhisperCppEngineFactory.swift
//  LibreVoice
//

import Foundation

/// Builds ``WhisperCppEngine`` around whichever downloaded model should be used.
///
/// "Is the engine available" is, for whisper.cpp, exactly the question "is a model
/// installed" — the code always works, the weights are what may be missing. This factory
/// owns that resolution: the user's chosen model if it is installed, otherwise the most
/// capable installed one, otherwise unavailable. Keeping the choice here means the
/// engine itself stays a pure function of one model file, and the UI's engine picker
/// reflects model state with no extra wiring.
nonisolated struct WhisperCppEngineFactory: SpeechEngineFactory {
    let descriptor: SpeechEngineDescriptor

    private let settings: AppSettings
    private let models: any ModelRepository
    private let logger: any Logger

    init(
        descriptor: SpeechEngineDescriptor,
        settings: AppSettings,
        models: any ModelRepository,
        logger: any Logger = NullLogger()
    ) {
        self.descriptor = descriptor
        self.settings = settings
        self.models = models
        self.logger = logger
    }

    func isAvailable() async -> Bool {
        await resolveModelFile() != nil
    }

    func makeEngine() async throws -> any SpeechRecognitionEngine {
        guard let modelFile = await resolveModelFile() else {
            throw SpeechRecognitionError.modelNotInstalled(name: descriptor.name)
        }
        return WhisperCppEngine(descriptor: descriptor, modelURL: modelFile, logger: logger)
    }

    // MARK: - Choosing the model

    /// The GGML file to load: the selected model if installed, else the best installed.
    ///
    /// "Best" is simply the *last* installed model in catalog order — the catalog lists
    /// models from smallest to most capable, so preferring the highest index means a
    /// user who downloaded Small and later Medium starts getting Medium without touching
    /// a setting, while an explicit selection always wins.
    private func resolveModelFile() async -> URL? {
        let catalog = await models.availableModels().filter { $0.engineID == descriptor.id }

        let preferred = await MainActor.run { settings.selectedModelID }
        if let preferred,
           let descriptor = catalog.first(where: { $0.id == preferred }),
           let url = await installedFile(of: descriptor) {
            return url
        }

        for descriptor in catalog.reversed() {
            if let url = await installedFile(of: descriptor) {
                return url
            }
        }
        return nil
    }

    /// The model's GGML file on disk, or `nil` when it is not installed.
    ///
    /// A whisper.cpp model is a single file; the repository stores it inside the model's
    /// directory under its catalog `path`.
    private func installedFile(of model: ModelDescriptor) async -> URL? {
        guard let directory = await models.installedLocation(of: model.id),
              let fileName = model.files.first?.path else { return nil }
        let url = directory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
