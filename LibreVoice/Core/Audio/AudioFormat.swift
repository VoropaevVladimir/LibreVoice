//
//  AudioFormat.swift
//  LibreVoice
//

import Foundation

/// The shape of a stream of linear PCM samples.
nonisolated struct AudioFormat: Sendable, Equatable, Hashable {
    /// Samples per second, per channel.
    let sampleRate: Double

    /// The number of interleaved channels.
    let channelCount: Int

    init(sampleRate: Double, channelCount: Int) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    /// 16 kHz mono — what speech models expect.
    ///
    /// Whisper and its derivatives are all trained at this rate, and Apple's
    /// `SFSpeechRecognizer` is happy with it too. Capturing at the format the engines
    /// want means resampling happens once, in the capture service, instead of being
    /// re-implemented by every engine.
    static let speech = AudioFormat(sampleRate: 16_000, channelCount: 1)
}
