//
//  AudioChunk.swift
//  LibreVoice
//

import Foundation

/// A contiguous window of captured microphone samples.
///
/// This is the unit that flows from ``AudioCaptureService`` to a
/// ``SpeechRecognitionEngine``. It is a plain `Sendable` value type rather than an
/// `AVAudioPCMBuffer` on purpose: `Core` must not depend on AVFoundation, engines
/// should not have to either, and a value type crosses isolation boundaries without
/// the aliasing hazards of a reference-typed buffer.
nonisolated struct AudioChunk: Sendable, Equatable {
    /// Linear PCM samples, nominally in `-1...1`.
    let samples: [Float]

    /// The format `samples` are in.
    let format: AudioFormat

    /// Seconds since capture started, for the first sample in this chunk.
    ///
    /// Relative to the session rather than the wall clock, so transcript timings stay
    /// meaningful and no timestamp identifies when a person was at their Mac.
    let startTime: TimeInterval

    init(samples: [Float], format: AudioFormat, startTime: TimeInterval) {
        self.samples = samples
        self.format = format
        self.startTime = startTime
    }

    /// How much audio this chunk represents.
    var duration: TimeInterval {
        guard format.sampleRate > 0, format.channelCount > 0 else { return 0 }
        return Double(samples.count) / (format.sampleRate * Double(format.channelCount))
    }

    /// The loudness of this chunk.
    ///
    /// Computed here, next to the samples, so the UI can show a meter without ever
    /// touching raw audio — the view layer only sees an ``AudioLevel``.
    var level: AudioLevel {
        guard !samples.isEmpty else { return .silent }

        var peak: Float = 0
        var sumOfSquares: Float = 0
        for sample in samples {
            let magnitude = abs(sample)
            if magnitude > peak { peak = magnitude }
            sumOfSquares += sample * sample
        }

        return AudioLevel(peak: peak, rms: (sumOfSquares / Float(samples.count)).squareRoot())
    }
}
