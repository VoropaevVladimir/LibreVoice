//
//  PrecisionEnhancementTests.swift
//  LibreVoiceTests
//

import Foundation
import Testing
@testable import LibreVoice

// MARK: - Runtime context

@Suite("Runtime context builder")
struct RuntimeContextBuilderTests {
    private let prompt = "You are my personal editor."

    @Test("Without a personal prompt there is no context at all")
    func promptIsRequired() {
        // LibreVoice never writes the system prompt itself — that is the design's
        // privacy stance, so it is pinned here as behaviour, not prose.
        let context = RuntimeContextBuilder.build(
            profile: WritingProfile(prompt: "   "),
            styleStrength: 0.5,
            transcript: "hello"
        )
        #expect(context == nil)
    }

    @Test("Zero strength or empty text produces no context")
    func disabledCasesProduceNothing() {
        #expect(RuntimeContextBuilder.build(
            profile: WritingProfile(prompt: prompt), styleStrength: 0, transcript: "hello"
        ) == nil)
        #expect(RuntimeContextBuilder.build(
            profile: WritingProfile(prompt: prompt), styleStrength: 0.5, transcript: "   \n"
        ) == nil)
    }

    @Test("The user's prompt leads and the transcript is the user message")
    func promptLeadsAndTextIsSeparate() throws {
        let context = try #require(RuntimeContextBuilder.build(
            profile: WritingProfile(prompt: prompt),
            styleStrength: 0.5,
            transcript: "  привет мир  "
        ))
        #expect(context.systemPrompt.hasPrefix(prompt))
        #expect(context.userText == "привет мир")
        let containsTranscript = context.systemPrompt.contains("привет мир")
        #expect(!containsTranscript, "the transcript must never leak into the system prompt")
    }

    @Test("The user's prompt reaches the model verbatim, in one piece")
    func promptPassesThroughUnaltered() throws {
        // The whole point of replacing six parsed files with one prompt: what the user
        // typed is what the model reads, character for character, with nothing inserted
        // between their sentences.
        let personal = """
        Ты мой личный редактор.

        Пиши коротко. «LibreVoice» — защищённое слово: не переводи и не склоняй.
        """
        let context = try #require(RuntimeContextBuilder.build(
            profile: WritingProfile(prompt: personal),
            styleStrength: 0.5,
            transcript: "hello"
        ))
        let containsVerbatim = context.systemPrompt.contains(personal)
        #expect(containsVerbatim, "the prompt must not be reformatted or split")
        #expect(context.systemPrompt.hasPrefix(personal), "the user's voice leads")
    }

    @Test("The non-negotiable rules are always present")
    func rulesAlwaysPresent() throws {
        for strength in [0.25, 0.5, 0.75, 1.0] {
            let context = try #require(RuntimeContextBuilder.build(
                profile: WritingProfile(prompt: prompt), styleStrength: strength, transcript: "x"
            ))
            let hasRules = context.systemPrompt.contains("Never summarize")
            let repliesTextOnly = context.systemPrompt.contains("corrected text and nothing else")
            #expect(hasRules, "strength \(strength) lost the safety rules")
            #expect(repliesTextOnly)
        }
    }

    @Test("Each strength bucket produces a distinct directive")
    func strengthBucketsDiffer() throws {
        var directives: Set<String> = []
        for strength in [0.25, 0.5, 0.75, 1.0] {
            let context = try #require(RuntimeContextBuilder.build(
                profile: WritingProfile(prompt: prompt), styleStrength: strength, transcript: "x"
            ))
            directives.insert(context.systemPrompt)
        }
        #expect(directives.count == 4, "the slider's buckets must actually change the instruction")
    }
}


// MARK: - Enhancer lifecycle

/// Records every lifecycle event so the mandatory load/unload behaviour is assertable.
private actor FakeLanguageModelProvider: LanguageModelProviding {
    private(set) var loadedModelURL: URL?
    private(set) var loadCount = 0
    private(set) var unloadCount = 0
    private(set) var lastSystem: String?
    private(set) var lastInput: String?
    private let reply: String?
    private let failsGeneration: Bool

    /// `reply: nil` echoes the input back, which every acceptance guard accepts.
    init(reply: String? = "improved text", failsGeneration: Bool = false) {
        self.reply = reply
        self.failsGeneration = failsGeneration
    }

    func load(modelAt url: URL) async throws {
        loadCount += 1
        loadedModelURL = url
    }

    func generate(system: String, input: String) async throws -> String {
        guard loadedModelURL != nil else {
            throw EnhancementError.generationFailed(reason: "generate before load")
        }
        if failsGeneration { throw EnhancementError.generationFailed(reason: "scripted failure") }
        lastSystem = system
        lastInput = input
        return reply ?? input
    }

    func unload() async {
        unloadCount += 1
        loadedModelURL = nil
    }
}

