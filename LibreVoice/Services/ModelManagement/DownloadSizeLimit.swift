//
//  DownloadSizeLimit.swift
//  LibreVoice
//

import Foundation

/// Decides when a transfer has sent more than the catalog said it would.
///
/// Its own type, rather than a couple of lines inside the `URLSession` delegate, because
/// it is a security control and an untested security control quietly stops working. The
/// delegate needs a live server to exercise; this needs two integers.
///
/// The checksum is still the real integrity check — but it only runs once the bytes are on
/// disk. Without a ceiling, a hostile or compromised mirror could stream gigabytes into the
/// temporary directory and fill the volume before anything looked at the hash.
nonisolated enum DownloadSizeLimit {
    /// How far past the declared size a transfer may go before it is abandoned.
    ///
    /// Not zero: catalog sizes are written by hand and a file may legitimately be a few
    /// bytes off. Small enough that overshooting it cannot fill a disk.
    static let tolerance: Int64 = 1_048_576

    /// Whether `received` bytes is already too many for a file declared as `expected`.
    ///
    /// Returns `false` when the expected size is unknown or nonsensical: a limit invented
    /// out of nothing would abort legitimate downloads, and the checksum still guards the
    /// result. This only enforces a bound the catalog actually stated.
    static func isOversize(received: Int64, expected: Int64?) -> Bool {
        guard let expected, expected > 0 else { return false }
        return received > expected + tolerance
    }
}
