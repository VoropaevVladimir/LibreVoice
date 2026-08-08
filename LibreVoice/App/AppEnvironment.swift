//
//  AppEnvironment.swift
//  LibreVoice
//

import AppKit
import Foundation
import Observation

/// The composition root: where LibreVoice is assembled from its parts.
///
/// This is the only file in the project that names a concrete implementation. Every
/// other file depends on a protocol from `Core`. That is not a stylistic preference —
/// it is the property that makes the rest of the architecture's claims true:
///
/// - Swapping `AVAudioEngineCaptureService` for something else is a one-line change here.
/// - Adding a speech engine means one more `register` call here, and nothing else.
/// - Tests build their own container and never touch this type.
///
/// If a concrete type's name ever appears outside this file, a dependency has leaked
/// and the layering has been broken.
@MainActor
final class AppEnvironment: ServiceContainer {
    let logger: any Logger
    let logRecords: any LogRecordReading
    let permissions: any PermissionService
    let audioCapture: any AudioCaptureService
    let speechEngines: any SpeechEngineProviding
    let hotkeys: any HotkeyService
    let textInsertion: any TextInsertionService
    let settings: AppSettings
    let dictation: DictationCoordinator
    let models: any ModelRepository
    let languageModels: any ModelRepository
    let writingProfile: any WritingProfileStoring
    let textEnhancement: any TextEnhancing
    let speechWarmUp: SpeechEngineWarmUp
    let speechWarmUpStatus: SpeechWarmUpStatus

    /// Drives the capsule and every state-driven visual. Created here, started in
    /// ``start()`` — it reacts to `dictation` and never the other way around.
    let experience: ExperienceCoordinator

    /// The registry, kept concretely so engines can be registered at launch. Everyone
    /// else sees it as ``SpeechEngineProviding``, which has no `register`.
    private let engineRegistry: SpeechEngineRegistry

    /// Whether ``start()`` has already run. Closing the window no longer quits the app,
    /// so the main window — and the `.task` that calls `start()` — can be created more
    /// than once per launch.
    private var hasStarted = false

    /// Whether the global dictation shortcut is actually bound. Its own observable object,
    /// because this container is not one — see ``HotkeyStatus``.
    let hotkeyStatus = HotkeyStatus()

    /// Builds the real application.
    init() {
        // Logging first: everything else takes a logger, so it has to exist before them.
        // Records fan out to the unified log (for Console.app and sysdiagnose) and to a
        // bounded in-memory buffer (for the in-app viewer). Neither knows about the other.
        let logStore = InMemoryLogStore()
        let logger = CompositeLogger([OSLogLogger(), logStore])
        self.logRecords = logStore
        self.logger = logger

        logger.info("LibreVoice starting up.", category: .app)

        let permissions = SystemPermissionService(logger: logger)
        let audioCapture = AVAudioEngineCaptureService(logger: logger)
        let textInsertion = AccessibilityTextInsertionService(logger: logger)
        let hotkeys = CarbonHotkeyService(logger: logger)
        let settings = AppSettings(
            persistence: UserDefaultsSettingsPersistence(logger: logger),
            logger: logger
        )

        let engineRegistry = SpeechEngineRegistry(logger: logger)

        self.permissions = permissions
        self.audioCapture = audioCapture
        self.textInsertion = textInsertion
        self.hotkeys = hotkeys
        self.settings = settings
        self.engineRegistry = engineRegistry
        self.speechEngines = engineRegistry
        let warmUpStatus = SpeechWarmUpStatus()
        self.speechWarmUpStatus = warmUpStatus
        self.speechWarmUp = SpeechEngineWarmUp(
            engines: engineRegistry,
            status: warmUpStatus,
            logger: logger
        )

        // The catalog is the trust anchor (it holds the checksums); the downloader is the
        // only networking in the app. Both are concrete only here, at the root.
        self.models = FileSystemModelRepository(
            catalog: JSONModelCatalog(logger: logger),
            downloader: URLSessionModelDownloader(logger: logger),
            logger: logger
        )

        // Precision's language models: the same machinery as speech models — catalog,
        // checksums, atomic installs — pointed at its own catalog and folder.
        let languageModels = FileSystemModelRepository(
            catalog: JSONModelCatalog(
                url: Bundle.main.url(forResource: "llm-catalog", withExtension: "json"),
                logger: logger
            ),
            downloader: URLSessionModelDownloader(logger: logger),
            subdirectoryName: "LanguageModels",
            logger: logger
        )
        self.languageModels = languageModels

        let writingProfile = FileSystemWritingProfileStore(logger: logger)
        self.writingProfile = writingProfile

        // llama.cpp is the runtime; which *model* runs on it is the user's choice from
        // the catalog. A different runtime later is a different provider on this line
        // and nothing else.
        self.textEnhancement = LocalModelTextEnhancer(
            provider: LlamaCppProvider(logger: logger),
            models: languageModels,
            profile: writingProfile,
            logger: logger
        )

        self.dictation = DictationCoordinator(
            audioCapture: audioCapture,
            speechEngines: engineRegistry,
            textInsertion: textInsertion,
            textProcessing: ModeTranscriptProcessor(),
            textEnhancement: textEnhancement,
            settings: settings,
            logger: logger
        )

        self.experience = ExperienceCoordinator(
            dictation: dictation,
            settings: settings,
            sounds: SoundPlayer(logger: logger),
            logger: logger
        )
    }

