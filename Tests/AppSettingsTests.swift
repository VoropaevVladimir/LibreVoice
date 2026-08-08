//
//  AppSettingsTests.swift
//  LibreVoiceTests
//

import Foundation
import Testing
@testable import LibreVoice

@Suite("AppSettings")
@MainActor
struct AppSettingsTests {
    @Test("Fresh settings report the documented defaults")
    func defaultsAreAsDocumented() {
        let settings = AppSettings(persistence: InMemorySettingsPersistence())

        #expect(settings.selectedEngineID == nil, "No engine chosen means “follow the registry”, not a hard-coded engine.")
        #expect(settings.locale == nil)
        #expect(settings.inputDeviceID == nil)
        #expect(settings.toggleShortcut == .defaultToggleDictation)
        #expect(settings.insertTextAutomatically)
        #expect(settings.showMenuBarIcon)
        #expect(!settings.hasCompletedOnboarding)
    }

    @Test("Changes are written straight through to storage")
    func changesArePersisted() {
        let persistence = InMemorySettingsPersistence()
        let settings = AppSettings(persistence: persistence)

        settings.selectedEngineID = SpeechEngineID(rawValue: "whisper-cpp")
        settings.insertTextAutomatically = false
        settings.toggleShortcut = HotkeyShortcut(keyCode: 0x31, modifiers: .control)

        // A second object reading the same storage is how a relaunch would see them.
        let reloaded = AppSettings(persistence: persistence)

        #expect(reloaded.selectedEngineID == SpeechEngineID(rawValue: "whisper-cpp"))
        #expect(!reloaded.insertTextAutomatically)
        #expect(reloaded.toggleShortcut == HotkeyShortcut(keyCode: 0x31, modifiers: .control))
    }

    @Test("No locale means the system language")
    func effectiveLocaleFallsBackToSystem() {
        let settings = AppSettings(persistence: InMemorySettingsPersistence())

        #expect(settings.effectiveLocale == .current)

        settings.locale = Locale(identifier: "ru-RU")
        #expect(settings.effectiveLocale == Locale(identifier: "ru-RU"))
    }

    @Test("Resetting restores every default")
    func resetRestoresDefaults() {
        let settings = AppSettings(persistence: InMemorySettingsPersistence())
        settings.selectedEngineID = SpeechEngineID(rawValue: "something")
        settings.insertTextAutomatically = false
        settings.showMenuBarIcon = false

        settings.resetToDefaults()

        #expect(settings.selectedEngineID == nil)
        #expect(settings.insertTextAutomatically)
        #expect(settings.showMenuBarIcon)
    }

    @Test("A value stored under the wrong type falls back instead of trapping")
    func corruptValueFallsBackToDefault() {
        // Simulates a preference written by an older version whose type has since changed.
        let defaults = try! #require(UserDefaults(suiteName: "com.librevoice.tests.corrupt"))
        defaults.removePersistentDomain(forName: "com.librevoice.tests.corrupt")
        defaults.set("not valid json for a Bool", forKey: SettingsKeys.insertTextAutomatically.name)

        let persistence = UserDefaultsSettingsPersistence(defaults: defaults)
        let value = persistence.value(for: SettingsKeys.insertTextAutomatically)

        #expect(value == true, "Losing one preference beats failing to launch.")

        defaults.removePersistentDomain(forName: "com.librevoice.tests.corrupt")
    }

    // MARK: - The app must never become unreachable

    // Hiding the Dock icon and the menu bar icon at once leaves LibreVoice running with
    // no icon anywhere and no way to open its window — recoverable only by deleting
    // preferences from a Terminal. The settings screen disables the second toggle, but a
    // rule that lives in a view is one code path away from being broken.

    @Test("Hiding the Dock icon forces the menu bar icon back on")
    func hidingTheDockIconKeepsTheMenuBarIcon() {
        let settings = AppSettings(persistence: InMemorySettingsPersistence())
        settings.showMenuBarIcon = false

        settings.menuBarOnly = true

        #expect(settings.showMenuBarIcon)
    }

    @Test("The menu bar icon cannot be switched off while it is the only one left")
    func menuBarIconCannotBeHiddenWhenItIsTheOnlyOne() {
        let settings = AppSettings(persistence: InMemorySettingsPersistence())
        settings.menuBarOnly = true

        settings.showMenuBarIcon = false

        #expect(settings.showMenuBarIcon, "Turning off the last icon must not be possible from any code path.")
    }

    @Test("Settings stored with both icons hidden are repaired on load")
    func storedUnreachableStateIsRepairedAtLaunch() {
        // Property observers do not run during init, so this pair — from an older build, a
        // synced preference file, or a hand-edited plist — would otherwise load verbatim.
        let persistence = InMemorySettingsPersistence()
        persistence.setValue(true, for: SettingsKeys.menuBarOnly)
        persistence.setValue(false, for: SettingsKeys.showMenuBarIcon)

        let settings = AppSettings(persistence: persistence)

        #expect(settings.showMenuBarIcon, "Launching into an app with no icon anywhere is not a recoverable state.")
    }
}

@Suite("InMemoryLogStore")
struct InMemoryLogStoreTests {
    private func entry(_ message: String, level: LogLevel = .info) -> LogEntry {
        LogEntry(level: level, category: .app, message: message, source: SourceLocation())
    }

    @Test("Records come back in the order they were written")
    func recordsArePreservedInOrder() {
        let store = InMemoryLogStore()

        store.write(entry("first"))
        store.write(entry("second"))

        #expect(store.snapshot().map(\.message) == ["first", "second"])
    }

    @Test("The buffer is bounded, so a long session cannot grow without limit")
    func oldestRecordsAreDropped() {
        let store = InMemoryLogStore(limit: 3)

        for index in 1...5 {
            store.write(entry("\(index)"))
        }

        #expect(store.snapshot().map(\.message) == ["3", "4", "5"])
    }

    @Test("Clearing discards everything, as the Activity screen promises")
    func clearDiscardsEverything() {
        let store = InMemoryLogStore()
        store.write(entry("something"))

        store.clear()

        #expect(store.snapshot().isEmpty)
    }

    @Test("A composite logger reaches every destination")
    func compositeLoggerFansOut() {
        let first = InMemoryLogStore()
        let second = InMemoryLogStore()
        let logger = CompositeLogger([first, second])

        logger.info("hello", category: .app)

        #expect(first.snapshot().count == 1)
        #expect(second.snapshot().count == 1, "The unified log and the in-app viewer must both see every record.")
    }
}