@Suite("Local model text enhancer")
struct LocalModelTextEnhancerTests {
    private let modelID = ModelIdentifier(rawValue: "test-llm")

    /// A temp directory that looks like an installed model: one .gguf inside.
    private func installedModelDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibreVoiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("gguf".utf8).write(to: dir.appendingPathComponent("weights.gguf"))
        return dir
    }

    private func configuration(strength: Double = 0.5, timeout: TimeInterval = 60) -> EnhancementConfiguration {
        EnhancementConfiguration(modelID: modelID, styleStrength: strength, unloadTimeout: timeout)
    }

    private func makeEnhancer(
        provider: (any LanguageModelProviding)?,
        location: URL?,
        prompt: String? = "You are my editor."
    ) -> LocalModelTextEnhancer {
        LocalModelTextEnhancer(
            provider: provider,
            models: StubModelRepository(installedLocations: location.map { [modelID: $0] } ?? [:]),
            profile: StubWritingProfileStore(profile: WritingProfile(prompt: prompt ?? ""))
        )
    }

    @Test("Readiness requires runtime, model, strength and the user's prompt")
    func readinessRequiresEverything() async throws {
        let location = try installedModelDirectory()
        defer { try? FileManager.default.removeItem(at: location) }
        let provider = FakeLanguageModelProvider()

        let ready = makeEnhancer(provider: provider, location: location)
        #expect(await ready.isReady(configuration()))

        let noRuntime = makeEnhancer(provider: nil, location: location)
        #expect(!(await noRuntime.isReady(configuration())))

        let noModel = makeEnhancer(provider: provider, location: nil)
        #expect(!(await noModel.isReady(configuration())))

        let zeroStrength = makeEnhancer(provider: provider, location: location)
        #expect(!(await zeroStrength.isReady(configuration(strength: 0))))

        let noPrompt = makeEnhancer(provider: provider, location: location, prompt: nil)
        #expect(!(await noPrompt.isReady(configuration())))
    }

    @Test("Enhancing loads once, reuses the model, and hands over the profile")
    func enhanceLoadsOnceAndReuses() async throws {
        let location = try installedModelDirectory()
        defer { try? FileManager.default.removeItem(at: location) }
        // Echoes its input: a reply that keeps the original's words, which is what the
        // acceptance guard requires of any genuine correction.
        let provider = FakeLanguageModelProvider(reply: nil)
        let enhancer = makeEnhancer(provider: provider, location: location)

        let first = try await enhancer.enhance("raw dictation", configuration: configuration())
        let second = try await enhancer.enhance("more dictation", configuration: configuration())

        #expect(first == "raw dictation")
        #expect(second == "more dictation")
        #expect(await provider.loadCount == 1, "the second run must reuse the loaded model")
        let system = await provider.lastSystem
        let input = await provider.lastInput
        #expect(system?.contains("You are my editor.") == true)
        #expect(input == "more dictation")
    }

    @Test("The model unloads after the idle timeout — the mandatory lifecycle")
    func unloadsAfterIdleTimeout() async throws {
        let location = try installedModelDirectory()
        defer { try? FileManager.default.removeItem(at: location) }
        let provider = FakeLanguageModelProvider(reply: nil)
        let enhancer = makeEnhancer(provider: provider, location: location)

        // A generous timeout first, so "still warm" is a fact rather than a race.
        _ = try await enhancer.enhance("dictated text here", configuration: configuration(timeout: 60))
        #expect(await provider.loadedModelURL != nil, "the model stays warm right after use")

        // The next use re-arms the idle timer with a short timeout; then idleness passes.
        _ = try await enhancer.enhance("dictated text here", configuration: configuration(timeout: 0.05))
        try await Task.sleep(for: .milliseconds(400))
        #expect(await provider.unloadCount == 1, "idle past the timeout must release the model")
        #expect(await provider.loadedModelURL == nil)
    }

    @Test("A generation failure throws; the caller keeps the original text")
    func generationFailureThrows() async throws {
        let location = try installedModelDirectory()
        defer { try? FileManager.default.removeItem(at: location) }
        let enhancer = makeEnhancer(
            provider: FakeLanguageModelProvider(failsGeneration: true),
            location: location
        )

        await #expect(throws: EnhancementError.self) {
            _ = try await enhancer.enhance("dictated text here", configuration: configuration())
        }
    }

    @Test("Replies are cleaned, and rule-breaking replies are refused")
    func acceptanceGuardsHold() throws {
        let original = "The quick brown fox jumps over the lazy dog."

        let fenced = "```markdown\nThe quick brown fox jumps over the lazy dog!\n```"
        let cleaned = try LocalModelTextEnhancer.accepted(reply: fenced, for: original)
        #expect(cleaned == "The quick brown fox jumps over the lazy dog!")

        #expect(throws: EnhancementError.self) {
            _ = try LocalModelTextEnhancer.accepted(reply: "   ", for: original)
        }
        #expect(throws: EnhancementError.self) {
            _ = try LocalModelTextEnhancer.accepted(reply: "Too short.", for: original)
        }
        let bloated = String(repeating: "invented content ", count: 40)
        #expect(throws: EnhancementError.self) {
            _ = try LocalModelTextEnhancer.accepted(reply: bloated, for: original)
        }
    }
}

