//
//  DictationCoordinatorTests.swift
//  LibreVoiceTests
//

import Foundation
import Testing
@testable import LibreVoice

/// Records what was inserted, so a test can assert that partials never reach another app.
private nonisolated final class RecordingTextInsertionService: TextInsertionService, @unchecked Sendable {
    private(set) var inserted: [String] = []
    private let shouldFail: Bool

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func isAvailable() async -> Bool { !shouldFail }

    func insert(_ text: String) async throws {
        if shouldFail { throw TextInsertionError.noFocusedTextField }
        inserted.append(text)
    }
}

/// An engine that emits a scripted list of events, ignoring the audio entirely.
private nonisolated struct ScriptedEngine: SpeechRecognitionEngine {
    let descriptor = SpeechEngineDescriptor(
        id: SpeechEngineID(rawValue: "scripted"),
        name: "Scripted",
        summary: "Emits a fixed script.",
        processing: .onDevice
    )

    let events: [TranscriptionEvent]

    func prepare() async throws {}

    func transcribe(
        _ audio: AsyncStream<AudioChunk>,
        options: TranscriptionOptions
    ) -> AsyncThrowingStream<TranscriptionEvent, any Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func shutdown() async {}
}

/// A `TextEnhancing` with scripted readiness and result, recording what it was given.
private nonisolated final class FakeTextEnhancer: TextEnhancing, @unchecked Sendable {
    private(set) var enhancedInputs: [String] = []
    private let ready: Bool
    private let result: String?

    /// `result: nil` makes every enhancement throw.
    init(ready: Bool, result: String?) {
        self.ready = ready
        self.result = result
    }

    func isReady(_ configuration: EnhancementConfiguration) async -> Bool { ready }

    func enhance(_ text: String, configuration: EnhancementConfiguration) async throws -> String {
        enhancedInputs.append(text)
        guard let result else { throw EnhancementError.generationFailed(reason: "scripted failure") }
        return result
    }
}

private nonisolated struct ScriptedEngineProvider: SpeechEngineProviding {
    let events: [TranscriptionEvent]

    private var engine: ScriptedEngine { ScriptedEngine(events: events) }

    func descriptors() async -> [SpeechEngineDescriptor] { [engine.descriptor] }
    func availableDescriptors() async -> [SpeechEngineDescriptor] { [engine.descriptor] }
    func defaultEngineID() async -> SpeechEngineID? { engine.descriptor.id }

    func makeEngine(for id: SpeechEngineID) async throws -> any SpeechRecognitionEngine { engine }
}

@Suite("DictationCoordinator")
@MainActor
struct DictationCoordinatorTests {
    /// Builds a coordinator from fakes.
    ///
    /// No microphone, no model, no TCC prompt — which is the entire return on injecting
    /// these as protocols rather than reaching for singletons.
    private func makeCoordinator(
        engines: any SpeechEngineProviding,
        textInsertion: any TextInsertionService = RecordingTextInsertionService(),
        insertAutomatically: Bool = true,
        mode: DictationMode = .smart,
        enhancement: (any TextEnhancing)? = nil
    ) -> DictationCoordinator {
        let settings = AppSettings(persistence: InMemorySettingsPersistence())
        settings.insertTextAutomatically = insertAutomatically
        settings.dictationMode = mode

        return DictationCoordinator(
            audioCapture: StubAudioCaptureService(),
            speechEngines: engines,
            textInsertion: textInsertion,
            textEnhancement: enhancement,
            settings: settings,
            logger: NullLogger()
        )
    }

