//
//  ModelError.swift
//  LibreVoice
//

import Foundation

/// Something that stopped a model from being downloaded or installed.
nonisolated enum ModelError: LocalizedError, Sendable, Equatable {
    /// The catalog gave a non-HTTPS download URL. Refused before any request is made.
    case insecureURL(URL)

    /// The catalog entry's identifier could not be turned into a safe file name —
    /// typically an attempt at path traversal from an untrusted catalog.
    case unsafeIdentifier(ModelIdentifier)

    /// The server could not be reached, or returned an error.
    case downloadFailed(reason: String)

    /// The download completed but its checksum did not match. The file is deleted.
    ///
    /// This is the security-relevant failure: it means the bytes on the wire were not the
    /// bytes the distributor published, so the model is discarded rather than loaded.
    case checksumMismatch(expected: String, actual: String)

    /// There is not enough free disk space for the model.
    case insufficientDiskSpace(required: Int64, available: Int64)

    /// The download was cancelled before it finished.
    case cancelled

    /// The verified model could not be moved into place, or a stored model removed.
    case storageFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .insecureURL:
            return String(localized: "This model can only be downloaded over an insecure connection, so it was refused.")
        case .unsafeIdentifier:
            return String(localized: "This model has an invalid identifier and can't be stored safely.")
        case .downloadFailed(let reason):
            return String(localized: "The download failed: \(reason)")
        case .checksumMismatch:
            return String(localized: "The downloaded model didn't match its expected fingerprint and was discarded.")
        case .insufficientDiskSpace(let required, let available):
            let need = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
            let have = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            return String(localized: "Not enough disk space: \(need) needed, \(have) free.")
        case .cancelled:
            return String(localized: "The download was cancelled.")
        case .storageFailed(let reason):
            return String(localized: "The model couldn't be saved: \(reason)")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .insecureURL, .unsafeIdentifier:
            String(localized: "This looks like a problem with the model catalog. Report it to whoever provides your models.")
        case .checksumMismatch:
            String(localized: "Try again. If it keeps failing, the download source may be compromised — don't install it.")
        case .insufficientDiskSpace:
            String(localized: "Free up some space and try again.")
        case .downloadFailed:
            String(localized: "Check your internet connection and try again.")
        case .cancelled, .storageFailed:
            nil
        }
    }
}
