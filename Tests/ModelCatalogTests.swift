//
//  ModelCatalogTests.swift
//  LibreVoiceTests
//

import Foundation
import Testing
@testable import LibreVoice

@Suite("ModelChecksum")
struct ModelChecksumTests {
    @Test("Matching is case- and whitespace-insensitive")
    func normalisesInput() {
        let checksum = ModelChecksum(sha256: "  ABC123DEF  ")
        #expect(checksum.matches("abc123def"))
        #expect(checksum.matches("ABC123DEF"))
    }

    @Test("A different digest does not match")
    func rejectsDifferentDigest() {
        let checksum = ModelChecksum(sha256: "aaaa")
        #expect(!checksum.matches("aaab"))
        #expect(!checksum.matches("aaa"), "A length difference must not match.")
    }

    @Test("A checksum round-trips as a bare JSON string")
    func encodesAsBareString() throws {
        let checksum = ModelChecksum(sha256: "deadbeef")

        let data = try JSONEncoder().encode(checksum)
        #expect(String(decoding: data, as: UTF8.self) == "\"deadbeef\"")

        let restored = try JSONDecoder().decode(ModelChecksum.self, from: data)
        #expect(restored == checksum)
    }
}

@Suite("ModelDescriptor")
struct ModelDescriptorTests {
    @Test("Total size is the sum of the files")
    func totalSizeSumsFiles() {
        let descriptor = ModelDescriptor(
            id: ModelIdentifier(rawValue: "m"),
            engineID: SpeechEngineID(rawValue: "mlx-whisper"),
            displayName: "M",
            summary: "s",
            files: [
                ModelFile(path: "a", url: URL(string: "https://e.com/a")!, sizeBytes: 100, sha256: ModelChecksum(sha256: "x")),
                ModelFile(path: "b", url: URL(string: "https://e.com/b")!, sizeBytes: 250, sha256: ModelChecksum(sha256: "y")),
            ]
        )
        #expect(descriptor.totalSizeBytes == 350)
    }

    @Test("A model decodes from the catalog's JSON shape")
    func decodesFromCatalogJSON() throws {
        let json = Data("""
        {
          "id": "mlx-whisper-tiny",
          "engineID": "mlx-whisper",
          "displayName": "Whisper Tiny",
          "summary": "Fast and small.",
          "languageSupport": "multilingual",
          "files": [
            { "path": "config.json", "url": "https://huggingface.co/x/config.json", "sizeBytes": 262, "sha256": "aaff20ce" },
            { "path": "weights.npz", "url": "https://huggingface.co/x/weights.npz", "sizeBytes": 74418182, "sha256": "d5a3b867" }
          ]
        }
        """.utf8)

        let descriptor = try JSONDecoder().decode(ModelDescriptor.self, from: json)

        #expect(descriptor.id == ModelIdentifier(rawValue: "mlx-whisper-tiny"))
        #expect(descriptor.engineID == SpeechEngineID(rawValue: "mlx-whisper"))
        #expect(descriptor.files.count == 2)
        #expect(descriptor.files[1].sha256.sha256 == "d5a3b867")
        #expect(descriptor.totalSizeBytes == 74_418_444)
    }
}

@Suite("Bundled catalog")
struct BundledCatalogTests {
    /// The catalog LibreVoice actually ships must parse, name real engines, use HTTPS
    /// throughout, and carry a checksum on every file — the integrity guarantee is only
    /// as good as the catalog honouring it.
    @Test("The shipped catalog is well-formed and every file is HTTPS with a checksum")
    func shippedCatalogIsValid() async throws {
        // The tests are hosted in the app, so `Bundle.main` is the app bundle where the
        // catalog resource lives.
        let url = try #require(
            Bundle.main.url(forResource: "model-catalog", withExtension: "json"),
            "model-catalog.json must be bundled."
        )
        let catalog = JSONModelCatalog(url: url)
        let models = try await catalog.availableModels()

        #expect(!models.isEmpty, "The shipped catalog should offer models.")

        for model in models {
            #expect(!model.files.isEmpty, "\(model.id) has no files.")
            for file in model.files {
                #expect(file.url.scheme == "https", "\(model.id)/\(file.path) is not HTTPS.")
                #expect(file.sha256.sha256.count == 64, "\(model.id)/\(file.path) has no valid SHA-256.")
                #expect(file.sizeBytes > 0, "\(model.id)/\(file.path) has no size.")
            }
        }
    }
}
