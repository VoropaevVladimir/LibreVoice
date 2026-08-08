//
//  AppSettings.swift
//  LibreVoice
//

import Foundation
import Observation

/// The user's preferences, observable by SwiftUI and written straight through to disk.
///
/// A single `@Observable` object rather than scattered `@AppStorage` properties in
/// views. `@AppStorage` reads nice in a demo but hard-codes a key and a storage
/// mechanism into the view that uses it, which makes the view untestable and the
/// preference impossible to migrate. Here views bind to typed properties, and the
/// only thing that knows about storage is the injected ``SettingsPersistence``.
///
/// Isolated to the main actor because it is bound directly to UI controls.
@Observable
@MainActor
final class AppSettings {
    private let persistence: any SettingsPersistence
    private let logger: any Logger

    /// The speech engine the user picked, or `nil` to follow the registry's default.
    var selectedEngineID: SpeechEngineID? {
        didSet { persistence.setValue(selectedEngineID?.rawValue, for: SettingsKeys.selectedEngineID) }
    }

    /// The language to transcribe, or `nil` to follow the system language.
    var locale: Locale? {
        didSet { persistence.setValue(locale?.identifier, for: SettingsKeys.localeIdentifier) }
    }

    /// The downloaded model to transcribe with, or `nil` for the best installed one.
    var selectedModelID: ModelIdentifier? {
        didSet { persistence.setValue(selectedModelID?.rawValue, for: SettingsKeys.selectedModelID) }
    }

    /// How transcribed text is processed before insertion.
    var dictationMode: DictationMode {
        didSet { persistence.setValue(dictationMode.rawValue, for: SettingsKeys.dictationMode) }
    }

    /// The microphone to capture from, or `nil` for the system default input.
    var inputDeviceID: String? {
        didSet { persistence.setValue(inputDeviceID, for: SettingsKeys.inputDeviceID) }
    }

    /// The shortcut that starts and stops dictation.
    var toggleShortcut: HotkeyShortcut {
        didSet { persistence.setValue(toggleShortcut, for: SettingsKeys.toggleShortcut) }
    }

    /// Whether to type transcribed text into the frontmost app.
    var insertTextAutomatically: Bool {
        didSet { persistence.setValue(insertTextAutomatically, for: SettingsKeys.insertTextAutomatically) }
    }

    /// Whether to play a sound when dictation starts and stops.
    var playFeedbackSounds: Bool {
        didSet { persistence.setValue(playFeedbackSounds, for: SettingsKeys.playFeedbackSounds) }
    }

    /// Whether to show the menu bar icon.
    var showMenuBarIcon: Bool {
        didSet {
            // Refuse to be the last icon turned off. The settings screen disables this
            // toggle while the Dock icon is hidden, but an invariant that lives only in a
            // view is an invariant one code path away from being broken.
            if !showMenuBarIcon, menuBarOnly {
                showMenuBarIcon = true
                return
            }
            persistence.setValue(showMenuBarIcon, for: SettingsKeys.showMenuBarIcon)
        }
    }

    /// Whether the app hides its Dock icon and lives only in the menu bar.
    var menuBarOnly: Bool {
        didSet {
            persistence.setValue(menuBarOnly, for: SettingsKeys.menuBarOnly)
            // With no Dock icon the menu bar item is the only way back into the app, so it
            // must stay visible. Enforce that here rather than let the two toggles combine
            // into an app that is running with no way to reach it.
            if menuBarOnly, !showMenuBarIcon { showMenuBarIcon = true }
        }
    }

    /// Whether the user has been through the welcome flow.
    var hasCompletedOnboarding: Bool {
        didSet { persistence.setValue(hasCompletedOnboarding, for: SettingsKeys.hasCompletedOnboarding) }
    }

    /// The local language model Precision enhances with, or `nil` for none.
    var selectedLanguageModelID: ModelIdentifier? {
        didSet { persistence.setValue(selectedLanguageModelID?.rawValue, for: SettingsKeys.selectedLanguageModelID) }
    }

    /// How strongly Precision preserves the user's personal style, `0...1`.
    var styleStrength: Double {
        didSet { persistence.setValue(styleStrength, for: SettingsKeys.styleStrength) }
    }

    /// Seconds of idleness before the language model is unloaded from memory.
    var languageModelUnloadTimeout: TimeInterval {
        didSet { persistence.setValue(languageModelUnloadTimeout, for: SettingsKeys.languageModelUnloadTimeout) }
    }