// MARK: - Real runtime smoke test

@Suite("Llama runtime")
struct LlamaRuntimeSmokeTests {
    @Test("The real runtime links, initialises, and refuses a bogus model file")
    func bogusModelIsRefusedByRealRuntime() async throws {
        // No model download in tests — what this pins is that the llama.cpp dylib
        // actually loads, its backend initialises, and the load-failure path returns
        // an error instead of crashing. The first real generation is exercised by a
        // human with a downloaded model; this guards the plumbing underneath it.
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("bogus-\(UUID().uuidString).gguf")
        try Data("not a gguf".utf8).write(to: bogus)
        defer { try? FileManager.default.removeItem(at: bogus) }

        let provider = LlamaCppProvider()
        await #expect(throws: EnhancementError.self) {
            try await provider.load(modelAt: bogus)
        }
        #expect(await provider.loadedModelURL == nil)
    }
}


// MARK: - Segment joining

@Suite("Segment joining")
struct SegmentJoiningTests {
    @Test("A space is inserted where trimmed segments would collide")
    func spaceAfterSentenceEnd() {
        // The reported defect: whisper trims every segment, so "Привет." and "Меня зовут"
        // concatenated read as "Привет.Меня зовут" — a missing space that appears only at
        // boundaries, which is exactly why it looked random.
        #expect(SegmentJoining.joined(["Привет.", "Меня зовут Владимир."])
            == "Привет. Меня зовут Владимир.")
        #expect(SegmentJoining.joined(["hello", "world"]) == "hello world")
    }

    @Test("Existing whitespace is never doubled")
    func noDoubleSpaces() {
        #expect(SegmentJoining.joined(["hello ", "world"]) == "hello world")
        #expect(SegmentJoining.joined(["hello", " world"]) == "hello world")
    }

    @Test("Punctuation still attaches to the word before it")
    func punctuationAttaches() {
        #expect(SegmentJoining.joined(["слово", ", ещё"]) == "слово, ещё")
        #expect(SegmentJoining.joined(["конец", "."]) == "конец.")
        #expect(SegmentJoining.joined(["вопрос", "?"]) == "вопрос?")
    }

    @Test("Empty pieces change nothing")
    func emptyPieces() {
        #expect(SegmentJoining.joined([]) == "")
        #expect(SegmentJoining.joined(["", "hello"]) == "hello")
        #expect(SegmentJoining.joined(["hello", ""]) == "hello")
    }

    @Test("A transcript joins its segments the same way, insertion included")
    func transcriptUsesTheRule() {
        var transcript = Transcript()
        transcript.apply(.final(TranscriptionSegment(text: "Привет.")))
        let second = transcript.apply(.final(TranscriptionSegment(text: "Меня зовут Владимир.")))

        #expect(transcript.committedText == "Привет. Меня зовут Владимир.")
        // Fast and Smart type each settled segment as it arrives, so the separator has to
        // travel with it — otherwise the space is missing in the user's document.
        #expect(second == " Меня зовут Владимир.")
    }
}

// MARK: - Refusing conversation

@Suite("Reply acceptance")
struct ReplyAcceptanceTests {
    private let dictated = "привет меня зовут владимир я разработчик приложения"

    @Test("A genuine correction is accepted")
    func correctionAccepted() throws {
        let corrected = "Привет, меня зовут Владимир. Я разработчик приложения."
        #expect(try LocalModelTextEnhancer.accepted(reply: corrected, for: dictated) == corrected)
    }

