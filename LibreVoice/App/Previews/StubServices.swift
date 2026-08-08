//
//  StubServices.swift
//  LibreVoice
//

import Foundation

// Fakes used by `PreviewServiceContainer`, and by tests that need one service to behave
// a particular way. They are configurable rather than fixed, because the states worth
// looking at — permission denied, no engine, insertion failing — are exactly the ones
// that are hard to produce with the real thing.
//
// They live in the app target rather than the test target so SwiftUI previews can use
// them too; previews cannot import a test bundle.

/// A ``PermissionService`` that reports whatever it is told to.
///
/// Lets the permission UI be previewed in states that are otherwise unreachable —
/// `.restricted` needs an MDM profile, and `.notDetermined` cannot be restored once the
/// real prompt has been answered.
nonisolated final class StubPermissionService: PermissionService {
    private let statuses: [Permission: PermissionStatus]

    /// Creates a service reporting `statuses`, defaulting to granted.
    init(statuses: [Permission: PermissionStatus] = [:]) {
        self.statuses = statuses
    }

    /// A service where nothing has been granted yet.
    static let notDetermined = StubPermissionService(
        statuses: Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, .notDetermined) })
    )

    /// A service where the microphone has been refused.
    static let microphoneDenied = StubPermissionService(statuses: [.microphone: .denied])

    func status(of permission: Permission) async -> PermissionStatus {
        statuses[permission] ?? .granted
    }

    @discardableResult
    func request(_ permission: Permission) async -> PermissionStatus {
        await status(of: permission)
    }

    func statusChanges(for permission: Permission) -> AsyncStream<PermissionStatus> {
        AsyncStream { continuation in
            continuation.yield(statuses[permission] ?? .granted)
            continuation.finish()
        }
    }

    @MainActor
    func openSystemSettings(for permission: Permission) {
        // Intentionally does nothing: a preview must not open System Settings.
    }
}

/// An ``AudioCaptureService`` that produces silence instead of touching the microphone.
nonisolated final class StubAudioCaptureService: AudioCaptureService {
    let format = AudioFormat.speech

    init() {}

    var isCapturing: Bool { get async { false } }

    func availableInputDevices() async -> [AudioInputDevice] {
        [AudioInputDevice(id: "stub.builtin", name: "MacBook Pro Microphone", isDefault: true)]
    }

    func start(deviceID: String?) async throws -> AsyncStream<AudioChunk> {
        AsyncStream { $0.finish() }
    }

    func stop() async {}
}

/// A ``SpeechEngineProviding`` with a configurable roster and no real engines.
nonisolated final class StubSpeechEngineProvider: SpeechEngineProviding {
    private let available: [SpeechEngineDescriptor]

    /// Creates a provider offering `available`. Empty by default, which matches the
    /// MVP's honest state: no engine exists yet.
    init(available: [SpeechEngineDescriptor] = []) {
        self.available = available
    }

    /// A provider offering every planned engine, for previewing the picker.
    static let planned = StubSpeechEngineProvider(available: PlannedSpeechEngines.all)

    func descriptors() async -> [SpeechEngineDescriptor] { available }
    func availableDescriptors() async -> [SpeechEngineDescriptor] { available }
    func defaultEngineID() async -> SpeechEngineID? { available.first?.id }

    func makeEngine(for id: SpeechEngineID) async throws -> any SpeechRecognitionEngine {
        throw SpeechRecognitionError.engineUnavailable(reason: "Previews don't run speech engines.")
    }
}

/// A ``ModelCatalog`` offering a fixed list, for previews.
nonisolated struct StubModelCatalog: ModelCatalog {
    let models: [ModelDescriptor]

    init(models: [ModelDescriptor] = StubModelCatalog.sampleModels) {
        self.models = models
    }

    func availableModels() async throws -> [ModelDescriptor] { models }

    /// A couple of realistic entries so the model screen has something to show. The URLs
    /// are `example.com` placeholders — a preview must never actually download anything.
    static let sampleModels: [ModelDescriptor] = [
        ModelDescriptor(
            id: ModelIdentifier(rawValue: "mlx-whisper-tiny"),
            engineID: SpeechEngineID(rawValue: "mlx-whisper"),
            displayName: "Whisper Tiny",
            summary: "Fastest and smallest. Great for quick notes.",
            files: [
                ModelFile(
                    path: "weights.npz",
                    url: URL(string: "https://example.com/whisper-tiny/weights.npz")!,
                    sizeBytes: 74_000_000,
                    sha256: ModelChecksum(sha256: "0000000000000000000000000000000000000000000000000000000000000000")
                )
            ]
        ),
        ModelDescriptor(
            id: ModelIdentifier(rawValue: "mlx-whisper-large-v3-turbo"),
            engineID: SpeechEngineID(rawValue: "mlx-whisper"),
            displayName: "Whisper Large v3 Turbo",
            summary: "Close to Large v3 accuracy, much faster.",
            files: [
                ModelFile(
                    path: "weights.safetensors",
                    url: URL(string: "https://example.com/whisper-turbo/weights.safetensors")!,
                    sizeBytes: 1_600_000_000,
                    sha256: ModelChecksum(sha256: "1111111111111111111111111111111111111111111111111111111111111111")
                )
            ]
        ),
    ]
}

