//
//  SpeechRecognitionEngine.swift
//  LibreVoice
//

import Foundation

/// A speech recognition backend.
///
/// This is the seam the whole application is built around. LibreVoice must be able to
/// gain an engine — MLX Whisper, whisper.cpp, Apple's `Speech` framework, a remote
/// API — without a single line changing outside that engine's own folder. Three rules
/// keep that true:
///
/// 1. **Nothing here names a technology.** No `WhisperModel`, no `SFSpeechRecognizer`,
///    no URL. The protocol is stated purely as audio in, text out.
/// 2. **Audio arrives as an `AsyncStream`.** A streaming engine consumes it as it
///    arrives; a batch engine (whisper.cpp wants a whole utterance) collects it and
///    transcribes on completion. Both fit without the caller knowing which it got.
/// 3. **Construction is someone else's job.** Engines are built by a
///    ``SpeechEngineFactory`` at the composition root, so the app depends on this
///    protocol and never on a concrete type.
///
/// Conformances are `Sendable` and typically `actor`s: transcription is slow, must not
/// touch the main thread, and needs somewhere to keep model state safely.
nonisolated protocol SpeechRecognitionEngine: Sendable {
    /// What this engine is and where it runs. Constant for the lifetime of the instance.
    var descriptor: SpeechEngineDescriptor { get }

    /// Loads models and allocates resources.
    ///
    /// Called before the first ``transcribe(_:options:)``. Idempotent — calling it on a
    /// prepared engine does nothing. Separate from `init` because loading a Whisper
    /// model takes seconds and can fail, and neither belongs in an initialiser.
    ///
    /// - Throws: ``SpeechRecognitionError`` if the engine cannot be made ready.
    func prepare() async throws

    /// Transcribes `audio`, emitting text as it is recognised.
    ///
    /// The returned stream finishes after ``TranscriptionEvent/completed`` once `audio`
    /// has finished and all text has been emitted. Cancelling the consuming task stops
    /// transcription.
    ///
    /// - Parameters:
    ///   - audio: Chunks in ``AudioFormat/speech``, finishing when the user stops speaking.
    ///   - options: How this run should behave.
    /// - Returns: A stream of events, failing with ``SpeechRecognitionError``.
    func transcribe(
        _ audio: AsyncStream<AudioChunk>,
        options: TranscriptionOptions
    ) -> AsyncThrowingStream<TranscriptionEvent, any Error>

    /// Releases models and resources.
    ///
    /// Whisper models occupy gigabytes of RAM; an idle app should not hold them.
    func shutdown() async
}
