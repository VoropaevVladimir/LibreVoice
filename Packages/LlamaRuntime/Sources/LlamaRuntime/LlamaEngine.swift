//
//  LlamaEngine.swift
//  LlamaRuntime
//

import Foundation
internal import llama

/// A loaded GGUF model and the ability to run one chat completion on it.
///
/// The public surface is deliberately free of llama.cpp types — that is the whole point
/// of this package (see Package.swift). One engine serves every model family in
/// LibreVoice's catalog: Llama, Qwen and Gemma are all GGUF files to llama.cpp, and each
/// model's own chat template (stored in its GGUF metadata) is applied at generation
/// time. Hardcoding any single family's template would silently break the others.
///
/// ## Threading
///
/// `@unchecked Sendable` with every C call confined to one serial `DispatchQueue`,
/// bridged through continuations. An actor would be the reflex, but llama.cpp calls
/// *block for seconds* — running them on an actor would pin a thread of the cooperative
/// pool, which Swift Concurrency forbids. A dedicated queue is the supported escape
/// hatch: inference occupies its own thread, the pool stays free, and the serial queue
/// provides the same mutual exclusion an actor would.
public final class LlamaEngine: @unchecked Sendable {
    /// Why the engine could not load or generate. A plain reason string, so the app
    /// can wrap it in its own error types without importing anything of llama's.
    public struct EngineError: Error, Sendable {
        public let reason: String
    }

    private let queue = DispatchQueue(label: "com.librevoice.llama-inference", qos: .userInitiated)

    /// Confined to `queue`.
    private var model: OpaquePointer?
    private var modelURL: URL?

    /// Process-wide llama.cpp initialisation, exactly once. The log callback swallows
    /// llama's stderr chatter — the host app has its own logger, and model-loading spam
    /// in the Console would read as something being wrong when nothing is.
    private static let backendReady: Void = {
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
    }()

    public init() {}

    deinit {
        if let model { llama_model_free(model) }
    }

    // MARK: - Public API

    /// The model file currently in memory, or `nil` when nothing is loaded.
    public var loadedModelURL: URL? {
        get async {
            await withCheckedContinuation { continuation in
                queue.async { continuation.resume(returning: self.modelURL) }
            }
        }
    }

