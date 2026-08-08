//
//  SpeechEngineRegistryTests.swift
//  LibreVoiceTests
//

import Foundation
import Testing
@testable import LibreVoice

/// A factory whose availability and engine are dictated by the test.
///
/// That this is ~20 lines, needs no model and touches no hardware is the point of
/// ``SpeechEngineFactory`` existing at all.
private nonisolated struct FakeEngineFactory: SpeechEngineFactory {
    let descriptor: SpeechEngineDescriptor
    let available: Bool

    init(id: String, available: Bool = true, processing: ProcessingLocation = .onDevice) {
        self.descriptor = SpeechEngineDescriptor(
            id: SpeechEngineID(rawValue: id),
            name: id,
            summary: "A fake engine for testing.",
            processing: processing
        )
        self.available = available
    }

    func isAvailable() async -> Bool { available }

    func makeEngine() async throws -> any SpeechRecognitionEngine {
        FakeEngine(descriptor: descriptor)
    }
}

private nonisolated struct FakeEngine: SpeechRecognitionEngine {
    let descriptor: SpeechEngineDescriptor

    func prepare() async throws {}

    func transcribe(
        _ audio: AsyncStream<AudioChunk>,
        options: TranscriptionOptions
    ) -> AsyncThrowingStream<TranscriptionEvent, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func shutdown() async {}
}

@Suite("SpeechEngineRegistry")
struct SpeechEngineRegistryTests {
    @Test("An empty registry has no default, rather than trapping")
    func emptyRegistryHasNoDefault() async {
        let registry = SpeechEngineRegistry()

        #expect(await registry.defaultEngineID() == nil)
        #expect(await registry.descriptors().isEmpty)
    }

    @Test("Registration order is preference order")
    func registrationOrderIsPreserved() async {
        let registry = SpeechEngineRegistry()
        await registry.register(FakeEngineFactory(id: "first"))
        await registry.register(FakeEngineFactory(id: "second"))
        await registry.register(FakeEngineFactory(id: "third"))

        let ids = await registry.descriptors().map(\.id.rawValue)

        #expect(ids == ["first", "second", "third"], "A dictionary alone would lose this, and the default depends on it.")
    }

    @Test("The default is the first engine that can actually run")
    func defaultSkipsUnavailableEngines() async {
        let registry = SpeechEngineRegistry()
        await registry.register(FakeEngineFactory(id: "unavailable", available: false))
        await registry.register(FakeEngineFactory(id: "usable"))

        #expect(await registry.defaultEngineID() == SpeechEngineID(rawValue: "usable"))
    }

    @Test("Unavailable engines are still listed, so the UI can explain them")
    func unavailableEnginesAreStillListed() async {
        let registry = SpeechEngineRegistry()
        await registry.register(FakeEngineFactory(id: "unavailable", available: false))

        #expect(await registry.descriptors().count == 1, "Hiding it would leave the user wondering where it went.")
        #expect(await registry.availableDescriptors().isEmpty)
    }

    @Test("Asking for an unregistered engine throws instead of crashing")
    func unknownEngineThrows() async throws {
        let registry = SpeechEngineRegistry()
        let missing = SpeechEngineID(rawValue: "does-not-exist")

        await #expect(throws: SpeechRecognitionError.unknownEngine(missing)) {
            _ = try await registry.makeEngine(for: missing)
        }
    }

    @Test("Registering the same identifier twice replaces it and keeps its position")
    func duplicateRegistrationReplacesInPlace() async {
        let registry = SpeechEngineRegistry()
        await registry.register(FakeEngineFactory(id: "engine", available: false))
        await registry.register(FakeEngineFactory(id: "other"))
        await registry.register(FakeEngineFactory(id: "engine", available: true))

        let ids = await registry.descriptors().map(\.id.rawValue)

        #expect(ids == ["engine", "other"], "A replacement must not jump the queue.")
        #expect(await registry.defaultEngineID() == SpeechEngineID(rawValue: "engine"))
    }

    @Test("A built engine carries the factory's descriptor")
    func makeEngineReturnsDescribedEngine() async throws {
        let registry = SpeechEngineRegistry()
        await registry.register(FakeEngineFactory(id: "engine"))

        let engine = try await registry.makeEngine(for: SpeechEngineID(rawValue: "engine"))

        #expect(engine.descriptor.id == SpeechEngineID(rawValue: "engine"))
    }

    @Test("A remote engine reports that it sends audio off the device")
    func remoteEngineIsFlagged() async {
        let registry = SpeechEngineRegistry()
        await registry.register(FakeEngineFactory(id: "cloud", processing: .remote(host: "example.com")))

        let descriptor = try? #require(await registry.descriptors().first)

        #expect(descriptor?.processing.sendsAudioOffDevice == true)
    }
}
