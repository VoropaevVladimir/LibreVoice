//
//  LocalModelTextEnhancer.swift
//  LibreVoice
//

import Foundation

/// The Precision enhancement stage: profile in, improved text out.
///
/// Owns the model's *lifecycle*, which is the part the sprint calls mandatory: the
/// model loads only when there is text to improve, stays warm while the user keeps
/// dictating, and unloads after a configurable idle timeout so gigabytes of weights
/// never sit in memory for nothing. The provider does the actual inference; this actor
/// decides when the provider is allowed to exist.
///
/// Built against ``LanguageModelProviding``, never a concrete runtime — swapping
/// llama.cpp for anything else changes one line in the composition root.
actor LocalModelTextEnhancer: TextEnhancing {
    /// The runtime, or `nil` in builds that ship without one. A nil provider makes
    /// `isReady` false and Precision falls back to rules-only behaviour — the feature
    /// degrades, the app does not.
    private let provider: (any LanguageModelProviding)?
    private let models: any ModelRepository
    private let profile: any WritingProfileStoring
    private let logger: any Logger

    /// The pending idle unload, cancelled whenever the model is used again.
    private var unloadTask: Task<Void, Never>?

    init(
        provider: (any LanguageModelProviding)?,
        models: any ModelRepository,
        profile: any WritingProfileStoring,
        logger: any Logger = NullLogger()
    ) {
        self.provider = provider
        self.models = models
        self.profile = profile
        self.logger = logger
    }

    // MARK: - TextEnhancing

    func isReady(_ configuration: EnhancementConfiguration) async -> Bool {
        guard provider != nil, configuration.styleStrength > 0 else { return false }
        guard let id = configuration.modelID,
              await models.installedLocation(of: id) != nil
        else { return false }

        // A personal prompt is required by design: LibreVoice never writes the system
        // prompt itself, so without the user's own there is nothing legitimate to say.
        return await profile.load().isConfigured
    }

    func enhance(_ text: String, configuration: EnhancementConfiguration) async throws -> String {
        guard let provider else { throw EnhancementError.runtimeUnavailable }
        guard let id = configuration.modelID,
              let location = await models.installedLocation(of: id),
              let modelFile = Self.modelFile(in: location)
        else { throw EnhancementError.modelNotInstalled }

        // The prompt is read fresh on every run, so an edit in Settings applies to the
        // very next dictation with no cache to invalidate.
        let writingProfile = await profile.load()
        guard let context = RuntimeContextBuilder.build(
            profile: writingProfile,
            styleStrength: configuration.styleStrength,
            transcript: text
        ) else { throw EnhancementError.promptMissing }

        // Using the model cancels its eviction; finishing schedules the next one —
        // in a defer, so even a thrown generation restarts the idle clock.
        unloadTask?.cancel()
        unloadTask = nil
        defer { scheduleUnload(after: configuration.unloadTimeout) }

        let current = await provider.loadedModelURL
        if current != modelFile {
            // Only a *different* model needs evicting first; unloading nothing would be
            // a phantom lifecycle event that muddies logs and tests alike.
            if current != nil {
                await provider.unload()
            }
            try await provider.load(modelAt: modelFile)
        }

        let reply = try await provider.generate(
            system: context.systemPrompt,
            input: context.userText
        )
        return try Self.accepted(reply: reply, for: text)
    }

    // MARK: - Lifecycle

    private func scheduleUnload(after timeout: TimeInterval) {
        unloadTask?.cancel()
        guard let provider, timeout > 0 else { return }

        unloadTask = Task {
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            await provider.unload()
        }
    }

    /// The single GGUF file inside an installed model's directory.
    private static func modelFile(in directory: URL) -> URL? {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return contents?.first { $0.pathExtension.lowercased() == "gguf" }
    }

    // MARK: - Acceptance

    /// Cleans the model's reply and refuses it when it plainly broke the rules.
    ///
    /// The system prompt already forbids summarising, inventing and conversing — but a
    /// local model is a probabilistic component, and the promise "the user's words
    /// survive" cannot rest on one. Small instruct models in particular slip into
    /// assistant mode and *answer* dictated text instead of correcting it, especially
    /// when it happens to read like a question. This is the barrier that catches that:
    /// anything not recognisably a corrected version of the original is discarded, and
    /// the caller inserts the text exactly as dictated.
    static func accepted(reply: String, for original: String) throws -> String {
        var cleaned = stripDecoration(reply)

        guard !cleaned.isEmpty else {
            throw EnhancementError.generationFailed(reason: "empty reply")
        }

        // Improving punctuation and grammar moves length by percent, not by half.
        // Outside these bounds the model summarised or invented — both forbidden.
        let ratio = Double(cleaned.count) / Double(max(original.count, 1))
        guard ratio >= 0.5, ratio <= 2.0 else {
            throw EnhancementError.generationFailed(reason: "reply length diverged from the original")
        }

        // The decisive check. A correction keeps nearly every word of the original; a
        // conversational answer — "Конечно! Чем ещё помочь?" — keeps almost none, however
        // plausible its length. Word overlap separates the two where no amount of
        // instruction reliably does.
        let retention = wordRetention(of: cleaned, from: original)
        guard retention >= 0.6 else {
            throw EnhancementError.generationFailed(
                reason: "the reply answered the text instead of correcting it"
            )
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }

    /// Removes the scaffolding models wrap answers in: code fences, a leading "Here is
    /// the corrected text:" and surrounding quotation marks.
    private static func stripDecoration(_ reply: String) -> String {
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)

        // A wrapping code fence, a habit some instruct models can't shake.
        if text.hasPrefix("```"), text.hasSuffix("```"), text.count > 6 {
            text = String(text.dropFirst(3).dropLast(3))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let newline = text.firstIndex(of: "\n"), !text[..<newline].contains(" ") {
                // The first fence line was a language tag ("markdown"), not content.
                text = String(text[text.index(after: newline)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // A preamble ending in a colon on its own first line: "Here is the corrected
        // text:", "Вот исправленный текст:". Only dropped when a body follows, and only
        // for a short opener — a colon inside real dictation must survive.
        if let newline = text.firstIndex(of: "\n") {
            let firstLine = text[..<newline].trimmingCharacters(in: .whitespaces)
            let body = String(text[text.index(after: newline)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if firstLine.hasSuffix(":"), firstLine.count <= 60, !body.isEmpty {
                text = body
            }
        }

        // Quotation marks around the whole reply.
        for (open, close) in [("\"", "\""), ("«", "»"), ("“", "”")] {
            if text.hasPrefix(open), text.hasSuffix(close), text.count > open.count + close.count {
                text = String(text.dropFirst(open.count).dropLast(close.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        return text
    }

    /// The share of the original's words that survive in `reply`, `0...1`.
    ///
    /// Compared on lowercased, punctuation-stripped words, because a correction is
    /// *expected* to change punctuation and case — those are the very things it fixes.
    /// Duplicates are counted once: what matters is whether the vocabulary survived, not
    /// how often each word recurs.
    static func wordRetention(of reply: String, from original: String) -> Double {
        let originalWords = words(in: original)
        guard !originalWords.isEmpty else { return 1 }

        let replyWords = words(in: reply)
        let kept = originalWords.filter(replyWords.contains).count
        return Double(kept) / Double(originalWords.count)
    }

    private static func words(in text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
    }
}
