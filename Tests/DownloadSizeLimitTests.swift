//
//  DownloadSizeLimitTests.swift
//  LibreVoiceTests
//

import Foundation
import Testing
@testable import LibreVoice

@Suite("Download size limit")
struct DownloadSizeLimitTests {
    private let expected: Int64 = 100_000_000 // 100 MB, a plausible model file

    @Test("A transfer within its declared size is allowed through")
    func normalDownloadIsAllowed() {
        #expect(DownloadSizeLimit.isOversize(received: 0, expected: expected) == false)
        #expect(DownloadSizeLimit.isOversize(received: expected / 2, expected: expected) == false)
        #expect(DownloadSizeLimit.isOversize(received: expected, expected: expected) == false)
    }

    @Test("A file slightly larger than declared is tolerated, not aborted")
    func smallOvershootIsTolerated() {
        #expect(
            DownloadSizeLimit.isOversize(received: expected + 1_000, expected: expected) == false,
            "Catalog sizes are hand-written; a few bytes off must not fail a real download."
        )
        #expect(DownloadSizeLimit.isOversize(received: expected + DownloadSizeLimit.tolerance, expected: expected) == false)
    }

    @Test("A server sending far more than declared is stopped")
    func runawayTransferIsRefused() {
        #expect(DownloadSizeLimit.isOversize(received: expected + DownloadSizeLimit.tolerance + 1, expected: expected))
        #expect(
            DownloadSizeLimit.isOversize(received: 50_000_000_000, expected: expected),
            "This is the case that matters: 50 GB aimed at a 100 MB file must never reach the disk in full."
        )
    }

    @Test("An unknown declared size enforces nothing rather than guessing one")
    func unknownExpectedSizeIsNotEnforced() {
        #expect(DownloadSizeLimit.isOversize(received: 50_000_000_000, expected: nil) == false)
        #expect(
            DownloadSizeLimit.isOversize(received: 50_000_000_000, expected: 0) == false,
            "A limit invented from a missing value would abort legitimate downloads; the checksum still guards the result."
        )
    }
}
