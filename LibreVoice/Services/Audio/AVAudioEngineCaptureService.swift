//
//  AVAudioEngineCaptureService.swift
//  LibreVoice
//

import AVFoundation
import Foundation

/// Captures microphone audio with `AVAudioEngine` and delivers it as
/// ``AudioChunk`` values in ``AudioFormat/speech``.
///
/// The interesting part is the format conversion. The microphone hands over whatever it
/// likes — 44.1 or 48 kHz, often stereo — while every speech model wants 16 kHz mono.
/// Converting once, here, means no engine ever has to, and no engine can get it subtly
/// wrong in its own way.
///
/// An `actor` because it owns mutable engine state that is reached from the dictation
/// coordinator, and taps deliver buffers from a real-time thread.
actor AVAudioEngineCaptureService: AudioCaptureService {
    nonisolated let format = AudioFormat.speech

    private let engine = AVAudioEngine()
    private let logger: any Logger

    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var capturing = false

    /// How many frames each tap callback asks for. 4096 at 48 kHz is ~85 ms — small
    /// enough that the level meter feels live, large enough not to thrash the CPU.
    private let tapBufferSize: AVAudioFrameCount = 4096

    init(logger: any Logger = NullLogger()) {
        self.logger = logger
    }

    var isCapturing: Bool { capturing }

    // MARK: - Devices

    func availableInputDevices() async -> [AudioInputDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let defaultID = AVCaptureDevice.default(for: .audio)?.uniqueID

        return session.devices.map { device in
            AudioInputDevice(
                id: device.uniqueID,
                name: device.localizedName,
                isDefault: device.uniqueID == defaultID
            )
        }
    }

    // MARK: - Capture

    func start(deviceID: String?) async throws -> AsyncStream<AudioChunk> {
        guard !capturing else { throw AudioCaptureError.alreadyCapturing }

        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioCaptureError.microphonePermissionDenied
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // A sample rate of zero means the HAL has no usable input — an unplugged
        // interface, or an input the system has disabled. Installing a tap on it
        // raises an Objective-C exception, which Swift cannot catch, so this guard is
        // load-bearing rather than defensive.
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioCaptureError.noInputDeviceAvailable
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: AVAudioChannelCount(format.channelCount),
            interleaved: false
        ) else {
            throw AudioCaptureError.engineFailedToStart(reason: "Unsupported target format.")
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.engineFailedToStart(
                reason: "Can't convert \(Int(inputFormat.sampleRate)) Hz to \(Int(format.sampleRate)) Hz."
            )
        }

        let stream = AsyncStream<AudioChunk>(bufferingPolicy: .bufferingNewest(64)) { continuation in
            self.continuation = continuation
        }

        let state = TapState(converter: converter, targetFormat: targetFormat, format: format)
        let continuation = self.continuation

        inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: inputFormat) { buffer, _ in
            guard let chunk = state.makeChunk(from: buffer) else { return }
            continuation?.yield(chunk)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            self.continuation = nil
            throw AudioCaptureError.engineFailedToStart(reason: error.localizedDescription)
        }

        capturing = true
        logger.info(
            "Capturing at \(Int(inputFormat.sampleRate)) Hz × \(inputFormat.channelCount), converting to \(Int(format.sampleRate)) Hz mono.",
            category: .audio
        )

        if deviceID != nil {
            // Choosing a non-default input means setting the AUHAL's current device,
            // which needs a CoreAudio device ID rather than the AVFoundation unique ID.
            // Until that translation is wired up, capture follows the system default —
            // and says so, rather than silently ignoring the setting.
            logger.warning(
                "A specific input device was requested, but device selection isn't implemented yet; using the system default.",
                category: .audio
            )
        }

        return stream
    }

    func stop() async {
        guard capturing else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        capturing = false

        logger.info("Capture stopped.", category: .audio)
    }
}

/// The per-session state a tap block needs, and the conversion itself.
///
/// `AVAudioEngine` calls a tap block serially on one real-time thread, so nothing here
/// is ever touched concurrently. The compiler cannot know that — `AVAudioConverter` is
/// not `Sendable` and the frame counter is mutable — hence `@unchecked Sendable`, with
/// that invariant as the justification.
private nonisolated final class TapState: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let targetFormat: AVAudioFormat
    private let format: AudioFormat

    /// Frames emitted so far, which is what makes chunk timestamps relative to the
    /// start of the session rather than to the wall clock.
    private var framesEmitted: AVAudioFramePosition = 0

    /// The buffer waiting to be handed to the converter.
    ///
    /// Held as a property rather than captured by the converter's input block, because
    /// that block is typed `@Sendable` even though `AVAudioConverter` calls it inline,
    /// before `convert` returns. Keeping the buffer here satisfies the annotation
    /// without pretending a captured `var` is safe to mutate concurrently.
    private var pendingInput: AVAudioPCMBuffer?

    init(converter: AVAudioConverter, targetFormat: AVAudioFormat, format: AudioFormat) {
        self.converter = converter
        self.targetFormat = targetFormat
        self.format = format
    }

    /// Converts one captured buffer into a chunk, or `nil` if it yielded no audio.
    func makeChunk(from buffer: AVAudioPCMBuffer) -> AudioChunk? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        // The converter pulls input, so the block hands over the buffer once and then
        // reports that it is out of data; returning it twice would duplicate audio.
        pendingInput = buffer
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { [self] _, outStatus in
            guard let input = pendingInput else {
                outStatus.pointee = .noDataNow
                return nil
            }
            pendingInput = nil
            outStatus.pointee = .haveData
            return input
        }
        pendingInput = nil

        guard status != .error, output.frameLength > 0 else { return nil }
        guard let channel = output.floatChannelData?[0] else { return nil }

        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        let startTime = Double(framesEmitted) / format.sampleRate
        framesEmitted += AVAudioFramePosition(output.frameLength)

        return AudioChunk(samples: samples, format: format, startTime: startTime)
    }
}
