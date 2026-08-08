//
//  ModelChecksum.swift
//  LibreVoice
//

import Foundation

/// A cryptographic fingerprint a downloaded model must match.
///
/// This is the load-bearing security value of the whole download subsystem. A speech
/// model is not passive data — it is fed to an inference engine that trusts its
/// contents. A model swapped in transit, or served by a compromised mirror, must be
/// rejected before it is ever loaded. Comparing the download against a checksum the
/// distributor published out-of-band is what makes that possible.
///
/// Only SHA-256 is modelled. MD5 and SHA-1 are both broken against collision attacks and
/// have no place verifying something that will be executed against; offering them as an
/// option would only invite their use.
nonisolated struct ModelChecksum: Sendable, Hashable, Codable {
    /// The expected SHA-256 digest, as lowercase hexadecimal.
    let sha256: String

    init(sha256: String) {
        // Normalised on the way in so a catalog written with uppercase hex, or stray
        // whitespace, still compares equal to a computed digest.
        self.sha256 = sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // Encoded as a bare string ("abc123…"), not an object, so a catalog file reads
    // `"sha256": "abc123…"` rather than `"sha256": { "sha256": "abc123…" }`.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(sha256: try container.decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256)
    }

    /// Whether `candidate` (lowercase hex) matches, compared without leaking timing.
    ///
    /// A byte-by-byte compare that bails on the first mismatch would, in principle, let
    /// an attacker who can measure timing learn the expected digest one character at a
    /// time. The digest is not secret, so the risk is largely theoretical — but constant
    /// time costs nothing here and is the correct habit in code that has been through a
    /// security review.
    func matches(_ candidate: String) -> Bool {
        let expected = Array(sha256.utf8)
        let actual = Array(candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().utf8)
        guard expected.count == actual.count else { return false }

        var difference: UInt8 = 0
        for index in expected.indices {
            difference |= expected[index] ^ actual[index]
        }
        return difference == 0
    }
}
