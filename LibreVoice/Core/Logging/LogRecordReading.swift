//
//  LogRecordReading.swift
//  LibreVoice
//

import Foundation

/// Read access to retained log records.
///
/// Split from ``Logger`` because writing and reading are different jobs with different
/// audiences: every service writes, only the log viewer reads, and most `Logger`
/// backends (the unified log, the null logger) cannot read back at all. Keeping them
/// separate means a backend implements only what it can actually do (Interface
/// Segregation), and it keeps the concrete `InMemoryLogStore` out of ``ServiceContainer``.
nonisolated protocol LogRecordReading: Sendable {
    /// The retained records, oldest first.
    func snapshot() -> [LogEntry]

    /// Discards every retained record.
    func clear()
}
