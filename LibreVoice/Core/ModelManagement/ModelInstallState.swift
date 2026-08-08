//
//  ModelInstallState.swift
//  LibreVoice
//

import Foundation

/// Where one model is in its lifecycle from "offered" to "ready".
nonisolated enum ModelInstallState: Sendable, Equatable {
    /// Available in the catalog, not on this Mac.
    case notInstalled

    /// Downloading. Carries live progress for the bar.
    case downloading(ModelDownloadProgress)

    /// Downloaded; its checksum is being computed and compared.
    ///
    /// A distinct state because verifying a multi-gigabyte file takes long enough that
    /// showing "installing…" instead would look like a hang.
    case verifying

    /// On disk and ready. Carries the actual on-disk size.
    case installed(sizeBytes: Int64)

    /// The last install attempt failed. Carries why, so the UI can explain and offer a retry.
    case failed(ModelError)

    /// Whether the model is downloaded and usable.
    var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }

    /// Whether an install is currently underway.
    var isBusy: Bool {
        switch self {
        case .downloading, .verifying: true
        case .notInstalled, .installed, .failed: false
        }
    }
}
