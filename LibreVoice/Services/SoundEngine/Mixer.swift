//
//  Mixer.swift
//  LibreVoice
//

import Foundation

/// Sums voices into one signal and keeps the result inside the rails.
///
/// The clipping guard is not defensive padding: two quiet sounds that overlap — the
/// breath running into the start motif — can exceed full scale together even though
/// neither does alone, and digital clipping is a harsh crackle that would undo every
/// other decision about calmness in one instant.
nonisolated struct Mixer {
    /// Combines samples, attenuating gracefully rather than clipping.
    static func mix(_ samples: [Float]) -> Float {
        let sum = samples.reduce(0, +)
        return softClip(sum)
    }

    /// Adds `signal` at `gain` into `buffer` starting at `offset`, in place.
    ///
    /// Out-of-range writes are skipped rather than trapping: a sound scheduled slightly
    /// past the end of a buffer should be quietly truncated, not crash the app.
    static func add(_ signal: [Float], to buffer: inout [Float], at offset: Int, gain: Float = 1) {
        guard offset < buffer.count else { return }
        let count = min(signal.count, buffer.count - offset)
        for index in 0..<count {
            buffer[offset + index] = softClip(buffer[offset + index] + signal[index] * gain)
        }
    }

    /// Compresses peaks smoothly instead of cutting them flat.
    ///
    /// `tanh` is the standard choice: it is linear where it matters — every sound here
    /// lives well below full scale, so it passes through untouched — and only bends as
    /// it approaches the rails.
    static func softClip(_ sample: Float) -> Float {
        tanh(sample)
    }
}
