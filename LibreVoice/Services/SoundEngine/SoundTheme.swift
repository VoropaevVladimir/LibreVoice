//
//  SoundTheme.swift
//  LibreVoice
//

import Foundation

/// The character of LibreVoice's sounds.
///
/// Earlier builds tuned pitch, length and air per dictation mode — three subtly
/// different sound sets for what a person experiences as one app. That was a distinction
/// nobody asked to hear, so the identity is now uniform: dictation sounds the same
/// whichever mode is selected. The type survives as the one place those constants live,
/// and as the seam a future per-mode identity would slot back into.
nonisolated struct SoundTheme: Sendable {
    /// Multiplies every frequency. Above 1 is brighter, below 1 is deeper.
    let pitch: Double

    /// Multiplies every duration. Below 1 is snappier, above 1 more relaxed.
    let length: Double

    /// Overall loudness. Everything here is quiet; this decides *how* quiet.
    let level: Float

    /// How much filtered air sits under the tones, `0...1`.
    let air: Float

    /// The single sound identity, shared by every mode. These are the values the default
    /// (Smart) mode always used, so nothing a user was already hearing changes.
    static let standard = SoundTheme(pitch: 1.00, length: 1.00, level: 0.15, air: 0.7)

    /// The theme for a mode — uniform now, so every mode returns ``standard``.
    static func theme(for mode: DictationMode) -> SoundTheme { standard }
}
