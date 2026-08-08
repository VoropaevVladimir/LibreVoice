//
//  SpeechEngineID.swift
//  LibreVoice
//

import Foundation

/// A stable identifier for a speech recognition backend.
///
/// Deliberately a `RawRepresentable` wrapper around `String` rather than an `enum`:
/// an enum would have to list every engine, which would put knowledge of concrete
/// engines into `Core` and make adding one a change to shared code. With this, an
/// engine names itself and `Core` stays ignorant of the roster.
///
/// - Important: Raw values are persisted in user settings. Changing one orphans the
///   preference of everyone already using that engine.
nonisolated struct SpeechEngineID: RawRepresentable, Sendable, Hashable, Codable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension SpeechEngineID: CustomStringConvertible {
    var description: String { rawValue }
}
