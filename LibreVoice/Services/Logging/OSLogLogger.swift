//
//  OSLogLogger.swift
//  LibreVoice
//

import Foundation
import os

/// Forwards records to Apple's unified logging system, where they are visible in
/// Console.app and captured in sysdiagnose bundles.
///
/// One `os.Logger` is created per ``LogCategory`` up front, so `write` never
/// allocates and stays cheap enough to call from audio callbacks.
nonisolated final class OSLogLogger: Logger {
    private let loggers: [LogCategory: os.Logger]
    private let minimumLevel: LogLevel

    /// Creates a logger writing to `subsystem`.
    ///
    /// - Parameters:
    ///   - subsystem: The unified logging subsystem. Defaults to the app's bundle identifier.
    ///   - minimumLevel: Records below this level are dropped. Defaults to `.debug` in
    ///     Debug builds and `.info` in Release builds.
    init(
        subsystem: String = Bundle.main.bundleIdentifier ?? "com.librevoice.LibreVoice",
        minimumLevel: LogLevel? = nil
    ) {
        self.loggers = Dictionary(
            uniqueKeysWithValues: LogCategory.allCases.map { category in
                (category, os.Logger(subsystem: subsystem, category: category.rawValue))
            }
        )

        if let minimumLevel {
            self.minimumLevel = minimumLevel
        } else {
            #if DEBUG
            self.minimumLevel = .debug
            #else
            self.minimumLevel = .info
            #endif
        }
    }

    func write(_ entry: LogEntry) {
        guard entry.level >= minimumLevel, let logger = loggers[entry.category] else { return }

        // The message is marked `.public` because LibreVoice's own log messages never
        // contain user speech — see the note on `LogEntry`. Keeping them readable is
        // what makes a bug report from a user useful.
        logger.log(
            level: entry.level.osLogType,
            "[\(entry.source.fileName, privacy: .public):\(entry.source.line, privacy: .public)] \(entry.message, privacy: .public)"
        )
    }
}

private nonisolated extension LogLevel {
    /// The unified logging type that best matches this level.
    var osLogType: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .warning: .default
        case .error: .error
        }
    }
}
