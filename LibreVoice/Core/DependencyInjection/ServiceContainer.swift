//
//  ServiceContainer.swift
//  LibreVoice
//

import Foundation

/// Everything the application is built out of.
///
/// ## Why this is a protocol with typed properties
///
/// The usual "DI container" in a Swift app is a bag of closures keyed by type:
///
/// ```swift
/// container.register(Logger.self) { OSLogLogger() }
/// let logger = container.resolve(Logger.self)   // returns an optional, or traps
/// ```
///
/// LibreVoice does not do that, for three reasons:
///
/// 1. **A forgotten registration should not compile.** With `resolve`, it compiles and
///    then crashes on launch — or worse, in a rarely taken branch. Here, a service
///    that is not provided is a build error in `AppEnvironment`.
/// 2. **No force unwraps, no `fatalError`.** A type-erased registry has to do one or
///    the other when a lookup misses. Typed properties never miss.
/// 3. **The dependency graph is readable.** This file is the list of what LibreVoice
///    is made of. A registry scatters that across every `register` call site.
///
/// What is given up is run-time registration — deciding at launch which services exist.
/// A dictation app has no use for that: the roster is known when the app is compiled.
/// The one thing that genuinely does vary — the set of speech engines — has its own
/// registry (``SpeechEngineRegistry``), because that variation is real.
///
/// ## Conforming
///
/// Two conformances exist: `AppEnvironment` for the real app, and
/// `PreviewServiceContainer` for previews and tests. A test that needs one fake service
/// starts from the preview container and overrides just that one.
///
/// Main-actor isolated because it is read from views and view models.
@MainActor
protocol ServiceContainer {
    /// Where log records go.
    var logger: any Logger { get }

    /// The retained log records, for the activity screen.
    var logRecords: any LogRecordReading { get }

    /// System authorization state.
    var permissions: any PermissionService { get }

    /// Microphone capture.
    var audioCapture: any AudioCaptureService { get }

    /// The speech backends available in this build.
    var speechEngines: any SpeechEngineProviding { get }

    /// Downloading and managing the on-device speech models.
    var models: any ModelRepository { get }

    /// Downloading and managing the local language models Precision enhances with.
    ///
    /// A second ``ModelRepository`` rather than a second kind of repository: GGUF
    /// weights need exactly what GGML weights need — a catalog, checksums, atomic
    /// installs — so the same machinery serves both, pointed at a different folder.
    var languageModels: any ModelRepository { get }

    /// The user's personal prompt.
    var writingProfile: any WritingProfileStoring { get }

    /// Pays the selected engine's first-load cost ahead of the first dictation.
    var speechWarmUp: SpeechEngineWarmUp { get }

    /// What that warm-up is doing, for the interface to show.
    var speechWarmUpStatus: SpeechWarmUpStatus { get }

    /// The Precision enhancement stage.
    var textEnhancement: any TextEnhancing { get }

    /// System-wide keyboard shortcuts.
    var hotkeys: any HotkeyService { get }

    /// Whether the global dictation shortcut is actually bound, so the settings screen
    /// can say when another app has taken it rather than advertising a dead key.
    var hotkeyStatus: HotkeyStatus { get }

    /// Delivering text into other applications.
    var textInsertion: any TextInsertionService { get }

    /// The user's preferences.
    var settings: AppSettings { get }

    /// The dictation session state machine.
    var dictation: DictationCoordinator { get }
}