    /// Loads the GGUF at `url`, replacing any previously loaded model.
    public func load(modelAt url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async {
                do {
                    try self.loadOnQueue(url)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// One demonstration turn pair: what the user sent, what the assistant should reply.
    public struct Example: Sendable {
        public let input: String
        public let output: String

        public init(input: String, output: String) {
            self.input = input
            self.output = output
        }
    }

    /// Runs one completion: `system` sets the rules, `examples` are replayed as prior
    /// chat turns, and `input` is the text to improve.
    public func generate(
        system: String,
        examples: [Example] = [],
        input: String
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try self.generateOnQueue(
                        system: system, examples: examples, input: input
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Releases the loaded model and its memory. Safe to call when nothing is loaded.
    public func unload() async {
        await withCheckedContinuation { continuation in
            queue.async {
                if let model = self.model {
                    llama_model_free(model)
                    self.model = nil
                    self.modelURL = nil
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Queue-confined implementation

    private func loadOnQueue(_ url: URL) throws {
        _ = Self.backendReady

        if let model {
            llama_model_free(model)
            self.model = nil
            modelURL = nil
        }

        var params = llama_model_default_params()
        // Every layer on the GPU: Metal is the whole point of running on Apple silicon,
        // and llama.cpp falls back to CPU by itself where Metal is unavailable.
        params.n_gpu_layers = 999

        guard let loaded = llama_model_load_from_file(url.path, params) else {
            throw EngineError(reason: "the model file couldn't be loaded")
        }

        model = loaded
        modelURL = url
    }

    private func generateOnQueue(system: String, examples: [Example], input: String) throws -> String {
        guard let model else {
            throw EngineError(reason: "no model is loaded")
        }
        guard let vocab = llama_model_get_vocab(model) else {
            throw EngineError(reason: "the model has no vocabulary")
        }

        let prompt = chatPrompt(system: system, examples: examples, input: input, model: model)

        // Tokenise the full templated prompt. `parse_special: true` because the chat
        // template's markers ("<|im_start|>", …) are text here and must become the
        // control tokens the model was trained on.
        var tokens = try tokenize(prompt, vocab: vocab)

        // The reply is an edit of the input, so it is about the input's size — budget
        // twice that plus headroom, and let end-of-generation stop us sooner.
        let replyBudget = max(128, min(1536, input.utf8.count / 2))

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(tokens.count + replyBudget + 16)
        contextParams.n_batch = UInt32(max(512, tokens.count))

        guard let context = llama_init_from_model(model, contextParams) else {
            throw EngineError(reason: "the inference context couldn't be created")
        }
        defer { llama_free(context) }

        let samplerParams = llama_sampler_chain_default_params()
        guard let sampler = llama_sampler_chain_init(samplerParams) else {
            throw EngineError(reason: "the sampler couldn't be created")
        }
        defer { llama_sampler_free(sampler) }
        // Greedy, deliberately: text correction wants the single most likely edit,
        // reproducibly — creative variance is a defect in an editor.
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())

        // Feed the prompt, then sample token by token until the model closes the reply.
        guard llama_decode(context, llama_batch_get_one(&tokens, Int32(tokens.count))) == 0 else {
            throw EngineError(reason: "the prompt couldn't be evaluated")
        }

        var reply = Data()
        var produced = 0
        while produced < replyBudget {
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }

            reply.append(piece(for: token, vocab: vocab))
            produced += 1

            guard llama_decode(context, llama_batch_get_one(&token, 1)) == 0 else { break }
        }

        guard let text = String(data: reply, encoding: .utf8) else {
            throw EngineError(reason: "the reply wasn't valid UTF-8")
        }
        return text
    }

    // MARK: - Prompt assembly

    /// The prompt in the model's own chat format.
    ///
    /// The template comes from the GGUF metadata via `llama_model_chat_template`; the
    /// ChatML fallback only exists for a model shipped without one, which none of the
    /// catalog models are.
    private func chatPrompt(
        system: String,
        examples: [Example],
        input: String,
        model: OpaquePointer
    ) -> String {
        guard let template = llama_model_chat_template(model, nil) else {
            return chatMLPrompt(system: system, examples: examples, input: input)
        }

        // system, then example turns in order, then the real request.
        var turns: [(role: String, content: String)] = [("system", system)]
        for example in examples {
            turns.append(("user", example.input))
            turns.append(("assistant", example.output))
        }
        turns.append(("user", input))

        var messages = turns.map {
            llama_chat_message(role: strdup($0.role), content: strdup($0.content))
        }
        defer {
            for message in messages {
                free(UnsafeMutablePointer(mutating: message.role))
                free(UnsafeMutablePointer(mutating: message.content))
            }
        }

        var capacity = turns.reduce(512) { $0 + $1.content.utf8.count * 2 }
        while true {
            var buffer = [CChar](repeating: 0, count: capacity)
            let written = llama_chat_apply_template(
                template, &messages, messages.count, true, &buffer, Int32(capacity)
            )
            if written < 0 {
                // The template engine refused this template; fall back to ChatML.
                return chatMLPrompt(system: system, examples: examples, input: input)
            }
            if Int(written) <= capacity {
                return String(decoding: buffer[0..<Int(written)].map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
            capacity = Int(written) + 1
        }
    }

    private func chatMLPrompt(system: String, examples: [Example], input: String) -> String {
        var prompt = "<|im_start|>system\n\(system)<|im_end|>\n"
        for example in examples {
            prompt += "<|im_start|>user\n\(example.input)<|im_end|>\n"
            prompt += "<|im_start|>assistant\n\(example.output)<|im_end|>\n"
        }
        prompt += "<|im_start|>user\n\(input)<|im_end|>\n<|im_start|>assistant\n"
        return prompt
    }

    // MARK: - Token helpers

    private func tokenize(_ text: String, vocab: OpaquePointer) throws -> [llama_token] {
        let byteCount = Int32(text.utf8.count)
        // First call with no buffer returns the negated required count.
        let required = -llama_tokenize(vocab, text, byteCount, nil, 0, true, true)
        guard required > 0 else {
            throw EngineError(reason: "the prompt couldn't be tokenised")
        }
        var tokens = [llama_token](repeating: 0, count: Int(required))
        let written = llama_tokenize(vocab, text, byteCount, &tokens, required, true, true)
        guard written > 0 else {
            throw EngineError(reason: "the prompt couldn't be tokenised")
        }
        tokens.removeLast(tokens.count - Int(written))
        return tokens
    }

    /// One token's bytes. `special: false` so control tokens render as nothing —
    /// the reply must never contain "<|im_end|>".
    private func piece(for token: llama_token, vocab: OpaquePointer) -> Data {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = llama_token_to_piece(vocab, token, &buffer, 256, 0, false)
        guard length > 0 else { return Data() }
        return Data(buffer[0..<Int(length)].map { UInt8(bitPattern: $0) })
    }
}