    /// Waits for the coordinator to settle, since a session runs in a detached task.
    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        timeout: Duration = .seconds(2)
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for the coordinator to reach the expected state.")
    }

    @Test("A new coordinator is idle and empty")
    func startsIdle() {
        let coordinator = makeCoordinator(engines: StubSpeechEngineProvider())

        #expect(coordinator.state == .idle)
        #expect(coordinator.transcript.isEmpty)
        #expect(coordinator.audioLevel == .silent)
    }

    @Test("With no engine available, the session fails and says why")
    func failsWhenNoEngineAvailable() async throws {
        let coordinator = makeCoordinator(engines: StubSpeechEngineProvider())

        coordinator.start()

        try await waitUntil { coordinator.state == .failed(.noEngineAvailable) }
        #expect(coordinator.state == .failed(.noEngineAvailable), "The MVP's real state must surface as an error, not a hang.")
    }

    @Test("Dismissing an error returns to idle")
    func dismissErrorReturnsToIdle() async throws {
        let coordinator = makeCoordinator(engines: StubSpeechEngineProvider())
        coordinator.start()
        try await waitUntil { coordinator.state == .failed(.noEngineAvailable) }

        coordinator.dismissError()

        #expect(coordinator.state == .idle)
    }

    @Test("Only final text is inserted into the frontmost app")
    func onlyFinalTextIsInserted() async throws {
        let insertion = RecordingTextInsertionService()
        let coordinator = makeCoordinator(
            engines: ScriptedEngineProvider(events: [
                .partial(TranscriptionSegment(text: "hel")),
                .partial(TranscriptionSegment(text: "hello wor")),
                .final(TranscriptionSegment(text: "hello world")),
                .completed,
            ]),
            textInsertion: insertion
        )

        coordinator.start()

        try await waitUntil { coordinator.state == .idle && !coordinator.transcript.isEmpty }
        #expect(insertion.inserted == ["hello world"], "Typing a partial would leave revised text in the user's document.")
    }

    @Test("Turning off automatic insertion keeps text inside LibreVoice")
    func insertionCanBeDisabled() async throws {
        let insertion = RecordingTextInsertionService()
        let coordinator = makeCoordinator(
            engines: ScriptedEngineProvider(events: [
                .final(TranscriptionSegment(text: "private")),
                .completed,
            ]),
            textInsertion: insertion,
            insertAutomatically: false
        )

        coordinator.start()

        try await waitUntil { coordinator.state == .idle && !coordinator.transcript.isEmpty }
        #expect(insertion.inserted.isEmpty)
        #expect(coordinator.transcript.committedText == "private", "The text must still be available to copy.")
    }

    @Test("A failed insertion does not kill the session or lose the text")
    func insertionFailureKeepsTranscript() async throws {
        let coordinator = makeCoordinator(
            engines: ScriptedEngineProvider(events: [
                .final(TranscriptionSegment(text: "kept")),
                .completed,
            ]),
            textInsertion: RecordingTextInsertionService(shouldFail: true)
        )

        coordinator.start()

        try await waitUntil { coordinator.state == .idle && !coordinator.transcript.isEmpty }
        #expect(coordinator.state == .idle, "An app that refuses text must not fail the whole session.")
        #expect(coordinator.transcript.committedText == "kept", "The user's words survive where they can still copy them.")
    }

    @Test("Precision with a ready model inserts the enhanced text once")
    func precisionBatchesAndEnhances() async throws {
        let insertion = RecordingTextInsertionService()
        let enhancer = FakeTextEnhancer(ready: true, result: "Hello, world.")
        let coordinator = makeCoordinator(
            engines: ScriptedEngineProvider(events: [
                .final(TranscriptionSegment(text: "hello ")),
                .final(TranscriptionSegment(text: "world")),
                .completed,
            ]),
            textInsertion: insertion,
            mode: .precision,
            enhancement: enhancer
        )

        coordinator.start()

        try await waitUntil { coordinator.state == .idle && !coordinator.transcript.isEmpty }
        #expect(insertion.inserted == ["Hello, world."], "one insertion of the improved whole, never per-segment")
        #expect(enhancer.enhancedInputs == ["hello world"], "the model gets the full batched transcript")
        #expect(coordinator.transcript.committedText == "Hello, world.", "the transcript must show what was actually inserted")
    }

    @Test("A failed enhancement inserts the text exactly as recognised")
    func enhancementFailureFallsBackToOriginal() async throws {
        let insertion = RecordingTextInsertionService()
        let coordinator = makeCoordinator(
            engines: ScriptedEngineProvider(events: [
                .final(TranscriptionSegment(text: "hello world")),
                .completed,
            ]),
            textInsertion: insertion,
            mode: .precision,
            enhancement: FakeTextEnhancer(ready: true, result: nil)
        )

        coordinator.start()

        try await waitUntil { coordinator.state == .idle && !coordinator.transcript.isEmpty }
        #expect(insertion.inserted == ["hello world"], "a model failure must never cost the user their words")
        #expect(coordinator.transcript.committedText == "hello world")
    }

    @Test("Smart mode never consults the language model")
    func smartModeBypassesEnhancement() async throws {
        let insertion = RecordingTextInsertionService()
        let enhancer = FakeTextEnhancer(ready: true, result: "SHOULD NEVER APPEAR")
        let coordinator = makeCoordinator(
            engines: ScriptedEngineProvider(events: [
                .final(TranscriptionSegment(text: "hello ")),
                .final(TranscriptionSegment(text: "world")),
                .completed,
            ]),
            textInsertion: insertion,
            mode: .smart,
            enhancement: enhancer
        )

        coordinator.start()

        try await waitUntil { coordinator.state == .idle && !coordinator.transcript.isEmpty }
        #expect(insertion.inserted == ["hello ", "world"], "Smart keeps per-segment insertion")
        #expect(enhancer.enhancedInputs.isEmpty, "only Precision may use the language model")
    }

    @Test("Precision without a ready model behaves exactly as before")
    func precisionWithoutModelKeepsLegacyBehaviour() async throws {
        let insertion = RecordingTextInsertionService()
        let coordinator = makeCoordinator(
            engines: ScriptedEngineProvider(events: [
                .final(TranscriptionSegment(text: "hello ")),
                .final(TranscriptionSegment(text: "world")),
                .completed,
            ]),
            textInsertion: insertion,
            mode: .precision,
            enhancement: FakeTextEnhancer(ready: false, result: "SHOULD NEVER APPEAR")
        )

        coordinator.start()

        try await waitUntil { coordinator.state == .idle && !coordinator.transcript.isEmpty }
        #expect(insertion.inserted == ["hello ", "world"], "no model means the classic per-segment pipeline")
    }

    @Test("Starting twice does not begin a second session")
    func startIsIdempotentWhileActive() async throws {
        let coordinator = makeCoordinator(engines: StubSpeechEngineProvider())

        coordinator.start()
        coordinator.start()

        try await waitUntil { !coordinator.state.isActive }
        #expect(coordinator.state == .failed(.noEngineAvailable))
    }
}
