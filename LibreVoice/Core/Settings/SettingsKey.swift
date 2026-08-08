//
//  SettingsKey.swift
//  LibreVoice
//

import Foundation

/// A typed name for one stored preference.
///
/// The generic parameter is what removes the usual `UserDefaults` hazards: a key can
/// only be read as the type it was declared with, so no call site can ask for a `Bool`
/// and receive a `String`, and no key can be misspelled at one of its two use sites.
nonisolated struct SettingsKey<Value: Codable & Sendable>: Sendable {
    /// The name the value is stored under. Persisted — do not change it casually.
    let name: String

    /// The value to use when nothing has been stored.
    let defaultValue: Value

    init(name: String, defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

/// The preferences LibreVoice stores.
///
/// Gathered in one place so the full extent of what the app persists can be read at a
/// glance — which, for an app that promises to keep to itself, should be short and
/// auditable.
nonisolated enum SettingsKeys {
    /// The speech engine the user picked. `nil` means "whatever the registry defaults to".
    static let selectedEngineID = SettingsKey<String?>(name: "speech.selectedEngineID", defaultValue: nil)

    /// The language to transcribe, as a locale identifier. `nil` means the system language.
    static let localeIdentifier = SettingsKey<String?>(name: "speech.localeIdentifier", defaultValue: nil)

    /// The downloaded model to transcribe with. `nil` means the best installed model.
    static let selectedModelID = SettingsKey<String?>(name: "speech.selectedModelID", defaultValue: nil)

    /// How transcribed text is processed before insertion. Stored as ``DictationMode``'s
    /// raw value; `nil` has never been stored, so the default lives on the mode itself.
    static let dictationMode = SettingsKey<String?>(name: "dictation.mode", defaultValue: nil)

    /// The microphone to capture from. `nil` means the system default input.
    static let inputDeviceID = SettingsKey<String?>(name: "audio.inputDeviceID", defaultValue: nil)

    /// The shortcut that starts and stops dictation.
    static let toggleShortcut = SettingsKey<HotkeyShortcut>(
        name: "hotkeys.toggleDictation",
        defaultValue: .defaultToggleDictation
    )

    /// Whether to type transcribed text into the frontmost app.
    static let insertTextAutomatically = SettingsKey<Bool>(name: "dictation.insertTextAutomatically", defaultValue: true)

    /// Whether to play a sound when dictation starts and stops.
    static let playFeedbackSounds = SettingsKey<Bool>(name: "dictation.playFeedbackSounds", defaultValue: true)

    /// Whether to show the menu bar icon.
    static let showMenuBarIcon = SettingsKey<Bool>(name: "app.showMenuBarIcon", defaultValue: true)

    /// Whether to hide the Dock icon and live only in the menu bar. On by default: this
    /// is a tool used from within other apps, so a Dock tile it rarely returns to is
    /// mostly clutter. The menu bar item stays the way back in.
    static let menuBarOnly = SettingsKey<Bool>(name: "app.menuBarOnly", defaultValue: true)

    /// Whether the user has been through the welcome flow.
    static let hasCompletedOnboarding = SettingsKey<Bool>(name: "app.hasCompletedOnboarding", defaultValue: false)

    /// The local language model Precision enhances with. `nil` means none selected,
    /// which leaves Precision running rules and terminology only.
    static let selectedLanguageModelID = SettingsKey<String?>(name: "precision.languageModelID", defaultValue: nil)

    /// How strongly Precision preserves the user's personal style, `0...1`.
    /// `0` disables the language-model stage entirely.
    static let styleStrength = SettingsKey<Double>(name: "precision.styleStrength", defaultValue: 0.5)

    /// Seconds of idleness before the language model is unloaded from memory.
    static let languageModelUnloadTimeout = SettingsKey<Double>(name: "precision.modelUnloadTimeout", defaultValue: 45)
}
