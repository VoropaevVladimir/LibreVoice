//
//  Oscillator.swift
//  LibreVoice
//

import Foundation

/// A single tone generator.
///
/// Phase is advanced per sample rather than recomputed from absolute time, which is what
/// lets the frequency glide mid-note without the waveform tearing: a jump in frequency
/// changes how fast the phase moves, never where it currently is. That continuity is the
/// difference between a note that bends and one that clicks.
nonisolated struct Oscillator {
    /// The shape of the tone.
    ///
    /// Only these three: a pure sine is the glassy voice of the audio logo, a triangle
    /// adds a little body without harshness, and noise is the raw material for the
    /// breath and the thinking texture. Sawtooth and square are deliberately absent —
    /// both are buzzy, and nothing in this app should buzz.
    enum Waveform: Sendable {
        case sine
        case triangle
        case noise
    }

    private let waveform: Waveform
    private var phase: Double = 0
    private var noiseState: UInt64

    init(_ waveform: Waveform, seed: UInt64 = 0x2545F4914F6CDD1D) {
        self.waveform = waveform
        // Never zero: the xorshift below is stuck at zero forever if it starts there.
        self.noiseState = seed == 0 ? 0x2545F4914F6CDD1D : seed
    }

    /// Produces the next sample and advances by one frame.
    ///
    /// - Parameters:
    ///   - frequency: Hertz. Ignored for ``Waveform/noise``.
    ///   - sampleRate: Frames per second.
    mutating func next(frequency: Double, sampleRate: Double) -> Float {
        switch waveform {
        case .noise:
            return nextNoise()
        case .sine, .triangle:
            let value = sample(at: phase)
            phase += frequency / sampleRate
            if phase >= 1 { phase -= floor(phase) }
            return value
        }
    }

    private func sample(at phase: Double) -> Float {
        switch waveform {
        case .sine:
            Float(sin(phase * 2 * .pi))
        case .triangle:
            // Rises 0→1 over the first half, falls 1→-1… expressed as a fold so there
            // are no branches per sample.
            Float(4 * abs(phase - floor(phase + 0.75) + 0.25) - 1)
        case .noise:
            0
        }
    }

    /// White noise from an xorshift generator.
    ///
    /// Deterministic on purpose: the same seed gives the same noise every time, so the
    /// breath effect is reproducible and testable rather than subtly different on each
    /// play. `SystemRandomNumberGenerator` would be neither.
    private mutating func nextNoise() -> Float {
        noiseState ^= noiseState << 13
        noiseState ^= noiseState >> 7
        noiseState ^= noiseState << 17
        // Top 24 bits mapped to -1...1; the low bits of xorshift are the weakest.
        let unit = Double(noiseState >> 40) / Double(1 << 24)
        return Float(unit * 2 - 1)
    }
}
