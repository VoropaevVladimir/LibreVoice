//
//  DictationCoordinator.swift
//  LibreVoice
//

import Foundation
import Observation

/// Runs a dictation session: microphone in, text out.
///
/// This is the one place that knows the *order* of things — check permission, build the
/// engine, open the microphone, stream audio through the engine, insert what comes back.
/// Views, view models and the menu bar all drive dictation through this single object,
/// so there is exactly one state machine and it cannot disagree with itself.
///
/// It depends only on `Core` protocols, never on AVFoundation or any engine, which is
/// what makes the whole flow testable with fakes: feed a canned audio stream through a
/// canned engine and assert on the states that come out.
///
/// - Note: The MVP wires the pipeline end to end but ships no real engine, so a session
///   reaches `.listening` and produces no text. Everything except transcription itself
///   is real, including permissions, capture, and the state machine.
@Observable
@MainActor
final class DictationCoordinator {
    /// Where the session currently is.
    private(set) var state: DictationState = .idle

    /// The live microphone level, for the meter.
    ///
    /// Kept beside ``state`` rather than inside it so that redrawing the meter sixty
    /// times a second does not invalidate every view watching the state.
    private(set) var audioLevel: AudioLevel = .silent

    /// The text recognised so far in this session.
    private(set) var transcript = Transcript()

    private let audioCapture: any AudioCaptureService
    private let speechEngines: any SpeechEngineProviding
    private let textInsertion: any TextInsertionService
    private let textProcessing: any TranscriptProcessing
    private let textEnhancement: (any TextEnhancing)?
    private let settings: AppSettings
    private let logger: any Logger

    /// The running session, if any. Cancelling it unwinds the whole pipeline.
    private var sessionTask: Task<Void, Never>?

    /// When non-nil, this session batches its text for language-model enhancement
    /// instead of inserting each settled segment. Captured once at session start, so a
    /// mid-session settings change cannot split one utterance across two behaviours.
    private var sessionEnhancement: EnhancementConfiguration?

    init(
        audioCapture: any AudioCaptureService,
        speechEngines: any SpeechEngineProviding,
        textInsertion: any TextInsertionService,
        textProcessing: any TranscriptProcessing = PassthroughTranscriptProcessing(),
        textEnhancement: (any TextEnhancing)? = nil,
        settings: AppSettings,
        logger: any Logger
    ) {
        self.audioCapture = audioCapture
        self.speechEngines = speechEngines
        self.textInsertion = textInsertion
        self.textProcessing = textProcessing
        self.textEnhancement = textEnhancement
        self.settings = settings
        self.logger = logger
    }

    // MARK: - Controlling a session

    /// Starts dictation if idle, stops it otherwise.
    ///
    /// This is what the hotkey and the menu bar call: a single entry point means the
    /// two can never race into contradictory states.
    func toggle() {
        if state.canStart {
            start()
        } else {
            stop()
        }
    }

    /// Starts a dictation session. Does nothing if one is already running.
    func start() {
        guard state.canStart else {
            logger.debug("Ignoring start; session already active.", category: .dictation)
            return
        }

        transcript.reset()
        sessionEnhancement = nil
        state = .preparing

        sessionTask = Task { [weak self] in
            await self?.runSession()
        }
    }

    /// Stops the current session, letting the engine finish the audio it already has.
    func stop() {
        guard state.isActive else { return }

        logger.info("Stopping dictation.", category: .dictation)
        state = .finishing

        // Closing the microphone finishes the audio stream, which lets the engine drain
        // and the session task end on its own. Cancelling the task here instead would
        // throw away the last words the user spoke.
        Task { [audioCapture] in
            await audioCapture.stop()
        }
    }

    /// Clears a `.failed` state, returning to `.idle`.
    func dismissError() {
        guard case .failed = state else { return }
        state = .idle
    }

    // MARK: - The pipeline

    private func runSession() async {
        do {
            // Microphone first, engine second. With push-to-talk the first word comes
            // the instant the key goes down, and a Whisper model takes seconds to load —
            // opening capture immediately and preparing the engine *while the user is
            // already speaking* is what keeps those first words. The audio stream
            // buffers everything captured in the meantime; the engine drains it whenever
            // it becomes ready.
            let audio = try await startCapture()

            if state == .preparing {
                state = .listening
                logger.info("Dictation started.", category: .dictation)
            } else {
                // Released before the microphone even finished opening. Close it again;
                // the (near-empty) stream drains through the engine and the session
                // ends cleanly rather than leaving the microphone running.
                await audioCapture.stop()
            }

            let engine = try await resolveEngine()
            try await engine.prepare()

            // Decided before the first word settles: Precision with a ready language
            // model batches the whole utterance and inserts once; every other case
            // keeps inserting per settled segment exactly as before.
            sessionEnhancement = await activeEnhancement()

            let options = TranscriptionOptions(
                locale: settings.effectiveLocale,
                includePartialResults: true
            )

            for try await event in engine.transcribe(audio, options: options) {
                await handle(event)
            }

            // Recognition is shut down *before* enhancement runs, so whisper's working
            // memory is released before the language model claims its own.
            await engine.shutdown()

            if let configuration = sessionEnhancement {
                await enhanceAndInsertBatch(configuration: configuration)
            }
            await finishSession()
        } catch is CancellationError {
            await audioCapture.stop()
            state = .idle
        } catch let error as DictationError {
            await fail(with: error)
        } catch let error as AudioCaptureError {
            await fail(with: .audio(error))
        } catch let error as SpeechRecognitionError {
            await fail(with: .speech(error))
        } catch {
            await fail(with: .speech(.transcriptionFailed(reason: error.localizedDescription)))
        }
    }