    /// Finishes setup that has to happen after `init` — registering engines and
    /// binding the global shortcut.
    ///
    /// Separate from `init` because both are asynchronous, and an initialiser that can
    /// suspend would force every caller to `await` merely to construct the app.
    ///
    /// Runs at most once per launch. Reopening the closed window recreates the view and
    /// re-runs its `.task`; without this guard that would bind a second listener to the
    /// shortcut stream, and one keypress would start — then immediately stop — dictation.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        experience.start()
        observeDockVisibility()
        await registerSpeechEngines()
        await registerHotkeys()
    }

    /// Keeps the Dock icon in sync with the ``AppSettings/menuBarOnly`` preference.
    ///
    /// `.accessory` removes the Dock tile and the app's menu bar, leaving only the menu
    /// bar item — the shape of a utility that is driven from within other apps. `.regular`
    /// restores both. The observation re-arms itself because `withObservationTracking`
    /// fires exactly once per change, the same pattern the experience coordinator uses.
    private func observeDockVisibility() {
        applyActivationPolicy()
        withObservationTracking {
            _ = settings.menuBarOnly
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyActivationPolicy()
                self?.observeDockVisibility()
            }
        }
    }

    private func applyActivationPolicy() {
        NSApp.setActivationPolicy(settings.menuBarOnly ? .accessory : .regular)
    }

    /// Registers every speech backend this build knows about.
    ///
    /// v1 ships exactly one: whisper.cpp. This method is the *only* place that knows
    /// which engines exist — adding a second is one `register` call here, and the
    /// registry, coordinator and UI do not move.
    private func registerSpeechEngines() async {
        // Registration order is the order the picker shows. Parakeet leads because it is
        // the intended recommendation; it and Moonshine report themselves unavailable
        // until a runtime for them ships, so the registry's default lands on Whisper.
        await engineRegistry.register(ParakeetEngineFactory(
            descriptor: PlannedSpeechEngines.parakeet,
            models: models,
            logger: logger
        ))

        await engineRegistry.register(WhisperCppEngineFactory(
            descriptor: PlannedSpeechEngines.whisperCPP,
            settings: settings,
            models: models,
            logger: logger
        ))

        await engineRegistry.register(PlannedSpeechEngineFactory(
            descriptor: PlannedSpeechEngines.moonshine
        ))

        // Compile the selected engine now rather than during the user's first dictation.
        // Detached and unawaited: launch must not wait on it, and a failure here costs
        // nothing the real session would not report itself.
        let selectedEngine = settings.selectedEngineID
        Task { [speechWarmUp] in
            await speechWarmUp.warmUp(engineID: selectedEngine)
        }

        if await engineRegistry.defaultEngineID() == nil {
            logger.warning(
                "No speech model is installed — dictation will ask for a download first.",
                category: .speech
            )
        }
    }

    /// Binds the dictation shortcut and starts listening for it.
    private func registerHotkeys() async {
        do {
            try await hotkeys.register(settings.toggleShortcut, for: .toggleDictation)
            hotkeyStatus.markRegistered()
        } catch {
            // Surfaced, not just logged. Registration fails when another app already owns
            // the combination — a normal thing to happen on someone's Mac — and the whole
            // product is that shortcut. Silently failing leaves the user holding a key
            // that does nothing, in front of a settings screen still advertising it, with
            // no reason to suspect anything but the app being broken.
            hotkeyStatus.markFailed()
            logger.error("Couldn't register the dictation shortcut.", error: error, category: .hotkeys)
        }

        // Push-to-talk: hold the shortcut to speak, release to transcribe and insert.
        // Press starts, release stops — not toggle — because "hold while talking" is a
        // gesture nobody has to remember the state of: the key is down exactly while
        // the microphone is open.
        //
        // A detached task would outlive the app object; this one is owned by it, and the
        // stream finishes when the service is torn down, ending the loop.
        Task { [hotkeys, dictation, logger] in
            for await event in hotkeys.events where event.id == .toggleDictation {
                switch event.phase {
                case .pressed:
                    logger.debug("Shortcut held — starting dictation.", category: .hotkeys)
                    dictation.start()
                case .released:
                    logger.debug("Shortcut released — finishing dictation.", category: .hotkeys)
                    dictation.stop()
                }
            }
        }
    }
}
