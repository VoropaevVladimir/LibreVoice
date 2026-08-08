//
//  CompositeLogger.swift
//  LibreVoice
//

import Foundation

/// Broadcasts every record to several loggers at once.
///
/// This is how LibreVoice writes to the unified logging system *and* keeps a
/// buffer for the in-app log viewer without either backend knowing about the
/// other. Adding a third destination (a file, say) means composing it in at the
/// composition root — no existing type changes (Open/Closed).
nonisolated struct CompositeLogger: Logger {
    private let loggers: [any Logger]

    /// Creates a logger that forwards to each of `loggers`, in order.
    init(_ loggers: [any Logger]) {
        self.loggers = loggers
    }

    func write(_ entry: LogEntry) {
        for logger in loggers {
            logger.write(entry)
        }
    }
}
