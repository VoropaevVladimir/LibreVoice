//
//  SpeechWarmUpTests.swift
//  LibreVoiceTests
//

import Foundation
import Testing
@testable import LibreVoice

/// Counts how many times an engine was actually built and prepared.
private nonisolated final class PrepareCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private nonisolated struct CountingEngine: SpeechRecognitionEngine {
    let descriptor: SpeechEngineDescriptor
    let counter: PrepareCounter

    func prepare() async throws { counter.increment() }

    func transcribe(
        _ audio: AsyncStream<AudioChunk>,
        options: TranscriptionOptions
    ) -> AsyncThrowingStream<TranscriptionEvent, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func shutdown() async {}
}

private nonisolated struct CountingFactory: SpeechEngineFactory {
    let descriptor: SpeechEngineDescriptor
    let counter: PrepareCounter

    init(id: String, counter: PrepareCounter) {
        self.descriptor = SpeechEngineDescriptor(
            id: SpeechEngineID(rawValue: id),
            name: id,
            summary: "Counts its preparations.",
            processing: .onDevice
        )
        self.counter = counter
    }

    func isAvailable() async -> Bool { true }

    func makeEngine() async throws -> any SpeechRecognitionEngine {
        CountingEngine(descriptor: descriptor, counter: counter)
    }
}

@Suite("Speech engine warm-up")
struct SpeechWarmUpTests {
    /// Building a registry with one engine that records its preparations.
    private func makeRegistry(id: String, counter: PrepareCounter) async -> SpeechEngineRegistry {
        let registry = SpeechEngineRegistry()
        await registry.register(CountingFactory(id: id, counter: counter))
        return registry
    }

    @Test("Warming up prepares the engine and then releases it")
    func warmUpPreparesOnce() async throws {
        let counter = PrepareCounter()
        let engineID = SpeechEngineID(rawValue: "counting")
        let registry = await makeRegistry(id: "counting", counter: counter)
        let warmUp = SpeechEngineWarmUp(engines: registry)

        await warmUp.warmUp(engineID: engineID)
        await warmUp.waitForCompletion()

        #expect(counter.count == 1)
    }

    @Test("An engine already warmed this launch is not compiled a second time")
    func warmUpIsNotRepeated() async throws {
        let counter = PrepareCounter()
        let engineID = SpeechEngineID(rawValue: "counting")
        let registry = await makeRegistry(id: "counting", counter: counter)
        let warmUp = SpeechEngineWarmUp(engines: registry)

        await warmUp.warmUp(engineID: engineID)
        await warmUp.waitForCompletion()
        await warmUp.warmUp(engineID: engineID)
        await warmUp.waitForCompletion()

        #expect(counter.count == 1, "Selecting the same model twice must not pay the compile twice.")
    }

    @Test("The interface can see a warm-up start and finish")
    @MainActor
    func statusReportsProgress() async throws {
        let counter = PrepareCounter()
        let engineID = SpeechEngineID(rawValue: "counting")
        let registry = await makeRegistry(id: "counting", counter: counter)
        let status = SpeechWarmUpStatus()
        let warmUp = SpeechEngineWarmUp(engines: registry, status: status)

        #expect(status.isPreparing(engineID) == false)

        await warmUp.warmUp(engineID: engineID)
        await warmUp.waitForCompletion()

        #expect(status.isPreparing(engineID) == false, "It must not stay stuck in 'preparing'.")
        #expect(status.readyEngineIDs.contains(engineID))
    }

    @Test("A finished download compiles the model straight away")
    @MainActor
    func installTriggersWarmUp() async throws {
        let counter = PrepareCounter()
        let descriptor = StubModelCatalog.sampleModels[0]
        let registry = await makeRegistry(id: descriptor.engineID.rawValue, counter: counter)
        let warmUp = SpeechEngineWarmUp(engines: registry)

        // The repository reports the model as not installed, then installed — exactly the
        // transition a completed download produces.
        let repository = ScriptedModelRepository(
            models: [descriptor],
            sequence: [
                [descriptor.id: .notInstalled],
                [descriptor.id: .installed(sizeBytes: 1_000)],
            ]
        )

        let viewModel = ModelManagementViewModel(
            repository: repository,
            settings: AppSettings(persistence: InMemorySettingsPersistence()),
            purpose: .speech,
            warmUp: warmUp
        )
        await viewModel.load()
        await viewModel.observe()
        await warmUp.waitForCompletion()

        #expect(counter.count == 1, "The wait belongs at download time, not at the user's first sentence.")
    }
}

/// A repository that replays a fixed sequence of state maps.
private nonisolated final class ScriptedModelRepository: ModelRepository, @unchecked Sendable {
    private let models: [ModelDescriptor]
    private let sequence: [[ModelIdentifier: ModelInstallState]]

    init(models: [ModelDescriptor], sequence: [[ModelIdentifier: ModelInstallState]]) {
        self.models = models
        self.sequence = sequence
    }

    func availableModels() async -> [ModelDescriptor] { models }
    func currentStates() async -> [ModelIdentifier: ModelInstallState] { sequence.first ?? [:] }

    func states() async -> AsyncStream<[ModelIdentifier: ModelInstallState]> {
        AsyncStream { continuation in
            for step in sequence { continuation.yield(step) }
            continuation.finish()
        }
    }

    func installState(of id: ModelIdentifier) async -> ModelInstallState {
        sequence.last?[id] ?? .notInstalled
    }

    func install(_ descriptor: ModelDescriptor) async {}
    func cancelInstall(of id: ModelIdentifier) async {}
    func remove(_ id: ModelIdentifier) async {}
    func installedLocation(of id: ModelIdentifier) async -> URL? { nil }
    func totalInstalledSize() async -> Int64 { 0 }
}
