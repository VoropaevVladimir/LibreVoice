//
//  HomeViewModel.swift
//  LibreVoice
//

import Foundation
import Observation

/// Drives the main dictation screen.
///
/// The view model does not own dictation state — ``DictationCoordinator`` does, because
/// the menu bar and the global shortcut drive the same session and a second copy of the
/// state would eventually disagree with the first. What this owns is the screen's own
/// concerns: whether the microphone has been granted, and what the button should say.
@Observable
@MainActor
final class HomeViewModel {
    private let dictation: DictationCoordinator
    private let permissions: any PermissionService
    private let speechEngines: any SpeechEngineProviding
    private let models: any ModelRepository
    private let settings: AppSettings
    private let logger: any Logger

    /// The microphone authorization, refreshed while the screen is visible.
    private(set) var microphoneStatus: PermissionStatus = .notDetermined

    /// Whether any speech engine can actually run. `nil` until checked.
    private(set) var hasAvailableEngine: Bool?

    init(container: any ServiceContainer) {
        self.dictation = container.dictation
        self.permissions = container.permissions
        self.speechEngines = container.speechEngines
        self.models = container.models
        self.settings = container.settings
        self.logger = container.logger
    }

    /// The processing mode dictation runs in, bindable from the picker.
    var dictationMode: DictationMode {
        get { settings.dictationMode }
        set { settings.dictationMode = newValue }
    }

    // MARK: - State the view reads

    var state: DictationState { dictation.state }
    var audioLevel: AudioLevel { dictation.audioLevel }
    var transcript: Transcript { dictation.transcript }

    /// What the primary button should say.
    var primaryButtonTitle: String {
        state.canStart ? String(localized: "Start Dictation") : String(localized: "Stop Dictation")
    }

    /// The SF Symbol for the primary button.
    var primaryButtonSymbol: String {
        state.canStart ? "mic.fill" : "stop.fill"
    }

    /// Whether the primary button can be pressed.
    ///
    /// Blocked while the session is winding down, so a fast second press cannot start a
    /// new session on top of one that is still finishing.
    var isPrimaryButtonEnabled: Bool {
        switch state {
        case .idle, .listening, .failed: true
        case .preparing, .finishing: false
        }
    }

    /// The reason dictation cannot start, or `nil` when it can.
    ///
    /// Checked in priority order, because someone missing both a microphone grant and an
    /// engine should be told about the microphone first — it is the one they can fix.
    var blockingIssue: BlockingIssue? {
        if microphoneStatus != .granted { return .microphoneNotGranted(microphoneStatus) }
        if hasAvailableEngine == false { return .noSpeechEngine }
        return nil
    }

    /// Something standing between the user and dictating.
    enum BlockingIssue: Equatable {
        case microphoneNotGranted(PermissionStatus)
        case noSpeechEngine

        var title: String {
            switch self {
            case .microphoneNotGranted: String(localized: "Microphone access needed")
            case .noSpeechEngine: String(localized: "Speech model needed")
            }
        }

        var message: String {
            switch self {
            case .microphoneNotGranted(.denied), .microphoneNotGranted(.restricted):
                String(localized: "LibreVoice can't hear you until microphone access is turned on in System Settings.")
            case .microphoneNotGranted:
                String(localized: "LibreVoice needs permission to use the microphone.")
            case .noSpeechEngine:
                String(localized: "Dictation needs a speech model on this Mac. Download one in Settings › Models — it's a one-time download, and everything stays offline.")
            }
        }
    }

    // MARK: - Actions

    /// Refreshes everything the screen depends on. Called when it appears.
    func refresh() async {
        microphoneStatus = await permissions.status(of: .microphone)
        hasAvailableEngine = await speechEngines.defaultEngineID() != nil
    }

    /// Watches the microphone grant for as long as the screen is visible.
    ///
    /// Without this, granting access in System Settings would leave the screen insisting
    /// it is still blocked until relaunch.
    func observeMicrophoneStatus() async {
        for await status in permissions.statusChanges(for: .microphone) {
            microphoneStatus = status
        }
    }

    /// Watches model installs for as long as the screen is visible.
    ///
    /// The whisper engine's availability *is* "a model is installed", so finishing a
    /// download in Settings must clear this screen's "Speech model needed" banner
    /// immediately — not after a restart. This was a live bug: the banner stayed until
    /// the user happened to switch sections.
    func observeModelChanges() async {
        for await _ in await models.states() {
            hasAvailableEngine = await speechEngines.defaultEngineID() != nil
        }
    }

    /// Starts or stops dictation.
    func toggleDictation() {
        dictation.toggle()
    }

    /// Asks for microphone access, or opens System Settings when asking is pointless.
    func resolveMicrophoneAccess() async {
        if microphoneStatus.isPromptable {
            microphoneStatus = await permissions.request(.microphone)
        } else {
            permissions.openSystemSettings(for: .microphone)
        }
    }

    /// Clears a failed state.
    func dismissError() {
        dictation.dismissError()
    }
}