    /// Loads settings from `persistence`.
    init(persistence: any SettingsPersistence, logger: any Logger = NullLogger()) {
        self.persistence = persistence
        self.logger = logger

        self.selectedEngineID = persistence
            .value(for: SettingsKeys.selectedEngineID)
            .map(SpeechEngineID.init(rawValue:))
        self.locale = persistence
            .value(for: SettingsKeys.localeIdentifier)
            .map(Locale.init(identifier:))
        self.selectedModelID = persistence
            .value(for: SettingsKeys.selectedModelID)
            .map(ModelIdentifier.init(rawValue:))
        self.dictationMode = persistence
            .value(for: SettingsKeys.dictationMode)
            .flatMap(DictationMode.init(rawValue:)) ?? .default
        self.inputDeviceID = persistence.value(for: SettingsKeys.inputDeviceID)
        self.toggleShortcut = persistence.value(for: SettingsKeys.toggleShortcut)
        self.insertTextAutomatically = persistence.value(for: SettingsKeys.insertTextAutomatically)
        self.playFeedbackSounds = persistence.value(for: SettingsKeys.playFeedbackSounds)
        self.showMenuBarIcon = persistence.value(for: SettingsKeys.showMenuBarIcon)
        self.menuBarOnly = persistence.value(for: SettingsKeys.menuBarOnly)
        self.hasCompletedOnboarding = persistence.value(for: SettingsKeys.hasCompletedOnboarding)
        self.selectedLanguageModelID = persistence
            .value(for: SettingsKeys.selectedLanguageModelID)
            .map(ModelIdentifier.init(rawValue:))
        self.styleStrength = persistence.value(for: SettingsKeys.styleStrength)
        self.languageModelUnloadTimeout = persistence.value(for: SettingsKeys.languageModelUnloadTimeout)

        // Repair the one combination that leaves the app unreachable.
        //
        // Property observers do not run during `init`, so a stored pair of "no Dock icon"
        // and "no menu bar icon" would be loaded verbatim and produce an app that is
        // running with no icon anywhere and no way to open its window — recoverable only
        // by deleting preferences from the Terminal. The `menuBarOnly` setter enforces
        // this too, but a setter cannot defend a value it never sees: these can arrive
        // from an older build, a synced preference file, or a hand-edited plist.
        if menuBarOnly, !showMenuBarIcon {
            showMenuBarIcon = true
            logger.warning(
                "Both app icons were hidden; restored the menu bar icon so the app stays reachable.",
                category: .settings
            )
        }

        logger.info("Settings loaded.", category: .settings)
    }

    /// The locale to transcribe in, resolving `nil` to the system language.
    var effectiveLocale: Locale {
        locale ?? .current
    }

    /// Restores every preference to its default.
    func resetToDefaults() {
        persistence.removeValue(for: SettingsKeys.selectedEngineID)
        persistence.removeValue(for: SettingsKeys.localeIdentifier)
        persistence.removeValue(for: SettingsKeys.selectedModelID)
        persistence.removeValue(for: SettingsKeys.dictationMode)
        persistence.removeValue(for: SettingsKeys.inputDeviceID)
        persistence.removeValue(for: SettingsKeys.toggleShortcut)
        persistence.removeValue(for: SettingsKeys.insertTextAutomatically)
        persistence.removeValue(for: SettingsKeys.playFeedbackSounds)
        persistence.removeValue(for: SettingsKeys.showMenuBarIcon)
        persistence.removeValue(for: SettingsKeys.menuBarOnly)
        persistence.removeValue(for: SettingsKeys.selectedLanguageModelID)
        persistence.removeValue(for: SettingsKeys.styleStrength)
        persistence.removeValue(for: SettingsKeys.languageModelUnloadTimeout)

        selectedEngineID = persistence
            .value(for: SettingsKeys.selectedEngineID)
            .map(SpeechEngineID.init(rawValue:))
        locale = persistence
            .value(for: SettingsKeys.localeIdentifier)
            .map(Locale.init(identifier:))
        selectedModelID = persistence
            .value(for: SettingsKeys.selectedModelID)
            .map(ModelIdentifier.init(rawValue:))
        dictationMode = .default
        inputDeviceID = persistence.value(for: SettingsKeys.inputDeviceID)
        toggleShortcut = persistence.value(for: SettingsKeys.toggleShortcut)
        insertTextAutomatically = persistence.value(for: SettingsKeys.insertTextAutomatically)
        playFeedbackSounds = persistence.value(for: SettingsKeys.playFeedbackSounds)
        showMenuBarIcon = persistence.value(for: SettingsKeys.showMenuBarIcon)
        menuBarOnly = persistence.value(for: SettingsKeys.menuBarOnly)
        selectedLanguageModelID = persistence
            .value(for: SettingsKeys.selectedLanguageModelID)
            .map(ModelIdentifier.init(rawValue:))
        styleStrength = persistence.value(for: SettingsKeys.styleStrength)
        languageModelUnloadTimeout = persistence.value(for: SettingsKeys.languageModelUnloadTimeout)

        logger.info("Settings reset to defaults.", category: .settings)
    }
}
