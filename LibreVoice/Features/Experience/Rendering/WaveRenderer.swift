//
//  WaveRenderer.swift
//  LibreVoice
//

import Foundation

/// Turns raw microphone levels into the smooth signals the wave shader wants.
///
/// Feeding the raw RMS straight into the shader makes the wave twitch — capture chunks
/// arrive at ~10 Hz while frames render at 120. This applies an asymmetric envelope
/// (fast attack, slow release, like an analogue VU meter) so the wave leaps with the
/// voice and settles gracefully, plus a slow "energy" trace of how animated the speech
/// has been — the shader uses it for shimmer.
nonisolated struct WaveRenderer {
    /// The smoothed instantaneous level, `0...1`.
    private(set) var level: Float = 0

    /// The slow-moving speech energy, `0...1`.
    private(set) var energy: Float = 0

    /// Advances the envelopes by one frame.
    ///
    /// - Parameters:
    ///   - rawLevel: The latest RMS from capture, `0...1`.
    ///   - dt: Seconds since the previous frame.
    mutating func advance(rawLevel: Float, dt: Float) {
        // Speech RMS lives in a narrow band near the bottom of `0...1` — talking into a
        // built-in microphone sits around 0.02–0.15 — so mapping it linearly left the
        // wave hovering at one height whatever was said. Three steps fix that:
        //
        // 1. Subtract a floor, so room tone reads as silence and the line rests.
        // 2. Gain hard, because the useful band is tiny.
        // 3. Expand with a power curve, which lifts quiet speech into view without
        //    letting a loud syllable pin permanently to the ceiling.
        let gated = max(0, rawLevel - Self.noiseFloor)
        let target = pow(min(1, gated * Self.gain), Self.expansion)

        // Attack fast enough to follow a phrase, slow enough that the wave *swells*
        // rather than snapping to each syllable. Tracking every consonant burst is
        // technically more faithful and looks worse: the crest twitches, which reads as
        // nervous. Release is slower still, so the wave settles instead of dropping out
        // in the gaps between words.
        let attack: Float = 14
        let release: Float = 4.5
        let rate = target > level ? attack : release
        level += (target - level) * min(1, rate * dt)

        // Energy trails the level slowly in both directions.
        energy += (level - energy) * min(1, 1.2 * dt)
    }

    /// RMS below this is treated as an empty room rather than speech.
    private static let noiseFloor: Float = 0.004

    /// Maps the usable speech band onto `0...1`.
    private static let gain: Float = 7.0

    /// Below 1, so the quiet end of the range is stretched and the loud end compressed —
    /// roughly how loudness is perceived.
    private static let expansion: Float = 0.55

    /// Resets both envelopes, for the start of a session.
    mutating func reset() {
        level = 0
        energy = 0
    }
}
