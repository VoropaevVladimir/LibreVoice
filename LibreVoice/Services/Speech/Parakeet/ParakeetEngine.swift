//
//  ParakeetEngine.swift
//  LibreVoice
//

import Foundation
import FluidAudio

/// NVIDIA Parakeet TDT, run on the Neural Engine through Core ML.
///
/// The inference itself comes from **FluidAudio** (Apache-2.0), which ships the Core ML
/// conversions of Parakeet and the RNN-T decode loop that turns encoder frames into
/// tokens. Writing that decoder from scratch was the alternative; it is the kind of code
/// that fails quietly and produces plausible-but-wrong text, which is the worst failure
/// mode a dictation app has.
///
/// What LibreVoice keeps for itself is the part that matters to its promises: **the
/// models are downloaded by LibreVoice's own catalog**, every file verified against a
/// pinned SHA-256 before use, into LibreVoice's own folder. FluidAudio is handed a
/// directory and never reaches the network. Nothing about this engine sends audio
/// anywhere — it is Core ML on the local machine, like whisper.cpp beside it.
///
/// ## Batch, not streaming
///
/// Parakeet can stream, and one day this engine should. For now it collects the
/// utterance and transcribes on completion, exactly as ``WhisperCppEngine`` does, because
/// that is what the current push-to-talk gesture needs: the user holds a key, speaks, and
/// releases. Streaming would change the experience arc (Listening → Thinking → Typing),
/// not just this file, so it is a separate piece of work rather than a hidden difference
/// between two engines.
actor ParakeetEngine: SpeechRecognitionEngine {
    nonisolated let descriptor: SpeechEngineDescriptor

    private let modelDirectory: URL
    private let logger: any Logger

    /// The loaded models. Held between sessions so a second dictation does not pay the
    /// load again; released by ``shutdown()``.
    private var models: AsrModels?
    private var manager: AsrManager?

    init(descriptor: SpeechEngineDescriptor, modelDirectory: URL, logger: any Logger = NullLogger()) {
        self.descriptor = descriptor
        self.modelDirectory = modelDirectory
        self.logger = logger
    }

    // MARK: - SpeechRecognitionEngine

    func prepare() async throws {
        guard models == nil else { return }

        do {
            // `.v3` and `.int8` match exactly what the catalog downloads: the shared
            // Preprocessor, Encoder, Decoder and JointDecisionv3 bundles. Asking for a
            // combination the catalog does not carry would fail here rather than at the
            // first word, which is the right place for it to fail.
            let models = try await AsrModels.load(
                from: modelDirectory,
                version: .v3,
                encoderPrecision: .int8
            )
            let manager = AsrManager()
            try await manager.loadModels(models)

            self.models = models
            self.manager = manager
            logger.info("Parakeet models loaded.", category: .speech)
        } catch {
            logger.error("Couldn't load the Parakeet models.", error: error, category: .speech)
            throw SpeechRecognitionError.engineUnavailable(reason: error.localizedDescription)
        }
    }

    nonisolated func transcribe(
        _ audio: AsyncStream<AudioChunk>,
        options: TranscriptionOptions
    ) -> AsyncThrowingStream<TranscriptionEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(audio, options: options, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func shutdown() async {
        manager = nil
        models = nil
        logger.info("Parakeet models released.", category: .speech)
    }

    // MARK: - Recognition

    private func run(
        _ audio: AsyncStream<AudioChunk>,
        options: TranscriptionOptions,
        into continuation: AsyncThrowingStream<TranscriptionEvent, any Error>.Continuation
    ) async throws {
        try await prepare()
        guard let manager else {
            throw SpeechRecognitionError.engineUnavailable(
                reason: String(localized: "The Parakeet engine isn't ready.")
            )
        }

        // Collect the utterance. The samples are already 16 kHz mono float — the format
        // the capture layer converts to and the one Parakeet expects.
        var samples: [Float] = []
        for await chunk in audio {
            try Task.checkCancellation()
            samples.append(contentsOf: chunk.samples)
        }

        try Task.checkCancellation()
        guard !samples.isEmpty else {
            continuation.yield(.completed)
            return
        }

        // The decoder state is per-utterance: a fresh one each time is what makes each
        // dictation independent of the last, which is exactly the push-to-talk gesture.
        var decoderState = try TdtDecoderState()
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if !text.isEmpty {
            continuation.yield(.final(TranscriptionSegment(text: text)))
        }
        continuation.yield(.completed)
    }
}
