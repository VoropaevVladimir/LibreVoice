//
//  SettingsPersistence.swift
//  LibreVoice
//

import Foundation

/// Somewhere preferences can be kept.
///
/// Abstracted away from `UserDefaults` so tests and previews get a clean slate in
/// memory instead of scribbling on the developer's real preferences — and so that
/// where settings live stays a decision the app can revisit.
nonisolated protocol SettingsPersistence: Sendable {
    /// The stored value for `key`, or the key's default when nothing is stored.
    func value<Value>(for key: SettingsKey<Value>) -> Value

    /// Stores `value` under `key`.
    func setValue<Value>(_ value: Value, for key: SettingsKey<Value>)

    /// Removes the stored value for `key`, restoring its default.
    func removeValue<Value>(for key: SettingsKey<Value>)
}
