//
//  NullLogger.swift
//  LibreVoice
//

import Foundation

/// A logger that discards every record.
///
/// Used by SwiftUI previews and unit tests, where log output is noise. Having an
/// explicit do-nothing implementation means call sites never need an optional
/// logger or an `if let` dance (Null Object pattern).
nonisolated struct NullLogger: Logger {
    init() {}

    func write(_ entry: LogEntry) {
        // Intentionally empty.
    }
}