    @Test("A chat reply is refused, whatever its length")
    func chatReplyRefused() throws {
        // The behaviour that prompted this guard: Qwen answering the dictation instead of
        // correcting it. These all pass the length check and must still be refused.
        let chatty = [
            "Конечно! Чем ещё я могу вам помочь сегодня?",
            "Привет, Владимир! Рад познакомиться. Какое приложение вы разрабатываете?",
            "Hello! I'd be happy to help you with your application development today.",
        ]
        for reply in chatty {
            #expect(throws: EnhancementError.self, "accepted a chat reply: \(reply)") {
                _ = try LocalModelTextEnhancer.accepted(reply: reply, for: dictated)
            }
        }
    }

    @Test("A preamble before the corrected text is stripped, not refused")
    func preambleStripped() throws {
        let withPreamble = """
        Вот исправленный текст:
        Привет, меня зовут Владимир. Я разработчик приложения.
        """
        let accepted = try LocalModelTextEnhancer.accepted(reply: withPreamble, for: dictated)
        #expect(accepted == "Привет, меня зовут Владимир. Я разработчик приложения.")
    }

    @Test("Wrapping quotes and fences are stripped")
    func wrappersStripped() throws {
        let corrected = "Привет, меня зовут Владимир. Я разработчик приложения."
        #expect(try LocalModelTextEnhancer.accepted(reply: "«\(corrected)»", for: dictated) == corrected)
        #expect(try LocalModelTextEnhancer.accepted(reply: "\"\(corrected)\"", for: dictated) == corrected)
        #expect(try LocalModelTextEnhancer.accepted(reply: "```\n\(corrected)\n```", for: dictated) == corrected)
    }

    @Test("Word retention measures what survived, ignoring case and punctuation")
    func retentionIgnoresCaseAndPunctuation() {
        let full = LocalModelTextEnhancer.wordRetention(
            of: "Привет, Меня Зовут Владимир!", from: "привет меня зовут владимир"
        )
        #expect(full == 1.0, "case and punctuation changes are the point of the edit")

        let none = LocalModelTextEnhancer.wordRetention(
            of: "Чем ещё помочь?", from: "привет меня зовут владимир"
        )
        #expect(none < 0.2)
    }
}


// MARK: - Writing profile

@Suite("Writing profile store")
struct WritingProfileStoreTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibreVoiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A fresh install starts from the default prompt")
    func freshInstallGetsTheDefault() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let profile = await FileSystemWritingProfileStore(containerDirectory: dir).load()
        #expect(profile.prompt == WritingProfile.defaultPrompt)
        #expect(profile.isConfigured)
    }

    @Test("A saved prompt round-trips verbatim")
    func savedPromptRoundTrips() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prompt = "Ты мой редактор.\n\nИсправляй только пунктуацию."

        try await FileSystemWritingProfileStore(containerDirectory: dir)
            .save(WritingProfile(prompt: prompt))

        // A second store, so this reads disk rather than a cache.
        let reloaded = await FileSystemWritingProfileStore(containerDirectory: dir).load()
        #expect(reloaded.prompt == prompt, "what the user typed is what the model must receive")
    }

    @Test("An over-long prompt is refused with its size")
    func overLongPromptRefused() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let huge = String(repeating: "a", count: WritingProfile.characterLimit + 1)

        let store = FileSystemWritingProfileStore(containerDirectory: dir)
        await #expect(throws: WritingProfileError.self) {
            try await store.save(WritingProfile(prompt: huge))
        }
    }

    @Test("A whitespace-only prompt is not configured")
    func blankPromptIsNotConfigured() {
        #expect(!WritingProfile(prompt: "   \n\t ").isConfigured)
        #expect(WritingProfile(prompt: "Be my editor.").isConfigured)
    }

    @Test("The legacy Markdown profile is migrated, not lost")
    func legacyDocumentsAreMigrated() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Lay out the previous design's files, as an existing user would have them.
        let profileDirectory = dir.appendingPathComponent("Profile", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        try "You are my editor.".write(
            to: profileDirectory.appendingPathComponent("PROMPT.md"), atomically: true, encoding: .utf8
        )
        try "I write short sentences.".write(
            to: profileDirectory.appendingPathComponent("STYLE.md"), atomically: true, encoding: .utf8
        )

        let migrated = await FileSystemWritingProfileStore(containerDirectory: dir).load()

        let keptPrompt = migrated.prompt.contains("You are my editor.")
        let keptStyle = migrated.prompt.contains("I write short sentences.")
        #expect(keptPrompt, "upgrading must not discard the user's prompt")
        #expect(keptStyle, "the other documents are folded in, not dropped")

        // Migration happens once and is then just the stored prompt.
        let second = await FileSystemWritingProfileStore(containerDirectory: dir).load()
        #expect(second.prompt == migrated.prompt)
    }
}

