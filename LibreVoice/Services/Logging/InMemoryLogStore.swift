//
//  InMemoryLogStore.swift
//  LibreVoice
//

import Foundation
import Synchronization

/// Keeps the most recent log records in memory so the user can read them inside the
/// app, without any log file ever touching the disk.
///
/// This exists for a privacy reason, not a debugging one: "no telemetry" is easy to
/// claim and hard to verify, so LibreVoice shows people exactly what it recorded and
/// lets them copy it into a bug report themselves.
///
/// Records are held in a bounded ring buffer; the oldest are dropped once `limit` is
/// reached, so a long-running session cannot grow without bound.
///
/// State is guarded by a `Mutex` rather than an `actor` because ``Logger/write(_:)``
/// is synchronous and must be callable from any isolation domain.
nonisolated final class InMemoryLogStore: Logger, LogRecordReading {
    private let entries = Mutex<[LogEntry]>([])
    private let limit: Int

    /// Creates a store that retains at most `limit` records.
    init(limit: Int = 1_000) {
        self.limit = max(1, limit)
    }

    func write(_ entry: LogEntry) {
        entries.withLock { entries in
            entries.append(entry)
            if entries.count > limit {
                entries.removeFirst(entries.count - limit)
            }
        }
    }

    /// The retained records, oldest first.
    func snapshot() -> [LogEntry] {
        entries.withLock { $0 }
    }

    /// Discards every retained record.
    func clear() {
        entries.withLock { $0.removeAll(keepingCapacity: false) }
    }
}
