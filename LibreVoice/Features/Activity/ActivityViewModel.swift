//
//  ActivityViewModel.swift
//  LibreVoice
//

import Foundation
import Observation

/// Drives the activity screen.
@Observable
@MainActor
final class ActivityViewModel {
    /// The records to show, newest first.
    private(set) var entries: [LogEntry] = []

    /// Hide records below this level.
    var minimumLevel: LogLevel = .debug {
        didSet { reload() }
    }

    /// Show only this category, or every category when `nil`.
    var category: LogCategory? {
        didSet { reload() }
    }

    private let logRecords: any LogRecordReading

    /// How often the list refreshes while visible.
    ///
    /// Polling, because ``LogRecordReading`` is deliberately a plain synchronous
    /// interface that any backend can implement — pushing changes would force every
    /// logger to become observable, to serve one screen. A second is imperceptible here
    /// and costs nothing.
    private let refreshInterval: Duration = .seconds(1)

    init(container: any ServiceContainer) {
        self.logRecords = container.logRecords
        reload()
    }

    /// Refreshes the list for as long as the screen is visible.
    func observe() async {
        while !Task.isCancelled {
            reload()
            try? await Task.sleep(for: refreshInterval)
        }
    }

    /// Discards every record.
    func clear() {
        logRecords.clear()
        reload()
    }

    /// The visible records as plain text, for pasting into a bug report.
    func exportText() -> String {
        entries
            .reversed()
            .map { entry in
                let timestamp = entry.timestamp.formatted(date: .omitted, time: .standard)
                return "\(timestamp) [\(entry.level.displayName)] [\(entry.category.displayName)] \(entry.message)"
            }
            .joined(separator: "\n")
    }

    private func reload() {
        entries = logRecords.snapshot()
            .filter { $0.level >= minimumLevel }
            .filter { category == nil || $0.category == category }
            .reversed()
    }
}
