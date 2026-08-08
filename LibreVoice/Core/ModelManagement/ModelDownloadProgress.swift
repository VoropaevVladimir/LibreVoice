//
//  ModelDownloadProgress.swift
//  LibreVoice
//

import Foundation

/// How far a model download has got.
nonisolated struct ModelDownloadProgress: Sendable, Equatable {
    /// Bytes written to disk so far.
    let bytesReceived: Int64

    /// The total size, or `nil` when the server did not report a length.
    let totalBytes: Int64?

    init(bytesReceived: Int64, totalBytes: Int64?) {
        self.bytesReceived = max(0, bytesReceived)
        self.totalBytes = totalBytes
    }

    /// Completion in `0...1`, or `nil` when the total is unknown so the UI shows an
    /// indeterminate bar rather than a misleading one.
    var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, Double(bytesReceived) / Double(totalBytes))
    }

    /// A short "12.4 MB of 466 MB" style description for the UI.
    var description: String {
        let received = ByteCountFormatter.string(fromByteCount: bytesReceived, countStyle: .file)
        guard let totalBytes else { return received }
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return String(localized: "\(received) of \(total)", comment: "Download progress, e.g. “12 MB of 466 MB”")
    }

    static let zero = ModelDownloadProgress(bytesReceived: 0, totalBytes: nil)
}