    /// Builds the engine the user selected, falling back to the registry's default.
    private func resolveEngine() async throws -> any SpeechRecognitionEngine {
        if let selected = settings.selectedEngineID {
            return try await speechEngines.makeEngine(for: selected)
        }

        guard let defaultID = await speechEngines.defaultEngineID() else {
            throw DictationError.noEngineAvailable
        }
        return try await speechEngines.makeEngine(for: defaultID)
    }

    /// Opens the microphone and starts forwarding levels to the meter.
    private func startCapture() async throws -> AsyncStream<AudioChunk> {
        let raw = try await audioCapture.start(deviceID: settings.inputDeviceID)

        // The chunks are needed twice: by the engine, and by the meter. Rather than
        // consume the stream twice (which is not allowed), re-yield each chunk onward
        // after reading its level.
        return AsyncStream<AudioChunk> { continuation in
            let forwarding = Task { [weak self] in
                for await chunk in raw {
                    await MainActor.run { self?.audioLevel = chunk.level }
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in forwarding.cancel() }
        }
    }

    private func handle(_ event: TranscriptionEvent) async {
        // Final text runs through the mode's pipeline *before* it reaches the transcript,
        // so the window shows exactly what was (or would be) inserted. Partials stay raw:
        // they are a live preview and will be superseded anyway.
        var event = event
        if case .final(let segment) = event {
            let processed = textProcessing.process(segment.text, mode: settings.dictationMode)
            event = .final(TranscriptionSegment(
                id: segment.id,
                text: processed,
                timeRange: segment.timeRange,
                confidence: segment.confidence
            ))
        }

        guard let settled = transcript.apply(event) else { return }

        // An enhancement session inserts nothing yet: the transcript accumulates, and
        // the improved whole is inserted once at the end. Inserting segments now and
        // then enhancing them differently would leave two versions in the document.
        guard sessionEnhancement == nil else { return }

        guard settings.insertTextAutomatically else { return }
        guard !settled.isEmpty else { return }

        do {
            try await textInsertion.insert(settled)
        } catch {
            // A failure to type into another app must not kill the session — the text is
            // still in the transcript, where the user can copy it. Log and carry on.
            logger.error("Couldn't insert transcribed text.", error: error, category: .textInsertion)
        }
    }

    /// The enhancement configuration for the session about to run, or `nil` when the
    /// language-model stage must not.
    private func activeEnhancement() async -> EnhancementConfiguration? {
        guard settings.dictationMode == .precision, let textEnhancement else { return nil }

        let configuration = EnhancementConfiguration(
            modelID: settings.selectedLanguageModelID,
            styleStrength: settings.styleStrength,
            unloadTimeout: settings.languageModelUnloadTimeout
        )
        return await textEnhancement.isReady(configuration) ? configuration : nil
    }

    /// Improves the batched transcript with the language model and inserts it once.
    ///
    /// Failure never loses words: any enhancement error falls back to the text exactly
    /// as recognised, and the transcript always ends up showing what was inserted.
    private func enhanceAndInsertBatch(configuration: EnhancementConfiguration) async {
        let recognised = transcript.committedText
        guard !recognised.isEmpty else { return }

        var final = recognised
        if let textEnhancement {
            do {
                final = try await textEnhancement.enhance(recognised, configuration: configuration)
            } catch {
                logger.error(
                    "Couldn't enhance the transcript; inserting it as recognised.",
                    error: error,
                    category: .dictation
                )
            }
        }

        if final != recognised {
            transcript.replaceCommitted(with: final)
        }

        guard settings.insertTextAutomatically, !final.isEmpty else { return }
        do {
            try await textInsertion.insert(final)
        } catch {
            logger.error("Couldn't insert transcribed text.", error: error, category: .textInsertion)
        }
    }

    private func finishSession() async {
        audioLevel = .silent
        state = .idle
        logger.info("Dictation finished.", category: .dictation)
    }

    private func fail(with error: DictationError) async {
        await audioCapture.stop()
        audioLevel = .silent
        state = .failed(error)
        logger.error("Dictation failed.", error: error, category: .dictation)
    }
}
