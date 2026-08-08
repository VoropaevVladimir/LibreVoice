//
//  ModelCatalog.swift
//  LibreVoice
//

import Foundation

/// The source of truth for which models exist and where to get them.
///
/// Abstracted so the catalog can move without the app changing: today a JSON file in the
/// bundle, tomorrow a JSON document fetched from the distributor's website so models can
/// be added without an app update. Both are just "a list of ``ModelDescriptor`` values",
/// which is all this protocol promises.
nonisolated protocol ModelCatalog: Sendable {
    /// Every model the catalog offers.
    ///
    /// - Throws: if the catalog itself cannot be read (a malformed file, an unreachable
    ///   host). An empty catalog is a success, not an error.
    func availableModels() async throws -> [ModelDescriptor]
}

extension ModelCatalog {
    /// The models belonging to `engineID`.
    func models(for engineID: SpeechEngineID) async throws -> [ModelDescriptor] {
        try await availableModels().filter { $0.engineID == engineID }
    }
}
