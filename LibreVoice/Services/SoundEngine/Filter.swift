//
//  Filter.swift
//  LibreVoice
//

import Foundation

/// A one-pole low-pass filter.
///
/// This is the single most important component in the whole engine, because it is what
/// turns noise into *air*. Raw white noise is a hiss — abrasive, and unmistakably
/// synthetic. Rolling its high end off leaves a soft movement of air, which is exactly
/// what the breath effect has to be and what the thinking texture is built from.
///
/// One pole, not a biquad: a gentle 6 dB/octave slope is what sounds natural here. A
/// steeper filter would be more "correct" and would sound like a filter — the resonance
/// and abrupt cutoff draw attention to themselves, and nothing in this app should.
nonisolated struct Filter {
    private var coefficient: Double
    private var state: Float = 0

    /// - Parameters:
    ///   - cutoff: The −3 dB point in hertz.
    ///   - sampleRate: Frames per second.
    init(cutoff: Double, sampleRate: Double) {
        coefficient = Self.coefficient(cutoff: cutoff, sampleRate: sampleRate)
    }

    /// Moves the cutoff mid-sound, for textures that open and close as they evolve.
    mutating func setCutoff(_ cutoff: Double, sampleRate: Double) {
        coefficient = Self.coefficient(cutoff: cutoff, sampleRate: sampleRate)
    }

    /// Filters one sample.
    mutating func process(_ input: Float) -> Float {
        state += Float(coefficient) * (input - state)
        return state
    }

    private static func coefficient(cutoff: Double, sampleRate: Double) -> Double {
        guard sampleRate > 0 else { return 1 }
        // Standard one-pole smoothing factor. Clamped below Nyquist so an over-eager
        // cutoff cannot make the filter unstable.
        let safeCutoff = min(max(cutoff, 1), sampleRate / 2 - 1)
        return 1 - exp(-2 * .pi * safeCutoff / sampleRate)
    }
}

/// A one-pole high-pass, built from the low-pass by subtraction.
///
/// Used to keep rumble out of the breath: everything below a couple of hundred hertz is
/// energy the user feels rather than hears, and on a laptop speaker it is just a thud.
nonisolated struct HighPassFilter {
    private var lowPass: Filter

    init(cutoff: Double, sampleRate: Double) {
        lowPass = Filter(cutoff: cutoff, sampleRate: sampleRate)
    }

    mutating func process(_ input: Float) -> Float {
        input - lowPass.process(input)
    }
}
