//
//  LogLevel.swift
//  LibreVoice
//

import Foundation

/// The severity of a log record, ordered from most verbose to most serious.
///
/// `LogLevel` is `Comparable` so a minimum level can act as a filter:
///
/// ```swift
/// let visible = entries.filter { $0.level >= .warning }
/// ```
nonisolated enum LogLevel: Int, Sendable, Comparable, CaseIterable, Identifiable {
    /// Fine-grained detail useful only while diagnosing a problem.
    case debug = 0

    /// Ordinary lifecycle information, such as a service starting or stopping.
    case info = 1

    /// Something unexpected happened, but the app recovered from it.
    case warning = 2

    /// A failure the user is likely to notice.
    case error = 3

    var id: Int { rawValue }

    /// A short, human-readable name suitable for display in the log viewer.
    var displayName: String {
        switch self {
        case .debug: String(localized: "Debug")
        case .info: String(localized: "Info")
        case .warning: String(localized: "Warning")
        case .error: String(localized: "Error")
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
