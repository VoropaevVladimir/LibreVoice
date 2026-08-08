//
//  AudioInputDevice.swift
//  LibreVoice
//

import Foundation

/// A microphone the user can dictate into.
nonisolated struct AudioInputDevice: Sendable, Identifiable, Hashable {
    /// A stable identifier for the device, suitable for persisting in settings.
    let id: String

    /// The name macOS shows for this device, such as "MacBook Pro Microphone".
    let name: String

    /// Whether this is the system's current default input.
    let isDefault: Bool

    init(id: String, name: String, isDefault: Bool) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}
