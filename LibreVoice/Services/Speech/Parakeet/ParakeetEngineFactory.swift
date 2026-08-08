//
//  ParakeetEngineFactory.swift
//  LibreVoice
//

import Foundation

/// Builds ``ParakeetEngine`` around the downloaded Core ML model directory.
///
/// Same shape as ``WhisperCppEngineFactory``, and for the same reason: the code always
/// works, the weights are what may be missing, so "is this engine available" is really
/// "is a model installed". Answering it here keeps the engine a pure function of one
/// directory and lets the picker reflect model state with no extra wiring.
///
/// Unlike Whisper, a Parakeet model is a *directory* of Core ML bundles rather than one
/// file — which is why the repository had to learn safe nested paths. The factory hands
/// that directory to the engine untouched.
nonisolated struct ParakeetEngineFactory: SpeechEngineFactory {
    let descriptor: SpeechEngineDescriptor

    private let models: any ModelRepository
    private let logger: any Logger

    init(
        descriptor: SpeechEngineDescriptor,
        models: any ModelRepository,
        logger: any Logger = NullLogger()
    ) {
        self.descriptor = descriptor
        self.models = models
        self.logger = logger
    }

    func isAvailable() async -> Bool {
        await installedModelDirectory() != nil
    }

    func makeEngine() async throws -> any SpeechRecognitionEngine {
        guard let directory = await installedModelDirectory() else {
            throw SpeechRecognitionError.modelNotInstalled(name: descriptor.name)
        }
        return ParakeetEngine(descriptor: descriptor, modelDirectory: directory, logger: logger)
    }

    /// The installed Parakeet model's folder, if there is one.
    ///
    /// The catalog carries a single Parakeet entry today; taking the last installed one
    /// in catalog order matches Whisper's rule, so adding a larger model later needs no
    /// change here.
    private func installedModelDirectory() async -> URL? {
        let catalog = await models.availableModels().filter { $0.engineID == descriptor.id }
        for model in catalog.reversed() {
            if let directory = await models.installedLocation(of: model.id) {
                return directory
            }
        }
        return nil
    }
}
