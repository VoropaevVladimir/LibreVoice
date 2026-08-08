//
//  Logger.swift
//  LibreVoice
//

import Foundation

/// A destination for log records.
///
/// The protocol deliberately has a single requirement. Everything callers actually
/// use — ``debug(_:category:fileID:function:line:)`` and friends — is provided as a
/// protocol extension, so a new backend only has to implement one method. This keeps
/// conforming types trivial (Interface Segregation) and means convenience APIs can
/// grow without breaking existing implementations.
///
/// Conformances must be safe to call from any isolation domain, including real-time
/// audio callbacks, hence the `Sendable` requirement and the synchronous `write`.
nonisolated protocol Logger: Sendable {
    /// Records a single entry. Must be non-blocking and safe to call concurrently.
    func write(_ entry: LogEntry)
}

// MARK: - Convenience API

// `nonisolated` is load-bearing, not decoration. The project builds with
// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so an unannotated extension would be
// inferred as main-actor isolated — and a logger that can only be called from the main
// actor is useless to an audio tap or an `actor`-based service.
nonisolated extension Logger {
    /// Records fine-grained detail useful only while diagnosing a problem.
    func debug(
        _ message: String,
        category: LogCategory = .app,
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        write(
            LogEntry(
                level: .debug,
                category: category,
                message: message,
                source: SourceLocation(fileID: fileID, function: function, line: line)
            )
        )
    }

    /// Records ordinary lifecycle information.
    func info(
        _ message: String,
        category: LogCategory = .app,
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        write(
            LogEntry(
                level: .info,
                category: category,
                message: message,
                source: SourceLocation(fileID: fileID, function: function, line: line)
            )
        )
    }

    /// Records something unexpected that the app recovered from.
    func warning(
        _ message: String,
        category: LogCategory = .app,
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        write(
            LogEntry(
                level: .warning,
                category: category,
                message: message,
                source: SourceLocation(fileID: fileID, function: function, line: line)
            )
        )
    }

    /// Records a failure the user is likely to notice.
    ///
    /// - Parameter error: When provided, its description is appended to `message`.
    func error(
        _ message: String,
        error: (any Error)? = nil,
        category: LogCategory = .app,
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        let text = if let error {
            "\(message): \(error.localizedDescription)"
        } else {
            message
        }
        write(
            LogEntry(
                level: .error,
                category: category,
                message: text,
                source: SourceLocation(fileID: fileID, function: function, line: line)
            )
        )
    }
}