// MARK: - Speech engine roster

@Suite("Speech engine roster")
struct SpeechEngineRosterTests {
    @Test("The build declares Parakeet, Whisper and Moonshine, in that order")
    func rosterMatchesTheProduct() {
        let names = PlannedSpeechEngines.all.map(\.name)
        #expect(names.count == 3)
        #expect(names[0].contains("Parakeet"))
        #expect(names[1] == "Whisper")
        #expect(names[2].contains("Moonshine"))
    }

    @Test("Every engine transcribes on this Mac")
    func everyEngineIsOnDevice() {
        for descriptor in PlannedSpeechEngines.all {
            #expect(descriptor.processing == .onDevice, "\(descriptor.name) would send audio away")
            #expect(!descriptor.processing.sendsAudioOffDevice)
        }
    }

    @Test("An engine with no implementation refuses to build rather than faking it")
    func plannedEngineRefuses() async throws {
        let factory = PlannedSpeechEngineFactory(descriptor: PlannedSpeechEngines.parakeet)
        #expect(!(await factory.isAvailable()))
        await #expect(throws: SpeechRecognitionError.self) {
            _ = try await factory.makeEngine()
        }
    }

    @Test("The registry defaults to an engine that can actually run")
    func defaultSkipsUnavailableEngines() async throws {
        // Registration order puts Parakeet first, but it cannot run; the default must
        // fall through to the engine that can.
        let registry = SpeechEngineRegistry()
        await registry.register(PlannedSpeechEngineFactory(descriptor: PlannedSpeechEngines.parakeet))
        await registry.register(StubSpeechEngineFactory(descriptor: PlannedSpeechEngines.whisperCPP))
        await registry.register(PlannedSpeechEngineFactory(descriptor: PlannedSpeechEngines.moonshine))

        let all = await registry.descriptors()
        let available = await registry.availableDescriptors()
        #expect(all.count == 3, "the picker shows the whole roster")
        #expect(available.map(\.id) == [PlannedSpeechEngines.whisperCPP.id])
        #expect(await registry.defaultEngineID() == PlannedSpeechEngines.whisperCPP.id)
    }
}

/// A factory that reports available and builds an engine which recognises nothing.
private nonisolated struct StubSpeechEngineFactory: SpeechEngineFactory {
    let descriptor: SpeechEngineDescriptor

    func isAvailable() async -> Bool { true }

    func makeEngine() async throws -> any SpeechRecognitionEngine {
        SilentEngine(descriptor: descriptor)
    }
}

private nonisolated struct SilentEngine: SpeechRecognitionEngine {
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

// MARK: - One list, engine follows the model

@Suite("Model selection")
@MainActor
struct ModelSelectionTests {
    private func catalogModel(_ id: String, engine: String) -> ModelDescriptor {
        ModelDescriptor(
            id: ModelIdentifier(rawValue: id),
            engineID: SpeechEngineID(rawValue: engine),
            displayName: id,
            summary: "",
            files: []
        )
    }

    @Test("Choosing a model switches the engine that owns it")
    func selectingModelSwitchesEngine() async throws {
        // One list, like the app it is modelled on: "Parakeet v3" and "Whisper Small" sit
        // side by side and picking one must not leave a second setting to find.
        let settings = AppSettings(persistence: InMemorySettingsPersistence())
        let whisper = catalogModel("whisper-cpp-small", engine: "whisper-cpp")
        let parakeet = catalogModel("parakeet-tdt-0.6b-v3-coreml", engine: "nvidia-parakeet")

        let viewModel = ModelManagementViewModel(
            repository: StubModelRepository(models: [whisper, parakeet]),
            settings: settings,
            purpose: .speech
        )
        await viewModel.load()

        viewModel.selectAsDefault(parakeet.id)
        #expect(settings.selectedModelID == parakeet.id)
        #expect(settings.selectedEngineID == parakeet.engineID, "the engine follows the model")

        viewModel.selectAsDefault(whisper.id)
        #expect(settings.selectedModelID == whisper.id)
        #expect(settings.selectedEngineID == whisper.engineID, "and follows it back")
    }

    @Test("The shipped catalog offers both engine families in one list")
    func catalogCoversBothEngines() async throws {
        let catalog = JSONModelCatalog(
            url: Bundle.main.url(forResource: "model-catalog", withExtension: "json")
        )
        let models = try await catalog.availableModels()
        let engines = Set(models.map(\.engineID.rawValue))

        #expect(engines.contains("whisper-cpp"))
        #expect(engines.contains("nvidia-parakeet"))
    }
}
