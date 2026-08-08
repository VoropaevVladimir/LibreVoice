//
//  ModelIdentifier.swift
//  LibreVoice
//

import Foundation

/// A stable identifier for a downloadable speech model.
///
/// A `String` wrapper rather than an `enum`, for the same reason ``SpeechEngineID`` is:
/// the set of models is not known to `Core`. It is data, supplied by a ``ModelCatalog``
/// at run time and — once LibreVoice ships — hosted wherever the distributor chooses.
///
/// - Important: The raw value is persisted (a downloaded model is stored under a name
///   derived from it) and may arrive from a remote catalog, so it is treated as
///   untrusted input when it becomes a file name. See `FileSystemModelRepository`.
nonisolated struct ModelIdentifier: RawRepresentable, Sendable, Hashable, Codable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension ModelIdentifier: CustomStringConvertible {
    var description: String { rawValue }
}
