//
//  LanguageModelProviding.swift
//  LibreVoice
//

import Foundation

/// A runtime that can load a local language model and generate text with it.
///
/// This is the provider seam the sprint demands: LibreVoice never depends on a specific
/// model or runtime. Llama, Qwen and Gemma are all just GGUF files consumed by one
/// conforming runtime today; a different runtime tomorrow is a new conformance and one
/// changed line in the composition root — nothing else in the app moves.
///
/// Implementations are expected to be reference types (actors): a loaded model is
/// hundreds of megabytes of shared mutable state, and load/generate/unload must be
/// serialised against each other.
nonisolated protocol LanguageModelProviding: Sendable {
    /// The model file currently in memory, or `nil` when nothing is loaded.
    var loadedModelURL: URL? { get async }

    /// Loads the model at `url` into memory, replacing any previously loaded model.
    func load(modelAt url: URL) async throws

    /// Runs one completion: `system` sets the rules, `input` is the text to improve.
    ///
    /// Returns the model's reply with any chat-template scaffolding stripped. The
    /// provider applies the model's own chat template — templates differ per family
    /// (Llama, Qwen, Gemma), and hardcoding one would silently break the others.
    func generate(system: String, input: String) async throws -> String

    /// Releases the loaded model and its memory. Safe to call when nothing is loaded.
    func unload() async
}
