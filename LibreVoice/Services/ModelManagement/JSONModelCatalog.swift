//
//  JSONModelCatalog.swift
//  LibreVoice
//

import Foundation

/// Reads the model catalog from a JSON document.
///
/// Today the document is bundled with the app; the same type reads a catalog fetched from
/// a URL without changing, because it only cares about the bytes. Keeping the catalog as
/// data — rather than a hard-coded Swift array — is what lets the distributor add models,
/// or repoint them to a mirror, by editing one file. The catalog is the trust anchor: the
/// SHA-256 in it is what every download is checked against.
nonisolated struct JSONModelCatalog: ModelCatalog {
    /// The on-disk shape of the catalog file.
    private struct Document: Decodable {
        let schemaVersion: Int
        let models: [ModelDescriptor]
    }

    private let url: URL?
    private let logger: any Logger

    /// Reads the catalog from `url`, defaulting to `model-catalog.json` in the app bundle.
    init(
        url: URL? = Bundle.main.url(forResource: "model-catalog", withExtension: "json"),
        logger: any Logger = NullLogger()
    ) {
        self.url = url
        self.logger = logger
    }

    func availableModels() async throws -> [ModelDescriptor] {
        guard let url else {
            logger.warning("No model catalog is bundled with this build.", category: .speech)
            return []
        }

        let data = try Data(contentsOf: url)
        let document = try JSONDecoder().decode(Document.self, from: data)

        // A newer catalog than this build understands: read it rather than refuse it, so a
        // hosted catalog can add fields without breaking older apps. `Codable` already
        // ignores unknown keys; this is just where a hard incompatibility would be caught.
        guard document.schemaVersion >= 1 else {
            logger.warning("Model catalog schema \(document.schemaVersion) is unsupported.", category: .speech)
            return []
        }

        logger.info("Loaded \(document.models.count) models from the catalog.", category: .speech)
        return document.models
    }
}
