//
//  LogEntry.swift
//  LibreVoice
//

import Foundation

/// The place in the source where a log record was created.
nonisolated struct SourceLocation: Sendable, Equatable {
    /// The `#fileID` of the call site, for example `LibreVoice/DictationCoordinator.swift`.
    let fileID: String

    /// The `#function` of the call site.
    let function: String

    /// The `#line` of the call site.
    let line: Int

    /// Just the file name, without the module prefix.
    var fileName: String {
        fileID.split(separator: "/").last.map(String.init) ?? fileID
    }

    init(fileID: String = #fileID, function: String = #function, line: Int = #line) {
        self.fileID = fileID
        self.function = function
        self.line = line
    }
}

/// A single structured record produced by the logging system.
///
/// - Important: A `message` must never contain transcribed speech, audio contents,
///   or anything else derived from what the user dictated. LibreVoice logs *that*
///   something happened, never *what* was said. See `Documentation/Architecture.md`.
nonisolated struct LogEntry: Sendable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    let message: String
    let source: SourceLocation

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        level: LogLevel,
        category: LogCategory,
        message: String,
        source: SourceLocation
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.source = source
    }
}
