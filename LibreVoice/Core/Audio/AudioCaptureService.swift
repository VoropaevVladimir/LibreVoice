//
//  AudioCaptureService.swift
//  LibreVoice
//

import Foundation

/// Captures microphone audio as a stream of ``AudioChunk`` values.
///
/// `start()` returns the stream rather than exposing a long-lived property, which ties
/// the stream's lifetime to one capture session and makes it impossible to hold a
/// stale stream from a previous run.
///
/// Conformances are expected to deliver chunks already converted to
/// ``AudioFormat/speech``, so engines never resample.
nonisolated protocol AudioCaptureService: Sendable {
    /// The format chunks are delivered in.
    var format: AudioFormat { get }

    /// Whether capture is currently running.
    var isCapturing: Bool { get async }

    /// The microphones currently available.
    func availableInputDevices() async -> [AudioInputDevice]

    /// Starts capturing and returns the stream of audio.
    ///
    /// The stream finishes when ``stop()`` is called or the input device disappears.
    ///
    /// - Parameter deviceID: The device to capture from, or `nil` for the system default.
    /// - Throws: ``AudioCaptureError`` if capture cannot start.
    func start(deviceID: String?) async throws -> AsyncStream<AudioChunk>

    /// Stops capturing and finishes the stream returned by ``start(deviceID:)``.
    ///
    /// Safe to call when not capturing.
    func stop() async
}

extension AudioCaptureService {
    /// Starts capturing from the system default input.
    func start() async throws -> AsyncStream<AudioChunk> {
        try await start(deviceID: nil)
    }
}
