//
//  WhisperContext.swift
//  WhisperRuntime
//

import Foundation
internal import whisper

/// One recognised piece of speech, as whisper.cpp reports it.
///
/// A plain value type on purpose: nothing here is a C type, which is what lets the app
/// module use this package without ever loading whisper's headers (see Package.swift).
public struct WhisperSegment: Sendable, Equatable {
    /// The recognised text, exactly as the model produced it — untrimmed and unjoined.
    public let text: String

    /// Where the segment sits in the utterance.
    public let startSeconds: TimeInterval
    public let endSeconds: TimeInterval

    /// How strongly the model itself suspects this segment is *not* speech, 0...1.
    ///
    /// Surfaced rather than filtered here: what counts as too doubtful to type into
    /// someone's document is the app's judgement, not this package's.
    public let noSpeechProbability: Float

    public init(
        text: String,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval,
        noSpeechProbability: Float
    ) {
        self.text = text
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.noSpeechProbability = noSpeechProbability
    }
}

/// A loaded whisper.cpp model and the ability to transcribe one utterance with it.
///
/// ## What this type is and is not
///
/// It is a thin, faithful wrapper: no threading policy, no voice-activity detection, no
/// retry logic, no opinion about which segments deserve to be kept. All of that lives in
/// the app, where it can be tested without a 1.5 GB model file. What lives here is the
/// only thing that cannot live there — the C calls themselves.
///
/// ## Threading
///
/// `@unchecked Sendable`, and every method is blocking and *not* internally synchronised.
/// The caller owns the exclusion. That is not laziness: `whisper_full` blocks for seconds,
/// so the app runs it on a dedicated serial queue rather than the cooperative thread pool,
/// and it already guarantees a single run at a time. Adding a second lock here would
/// suggest a safety this type cannot actually provide — nothing stops a caller from using
/// the context after ``close()``.
public final class WhisperContext: @unchecked Sendable {
    private var pointer: OpaquePointer?

    private init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        if let pointer { whisper_free(pointer) }
    }

    /// Loads a GGML model from disk, or returns `nil` if whisper.cpp refuses it.
    ///
    /// Blocking: this reads hundreds of megabytes and builds GPU buffers. Call it from a
    /// thread you are willing to lose for a few seconds.
    public static func load(modelPath: String, useGPU: Bool = true) -> WhisperContext? {
        var params = whisper_context_default_params()
        params.use_gpu = useGPU
        guard let pointer = modelPath.withCString({ whisper_init_from_file_with_params($0, params) }) else {
            return nil
        }
        return WhisperContext(pointer: pointer)
    }

    /// Releases the model. Safe to call more than once; the context is unusable afterwards.
    public func close() {
        if let pointer { whisper_free(pointer) }
        pointer = nil
    }

    /// Whether whisper.cpp recognises this ISO 639-1 code.
    ///
    /// Worth asking before transcribing: an unknown code does not fall back to
    /// auto-detection, it makes the run fail outright.
    public static func supportsLanguage(_ code: String) -> Bool {
        code.withCString { whisper_lang_id($0) >= 0 }
    }

    /// Transcribes one utterance of 16 kHz mono float samples.
    ///
    /// Blocks until recognition finishes, is aborted, or fails. Returns whisper.cpp's own
    /// result code — `0` on success.
    ///
    /// - Parameters:
    ///   - language: ISO 639-1 code, or `nil` to let the model detect it.
    ///   - threadCount: How many threads inference may use.
    ///   - shouldAbort: Polled from whisper's threads; return `true` to stop early.
    ///   - onProgress: Called as each segment settles, with everything recognised so far.
    ///     Invoked on whisper's own threads, so it must be safe to call from anywhere.
    public func run(
        samples: [Float],
        language: String?,
        threadCount: Int32,
        shouldAbort: @escaping @Sendable () -> Bool,
        onProgress: @escaping @Sendable ([WhisperSegment]) -> Void
    ) -> Int32 {
        guard let pointer else { return -1 }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.print_timestamps = false
        params.suppress_blank = true
        params.no_context = true
        params.n_threads = threadCount

        // The callbacks are C function pointers and cannot capture, so the two closures
        // travel through `user_data` in a box that outlives the call.
        let callbacks = CallbackBox(shouldAbort: shouldAbort, onProgress: onProgress)
        let user = Unmanaged.passUnretained(callbacks).toOpaque()

        params.new_segment_callback_user_data = user
        params.new_segment_callback = { context, _, _, userData in
            guard let context, let userData else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(userData).takeUnretainedValue()
            box.onProgress(WhisperContext.readSegments(from: context))
        }
        params.abort_callback_user_data = user
        params.abort_callback = { userData in
            guard let userData else { return false }
            return Unmanaged<CallbackBox>.fromOpaque(userData).takeUnretainedValue().shouldAbort()
        }

        // The language string must outlive the call; strdup and free bracket it.
        let cLanguage: UnsafeMutablePointer<CChar>? = language.map { strdup($0) } ?? nil
        defer { free(cLanguage) }
        params.language = cLanguage.map { UnsafePointer($0) }

        let result = samples.withUnsafeBufferPointer { buffer in
            whisper_full(pointer, params, buffer.baseAddress, Int32(buffer.count))
        }

        // Keeps the box alive past the last callback — `passUnretained` above means
        // nothing else does.
        withExtendedLifetime(callbacks) {}
        return result
    }

    /// Everything recognised by the most recent ``run(samples:language:threadCount:shouldAbort:onProgress:)``.
    public var segments: [WhisperSegment] {
        guard let pointer else { return [] }
        return Self.readSegments(from: pointer)
    }

    private static func readSegments(from context: OpaquePointer) -> [WhisperSegment] {
        let count = whisper_full_n_segments(context)
        guard count > 0 else { return [] }

        var segments: [WhisperSegment] = []
        segments.reserveCapacity(Int(count))
        for index in 0..<count {
            guard let cText = whisper_full_get_segment_text(context, index) else { continue }
            segments.append(WhisperSegment(
                text: String(cString: cText),
                // whisper reports timestamps in 10 ms ticks.
                startSeconds: TimeInterval(whisper_full_get_segment_t0(context, index)) / 100,
                endSeconds: TimeInterval(whisper_full_get_segment_t1(context, index)) / 100,
                noSpeechProbability: whisper_full_get_segment_no_speech_prob(context, index)
            ))
        }
        return segments
    }

    /// Carries the two closures into whisper's C callbacks.
    private final class CallbackBox: @unchecked Sendable {
        let shouldAbort: @Sendable () -> Bool
        let onProgress: @Sendable ([WhisperSegment]) -> Void

        init(
            shouldAbort: @escaping @Sendable () -> Bool,
            onProgress: @escaping @Sendable ([WhisperSegment]) -> Void
        ) {
            self.shouldAbort = shouldAbort
            self.onProgress = onProgress
        }
    }
}
