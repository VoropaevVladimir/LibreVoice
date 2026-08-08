//
//  UserDefaultsSettingsPersistence.swift
//  LibreVoice
//

import Foundation

/// Stores preferences in `UserDefaults`.
///
/// Values are encoded as JSON rather than written as property-list primitives. That
/// costs a little speed on a code path that runs a handful of times per launch, and
/// buys the ability to store any `Codable` — ``HotkeyShortcut``, for one — through the
/// same typed API as a `Bool`, with no per-type special cases.
nonisolated final class UserDefaultsSettingsPersistence: SettingsPersistence {
    /// `UserDefaults` is documented as thread-safe but predates `Sendable` and has never
    /// been annotated, so the compiler has to be told. This is a gap in the annotation,
    /// not in the guarantee.
    private nonisolated(unsafe) let defaults: UserDefaults

    private let logger: any Logger

    /// Creates persistence backed by `defaults`.
    ///
    /// - Parameter defaults: Where to store values. Defaults to `.standard`.
    init(defaults: UserDefaults = .standard, logger: any Logger = NullLogger()) {
        self.defaults = defaults
        self.logger = logger
    }

    func value<Value>(for key: SettingsKey<Value>) -> Value {
        guard let data = defaults.data(forKey: key.name) else {
            return key.defaultValue
        }

        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            // A value written by an older version can fail to decode after a type
            // changes. Falling back to the default is better than trapping: the user
            // loses one preference instead of the ability to launch the app.
            logger.warning(
                "Couldn't decode setting “\(key.name)”; using its default value.",
                category: .settings
            )
            return key.defaultValue
        }
    }

    func setValue<Value>(_ value: Value, for key: SettingsKey<Value>) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key.name)
        } catch {
            logger.error("Couldn't encode setting “\(key.name)”.", error: error, category: .settings)
        }
    }

    func removeValue<Value>(for key: SettingsKey<Value>) {
        defaults.removeObject(forKey: key.name)
    }
}
