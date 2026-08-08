//
//  WhisperCppEngine.swift
//  LibreVoice
//

import Foundation
import WhisperRuntime

/// Speech recognition through whisper.cpp — the engine LibreVoice v1 ships.
///
/// Entirely offline: the GGML model file is read from disk, inference runs in-process
/// (Metal-accelerated on Apple silicon), and nothing touches the network. The engine is
/// a *batch* consumer of the audio stream: it collects the utterance while the user
/// speaks and transcribes when the stream ends. That shape is deliberate — it matches
/// the product's Listening → Thinking → Typing flow, and it is where whisper.cpp is at
/// its most accurate. Text still arrives progressively: whisper reports each segment as
/// it settles, which this engine forwards as ``TranscriptionEvent/partial(_:)`` so the
/// UI can type along with recognition.
///
/// The C calls themselves live in the `WhisperRuntime` package rather than here. That is
/// not tidiness: whisper and llama each carry their own incompatible ggml, and a Swift
/// module that can see both fails to compile. Neither is visible from the app module.
///
/// An `actor` because it owns the loaded model and a run-state flag, both of which must
/// never be touched concurrently.
actor WhisperCppEngine: SpeechRecognitionEngine {
    nonisolated let descriptor: SpeechEngineDescriptor

    private let modelURL: URL
    private let logger: any Logger

    /// The loaded whisper context, owned by this actor. Released in ``shutdown()``.
    private var context: WhisperContext?

    /// Whether ``transcribe(_:options:)`` is currently running.
    private var isRunning = false

    /// Set when ``shutdown()`` is called mid-run; the run releases the model as it ends.
    private var freeAfterRun = false

    /// Inference below this much gated audio is refused as "no speech": half a second
    /// cannot contain a word.
    private static let minimumDuration: TimeInterval = 0.5

    /// The VAD stage that strips silence before inference.
    private static let voiceGate = EnergyVoiceGate()

    init(descriptor: SpeechEngineDescriptor, modelURL: URL, logger: any Logger = NullLogger()) {
        self.descriptor = descriptor
        self.modelURL = modelURL
        self.logger = logger
    }

    // MARK: - SpeechRecognitionEngine

    func prepare() async throws {
        guard context == nil else { return }

        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw SpeechRecognitionError.modelNotInstalled(name: modelURL.lastPathComponent)
        }

        // Loading a model reads hundreds of megabytes and builds GPU buffers — seconds of
        // blocking work that must not run on the cooperative thread pool.
        let path = modelURL.path
        let loaded = await Self.onWorkQueue { WhisperContext.load(modelPath: path) }

        guard let loaded else {
            logger.error("whisper.cpp couldn't load the model.", category: .speech)
            throw SpeechRecognitionError.engineUnavailable(
                reason: String(localized: "The speech model couldn't be loaded. It may be corrupted — try downloading it again.")
            )
        }

        context = loaded
        logger.info("whisper.cpp ready (model: \(modelURL.lastPathComponent)).", category: .speech)
    }

    nonisolated func transcribe(
        _ audio: AsyncStream<AudioChunk>,
        options: TranscriptionOptions
    ) -> AsyncThrowingStream<TranscriptionEvent, any Error> {
        AsyncThrowingStream { continuation in
            let cancelled = CancellationFlag()
            let task = Task {
                do {
                    try await self.run(audio: audio, options: options, cancelled: cancelled, into: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                cancelled.cancel()
                task.cancel()
            }
        }
    }

    func shutdown() async {
        if isRunning {
            // The model is in use on the work queue; releasing it now would be a
            // use-after-free. The run releases it on its way out instead.
            freeAfterRun = true
            return
        }
        if let context {
            context.close()
            self.context = nil
            logger.info("whisper.cpp model released.", category: .speech)
        }
    }

    // MARK: - The run

    private func run(
        audio: AsyncStream<AudioChunk>,
        options: TranscriptionOptions,
        cancelled: CancellationFlag,
        into continuation: AsyncThrowingStream<TranscriptionEvent, any Error>.Continuation
    ) async throws {
        guard let context else {
            throw SpeechRecognitionError.engineUnavailable(
                reason: String(localized: "The speech engine wasn't prepared.")
            )
        }
        guard !isRunning else {
            throw SpeechRecognitionError.transcriptionFailed(
                reason: String(localized: "A transcription is already running.")
            )
        }

        isRunning = true
        defer {
            isRunning = false
            if freeAfterRun {
                context.close()
                self.context = nil
                freeAfterRun = false
            }
        }

        // 1. Collect the utterance. Cheap append work; chunks arrive at speech pace.
        var captured: [Float] = []
        for await chunk in audio {
            if cancelled.isCancelled { throw SpeechRecognitionError.cancelled }
            captured.append(contentsOf: chunk.samples)
        }
        if cancelled.isCancelled { throw SpeechRecognitionError.cancelled }

        // 2. VAD: keep the speech, drop the silence. Whisper *hallucinates* on quiet
        // audio — a minute of room tone around one sentence produced an entire invented
        // dialogue in live testing — and an invented sentence typed into someone's
        // document is the single worst failure mode a dictation app can have. Gating
        // also makes inference proportional to what was said, not to how long the
        // microphone was open.
        let gated = Self.voiceGate.gate(captured, sampleRate: AudioFormat.speech.sampleRate)
        let samples = gated.samples
        guard gated.containsSpeech, samples.count >= Int(Self.minimumDuration * AudioFormat.speech.sampleRate) else {
            logger.info(
                "Skipping transcription: no speech detected in \(String(format: "%.1f", TimeInterval(captured.count) / AudioFormat.speech.sampleRate))s of audio.",
                category: .speech
            )
            continuation.yield(.completed)
            continuation.finish()
            return
        }

        logger.info(
            "Transcribing \(String(format: "%.1f", gated.speechDuration))s of speech (from \(String(format: "%.1f", TimeInterval(captured.count) / AudioFormat.speech.sampleRate))s captured).",
            category: .speech
        )

        // 3. Run inference off the actor. Handing the context to the work queue is safe
        // because `isRunning` guarantees exclusive use and `shutdown()` defers releasing
        // it until this run ends.
        let utterance = samples
        let language = Self.whisperLanguage(for: options.locale)
        let emitPartials = options.includePartialResults
        let threads = Int32(max(2, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))

        let result: Int32 = await Self.onWorkQueue {
            context.run(
                samples: utterance,
                language: language,
                threadCount: threads,
                shouldAbort: { cancelled.isCancelled },
                onProgress: { segments in
                    guard emitPartials else { return }
                    let (text, range) = Self.join(segments)
                    guard !text.isEmpty else { return }
                    continuation.yield(.partial(TranscriptionSegment(text: text, timeRange: range)))
                }
            )
        }

        if cancelled.isCancelled { throw SpeechRecognitionError.cancelled }
        guard result == 0 else {
            throw SpeechRecognitionError.transcriptionFailed(
                reason: String(localized: "The recogniser returned an error (code \(result)).")
            )
        }

        // 4. Commit the settled text once, as a single final segment.
        let (text, range) = Self.join(context.segments)
        if !text.isEmpty {
            continuation.yield(.final(TranscriptionSegment(text: text, timeRange: range)))
        }
        continuation.yield(.completed)
        continuation.finish()
        logger.info("Transcription finished (\(text.count) characters).", category: .speech)
    }

    // MARK: - Interpreting what whisper reported

    /// A segment whose no-speech probability exceeds this is discarded as noise.
    ///
    /// The second anti-hallucination line, behind the VAD: when residual room noise
    /// does reach the model, Whisper still *reports* its own doubt per segment — and a
    /// segment the model itself half-believes is not speech must never be typed into
    /// someone's document.
    private static let maximumNoSpeechProbability: Float = 0.5

    /// Joins the credible segments into one string with its span.
    nonisolated static func join(
        _ segments: [WhisperSegment]
    ) -> (text: String, range: ClosedRange<TimeInterval>?) {
        var pieces: [String] = []
        var start: TimeInterval?
        var end: TimeInterval?

        for segment in segments where segment.noSpeechProbability <= maximumNoSpeechProbability {
            pieces.append(segment.text)
            start = min(start ?? segment.startSeconds, segment.startSeconds)
            end = max(end ?? segment.endSeconds, segment.endSeconds)
        }

        let text = pieces.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start, let end, start <= end else { return (text, nil) }
        return (text, start...end)
    }

    /// The ISO 639-1 code whisper should transcribe in, or `nil` for auto-detection.
    private nonisolated static func whisperLanguage(for locale: Locale) -> String? {
        guard let code = locale.language.languageCode?.identifier.lowercased() else { return nil }
        // An unknown code would make the run fail outright; auto-detect instead.
        return WhisperContext.supportsLanguage(code) ? code : nil
    }

    // MARK: - Work queue

    /// Serial queue for model loading and inference — blocking work that must stay off
    /// the Swift cooperative thread pool.
    private static let workQueue = DispatchQueue(label: "com.librevoice.whisper", qos: .userInitiated)

    private static func onWorkQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            workQueue.async { continuation.resume(returning: work()) }
        }
    }
}

/// A thread-safe cancellation flag readable from whisper's own threads.
private nonisolated final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        value = true
    }
}
