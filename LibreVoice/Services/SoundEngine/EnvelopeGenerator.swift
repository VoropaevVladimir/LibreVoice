//
//  EnvelopeGenerator.swift
//  LibreVoice
//

import Foundation

/// The volume shape of a sound over its lifetime.
///
/// An attack–decay envelope rather than full ADSR: every sound here is a brief gesture
/// with no held portion, so sustain and release would be parameters that are always the
/// same. Two numbers that matter beat four that do not.
///
/// The envelope is what makes a tone a *sound* rather than a beep. A tone that begins
/// and ends abruptly clicks — the discontinuity is broadband energy the ear hears as a
/// tick — so nothing here is allowed a zero-length attack or decay.
nonisolated struct EnvelopeGenerator: Sendable {
    /// How long the sound takes to reach full volume.
    let attack: TimeInterval

    /// How long it takes to fall silent afterwards.
    let decay: TimeInterval

    /// Shape of the decay. Above 1 falls away quickly then trails; below 1 lingers.
    ///
    /// 2.2 by default, which approximates how a struck glass loses energy: most of it
    /// immediately, the last of it slowly.
    let curve: Double

    init(attack: TimeInterval, decay: TimeInterval, curve: Double = 2.2) {
        self.attack = max(0.001, attack)
        self.decay = max(0.001, decay)
        self.curve = max(0.1, curve)
    }

    /// Total length of the sound.
    var duration: TimeInterval { attack + decay }

    /// The gain at `time` seconds from the start, in `0...1`.
    func amplitude(at time: TimeInterval) -> Float {
        guard time > 0 else { return 0 }
        guard time < duration else { return 0 }

        if time < attack {
            // Eased rather than linear, so the onset swells instead of ramping.
            let progress = time / attack
            return Float(progress * progress * (3 - 2 * progress))
        }

        let progress = (time - attack) / decay
        return Float(pow(1 - progress, curve))
    }
}
