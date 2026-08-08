//
//  PreviewServiceContainer.swift
//  LibreVoice
//

import Foundation

/// A container of fakes, for SwiftUI previews and unit tests.
///
/// Every dependency is overridable, so a test that cares about one service passes that
/// one and gets working defaults for the rest. Without this, testing a view model would
/// mean standing up seven fakes to exercise one.
///
/// Nothing here touches the microphone, the user's real preferences, or the system's
/// permission state, so previews are safe to run and tests cannot interfere with each
/// other.
///
/// - Note: This lives in `App/` beside ``AppEnvironment``, not in `Core/`, because it is
///   the same kind of thing: a composition root. Composing means naming concrete types,
///   and `Core` is not allowed to know any. The two containers are siblings — one
///   assembles the real app, the other assembles a harmless imitation of it.
@MainActor
final class PreviewServiceContainer: ServiceContainer {
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

    /// Previews never register a real hotkey, so they show the healthy state.
    let hotkeyStatus = HotkeyStatus()

    init(
        logger: (any Logger)? = nil,
        logRecords: (any LogRecordReading)? = nil,
        permissions: (any PermissionService)? = nil,
        audioCapture: (any AudioCaptureService)? = nil,
        speechEngines: (any SpeechEngineProviding)? = nil,
        hotkeys: (any HotkeyService)? = nil,
        textInsertion: (any TextInsertionService)? = nil,
        settings: AppSettings? = nil,
        models: (any ModelRepository)? = nil,
        languageModels: (any ModelRepository)? = nil,
        writingProfile: (any WritingProfileStoring)? = nil,
        textEnhancement: (any TextEnhancing)? = nil
    ) {
        // Previews get a real in-memory store so the activity screen has something to
        // show; it writes nowhere but this object.
        let store = InMemoryLogStore()
        let resolvedLogger = logger ?? store

        let resolvedPermissions = permissions ?? StubPermissionService()
        let resolvedAudio = audioCapture ?? StubAudioCaptureService()
        let resolvedEngines = speechEngines ?? StubSpeechEngineProvider()
        let resolvedInsertion = textInsertion ?? StubTextInsertionService()
        let resolvedSettings = settings ?? AppSettings(persistence: InMemorySettingsPersistence())

        self.logger = resolvedLogger
        self.logRecords = logRecords ?? store
        self.permissions = resolvedPermissions
        self.audioCapture = resolvedAudio
        self.speechEngines = resolvedEngines
        self.hotkeys = hotkeys ?? StubHotkeyService()
        self.textInsertion = resolvedInsertion
        self.settings = resolvedSettings
        self.models = models ?? StubModelRepository()
        self.languageModels = languageModels ?? StubModelRepository(models: [])
        self.writingProfile = writingProfile ?? StubWritingProfileStore()
        let warmUpStatus = SpeechWarmUpStatus()
        self.speechWarmUpStatus = warmUpStatus
        self.speechWarmUp = SpeechEngineWarmUp(engines: resolvedEngines, status: warmUpStatus)
        let resolvedEnhancement = textEnhancement ?? StubTextEnhancer()
        self.textEnhancement = resolvedEnhancement

        self.dictation = DictationCoordinator(
            audioCapture: resolvedAudio,
            speechEngines: resolvedEngines,
            textInsertion: resolvedInsertion,
            textEnhancement: resolvedEnhancement,
            settings: resolvedSettings,
            logger: resolvedLogger
        )
    }
}
