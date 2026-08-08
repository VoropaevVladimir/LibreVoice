//
//  AudioLevel.swift
//  LibreVoice
//

import Foundation

/// A normalised loudness measurement, used to drive the microphone meter.
nonisolated struct AudioLevel: Sendable, Equatable {
    /// The loudest sample in the window, in `0...1`.
    let peak: Float

    /// The root-mean-square average of the window, in `0...1`.
    ///
    /// RMS tracks perceived loudness far better than peak, so this is what the meter
    /// should animate; `peak` is for clipping indication.
    let rms: Float

    init(peak: Float, rms: Float) {
        self.peak = peak.clamped(to: 0...1)
        self.rms = rms.clamped(to: 0...1)
    }

    /// Silence.
    static let silent = AudioLevel(peak: 0, rms: 0)

    /// Whether the input is loud enough that it is probably clipping.
    var isClipping: Bool { peak >= 0.99 }
}

private nonisolated extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
