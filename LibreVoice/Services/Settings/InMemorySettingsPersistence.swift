//
//  InMemorySettingsPersistence.swift
//  LibreVoice
//

import Foundation
import Synchronization

/// Keeps preferences in memory only.
///
/// Used by previews and tests so they neither depend on nor damage the real
/// `UserDefaults` — a preview that flips a switch should not change the developer's
/// actual settings, and a test should start from a known state every time.
nonisolated final class InMemorySettingsPersistence: SettingsPersistence {
    private let storage = Mutex<[String: any Sendable]>([:])

    /// Creates an empty store, so every key reports its default.
    init() {}

    func value<Value>(for key: SettingsKey<Value>) -> Value {
        storage.withLock { storage in
            storage[key.name] as? Value ?? key.defaultValue
        }
    }

    func setValue<Value>(_ value: Value, for key: SettingsKey<Value>) {
        storage.withLock { $0[key.name] = value }
    }

    func removeValue<Value>(for key: SettingsKey<Value>) {
        storage.withLock { _ = $0.removeValue(forKey: key.name) }
    }
}
