//
//  FileChecksum.swift
//  LibreVoice
//

import CryptoKit
import Foundation

/// Computes the SHA-256 digest of a file.
///
/// Lives in `Services`, not `Core`, because it imports CryptoKit — `Core` is confined to
/// Foundation. `Core` describes *what* a checksum is (``ModelChecksum``); this computes one.
///
/// The file is read in chunks and fed to the hasher incrementally, so a multi-gigabyte
/// model is verified without ever being fully resident in memory. Hashing the whole file
/// in one `Data(contentsOf:)` would work for a tiny model and page the machine to a crawl
/// on a large one.
nonisolated enum FileChecksum {
    /// The size of each read. 1 MiB balances syscall overhead against memory use.
    private static let chunkSize = 1 << 20

    /// Returns the lowercase-hex SHA-256 of the file at `url`.
    ///
    /// - Throws: ``ModelError/storageFailed(reason:)`` if the file cannot be read.
    static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ModelError.storageFailed(reason: "couldn't read the downloaded file")
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: chunkSize) ?? Data()
            } catch {
                throw ModelError.storageFailed(reason: "couldn't read the downloaded file")
            }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)

            // Verifying a big file is cancellable — no reason to keep hashing gigabytes
            // for a download the user already walked away from.
            if Task.isCancelled { throw ModelError.cancelled }
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