/// A ``ModelRepository`` that reports fixed states and never touches the network or disk.
nonisolated final class StubModelRepository: ModelRepository, @unchecked Sendable {
    private let models: [ModelDescriptor]
    private let fixedStates: [ModelIdentifier: ModelInstallState]
    private let installedLocations: [ModelIdentifier: URL]

    init(
        models: [ModelDescriptor] = StubModelCatalog.sampleModels,
        states: [ModelIdentifier: ModelInstallState] = [:],
        installedLocations: [ModelIdentifier: URL] = [:]
    ) {
        self.models = models
        self.fixedStates = states
        self.installedLocations = installedLocations
    }

    func availableModels() async -> [ModelDescriptor] { models }
    func currentStates() async -> [ModelIdentifier: ModelInstallState] { fixedStates }

    func states() async -> AsyncStream<[ModelIdentifier: ModelInstallState]> {
        AsyncStream { continuation in
            continuation.yield(fixedStates)
            continuation.finish()
        }
    }

    func installState(of id: ModelIdentifier) async -> ModelInstallState {
        fixedStates[id] ?? .notInstalled
    }

    func install(_ descriptor: ModelDescriptor) async {}
    func cancelInstall(of id: ModelIdentifier) async {}
    func remove(_ id: ModelIdentifier) async {}
    func installedLocation(of id: ModelIdentifier) async -> URL? { installedLocations[id] }
    func totalInstalledSize() async -> Int64 { 0 }
}

/// A ``WritingProfileStoring`` holding one prompt in memory.
actor StubWritingProfileStore: WritingProfileStoring {
    private var stored: WritingProfile

    init(profile: WritingProfile = WritingProfile(prompt: "")) {
        self.stored = profile
    }

    func load() async -> WritingProfile { stored }

    func save(_ profile: WritingProfile) async throws {
        // The same limit as the real store, so previews and tests meet real rejections —
        // but held in memory, never written to the user's disk.
        guard profile.prompt.count <= WritingProfile.characterLimit else {
            throw WritingProfileError.tooLong(
                characters: profile.prompt.count,
                limit: WritingProfile.characterLimit
            )
        }
        stored = profile
    }
}

/// A ``TextEnhancing`` that is never ready and changes nothing.
///
/// The preview default: Precision behaves as if no language model were configured,
/// which is also the real app's behaviour in a build without a runtime.
nonisolated struct StubTextEnhancer: TextEnhancing {
    init() {}

    func isReady(_ configuration: EnhancementConfiguration) async -> Bool { false }

    func enhance(_ text: String, configuration: EnhancementConfiguration) async throws -> String {
        text
    }
}

/// A ``LanguageModelProviding`` that loads nothing and echoes its input.
///
/// For previews and for tests that need a provider present without an inference runtime.
nonisolated struct StubLanguageModelProvider: LanguageModelProviding {
    init() {}

    var loadedModelURL: URL? { get async { nil } }

    func load(modelAt url: URL) async throws {}

    func generate(system: String, input: String) async throws -> String { input }

    func unload() async {}
}

/// A ``SoundPlaying`` that stays silent.
///
/// Previews and tests must never make noise: a canvas that chimes every time it
/// re-renders is intolerable, and a test suite that plays sounds is worse.
nonisolated struct SilentSoundPlayer: SoundPlaying {
    init() {}

    func play(_ sound: DictationSound, mode: DictationMode) async {}
}

/// A ``HotkeyService`` that accepts registrations and never fires.
nonisolated final class StubHotkeyService: HotkeyService {
    let events: AsyncStream<HotkeyEvent>

    init() {
        events = AsyncStream { $0.finish() }
    }

    func register(_ shortcut: HotkeyShortcut, for id: HotkeyID) async throws {}
    func unregister(_ id: HotkeyID) async {}
    func unregisterAll() async {}
}

/// A ``TextInsertionService`` that discards text instead of typing it anywhere.
///
/// Emphatically not a real implementation: a preview that typed into whatever app the
/// developer had open would be a genuinely bad afternoon.
nonisolated final class StubTextInsertionService: TextInsertionService {
    private let available: Bool

    init(available: Bool = true) {
        self.available = available
    }

    func isAvailable() async -> Bool { available }

    func insert(_ text: String) async throws {
        guard available else { throw TextInsertionError.accessibilityPermissionDenied }
    }
}
