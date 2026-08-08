//
//  SpeechEngineWarmUp.swift
//  LibreVoice
//

import Foundation

/// Pays an engine's first-load cost before the user ever presses the shortcut.
///
/// ## Why this exists
///
/// Core ML compiles a model for the Neural Engine the first time it is loaded and caches
/// the result on disk. For Parakeet that compile is **~85 seconds**; every load after it
/// takes half a second. Without a warm-up the bill lands on the first dictation: the
/// capsule sits in its thinking state for a minute and a half, which is indistinguishable
/// from a hang — and a user who gives up and quits has just thrown away the compile they
/// were waiting for, so the next attempt starts over.
///
/// The fix is not to keep models in memory — that was rejected deliberately, an idle app
/// should not hold gigabytes. Warm-up builds the engine, prepares it, and **immediately
/// shuts it down**. Nothing is retained; what survives is Core ML's on-disk cache, which
/// is the expensive part. The cost is paid once, in the background, at a moment nobody is
/// waiting on it.
///
/// Whisper needs none of this — a GGML file loads in a second — but the warm-up is engine
/// agnostic on purpose: it asks the registry for whatever engine is selected and prepares
/// it. A future engine with a heavy first load is covered without touching this file.
actor SpeechEngineWarmUp {
    private let engines: any SpeechEngineProviding
    private let logger: any Logger

    /// Main-actor state the interface reads, so the compile is visible rather than a
    /// silent minute in which the app looks broken.
    private let status: SpeechWarmUpStatus?

    /// The engine most recently warmed, so selecting the same model twice does not
    /// repeat the work.
    private var warmedEngineID: SpeechEngineID?
    private var inFlight: Task<Void, Never>?

    init(
        engines: any SpeechEngineProviding,
        status: SpeechWarmUpStatus? = nil,
        logger: any Logger = NullLogger()
    ) {
        self.engines = engines
        self.status = status
        self.logger = logger
    }

    /// Prepares `engineID` — or the default engine when `nil` — unless it is already warm.
    ///
    /// Never throws: a warm-up that fails costs only the time it would have saved, and
    /// the real dictation will surface the same error properly. Cancelling replaces any
    /// warm-up already running, so switching models twice quickly does not queue two
    /// compiles.
    func warmUp(engineID: SpeechEngineID?) {
        inFlight?.cancel()
        inFlight = Task { [engines, logger, status] in
            let resolved: SpeechEngineID?
            if let engineID {
                resolved = engineID
            } else {
                resolved = await engines.defaultEngineID()
            }
            guard let id = resolved else { return }
            guard self.shouldWarm(id) else { return }

            await status?.beganPreparing(id)
            do {
                let engine = try await engines.makeEngine(for: id)
                let started = ContinuousClock.now
                try await engine.prepare()
                let elapsed = ContinuousClock.now.duration(to: started)

                // Released at once: the point is Core ML's disk cache, not a resident model.
                await engine.shutdown()

                self.markWarm(id)
                await status?.finishedPreparing(id, succeeded: true)
                logger.info(
                    "Warmed up “\(id.rawValue)” in \(elapsed).",
                    category: .speech
                )
            } catch {
                await status?.finishedPreparing(id, succeeded: false)
                logger.debug(
                    "Warm-up of “\(id.rawValue)” didn't complete; dictation will load it instead.",
                    category: .speech
                )
            }
        }
    }

    /// Waits for the warm-up in flight, if any.
    ///
    /// Nothing in the app calls this — warm-up exists precisely so that nobody waits. It
    /// is here for tests, which otherwise have no way to observe work that is deliberately
    /// fire-and-forget.
    func waitForCompletion() async {
        await inFlight?.value
    }

    private func shouldWarm(_ id: SpeechEngineID) -> Bool {
        warmedEngineID != id
    }

    private func markWarm(_ id: SpeechEngineID) {
        warmedEngineID = id
    }
}
