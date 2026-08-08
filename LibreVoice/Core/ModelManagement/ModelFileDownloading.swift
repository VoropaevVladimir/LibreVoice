//
//  ModelFileDownloading.swift
//  LibreVoice
//

import Foundation

/// Downloads a file to a temporary location, reporting progress.
///
/// This is the seam that keeps the network out of the tests. `FileSystemModelRepository`
/// owns all the interesting logic — disk checks, checksum verification, atomic install —
/// and none of it should need a live server to test. A fake downloader that copies a
/// local fixture lets every one of those paths be exercised offline, including the
/// security-critical checksum-mismatch path.
///
/// The returned URL is a temporary file the caller takes ownership of: it must move or
/// delete it. Cancelling the calling task cancels the download.
nonisolated protocol ModelFileDownloading: Sendable {
    /// Downloads `url` to a temporary file and returns its location.
    ///
    /// - Parameters:
    ///   - url: The source. Implementations must reject anything but HTTPS.
    ///   - expectedSize: The size from the catalog, used only to report progress when the
    ///     server omits a content length.
    ///   - onProgress: Called as bytes arrive, on an arbitrary thread.
    /// - Returns: A temporary file the caller must move or delete.
    /// - Throws: ``ModelError``.
    func download(
        from url: URL,
        expectedSize: Int64?,
        onProgress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> URL
}
