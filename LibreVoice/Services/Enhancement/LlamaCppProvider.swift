//
//  LlamaCppProvider.swift
//  LibreVoice
//

import Foundation
import LlamaRuntime

/// The llama.cpp runtime behind ``LanguageModelProviding``.
///
/// A thin adapter over `LlamaRuntime.LlamaEngine`, which lives in its own package so
/// that llama's bundled ggml never meets whisper's in one module (see the package's
/// Package.swift for the collision this avoids). This type's only jobs are protocol
/// conformance and translating the engine's errors into the app's ``EnhancementError``.
final class LlamaCppProvider: LanguageModelProviding, Sendable {
    private let engine: LlamaEngine
    private let logger: any Logger

    init(logger: any Logger = NullLogger()) {
        self.engine = LlamaEngine()
        self.logger = logger
    }

    var loadedModelURL: URL? {
        get async { await engine.loadedModelURL }
    }

    func load(modelAt url: URL) async throws {
        do {
            try await engine.load(modelAt: url)
            logger.info("Language model loaded.", category: .speech)
        } catch let error as LlamaEngine.EngineError {
            throw EnhancementError.generationFailed(reason: error.reason)
        }
    }

    func generate(system: String, input: String) async throws -> String {
        do {
            return try await engine.generate(system: system, input: input)
        } catch let error as LlamaEngine.EngineError {
            throw EnhancementError.generationFailed(reason: error.reason)
        }
    }

    func unload() async {
        await engine.unload()
        logger.info("Language model unloaded.", category: .speech)
    }
}
