//
//  AudioSynthesizer.swift
//  LibreVoice
//

import Foundation

/// Renders LibreVoice's sounds from nothing but arithmetic.
///
/// No files ship with the app and none are downloaded: every sound is computed when it
/// is asked for. That is partly principle — an app that promises to keep to itself
/// should not need megabytes of assets to say "listening" — and partly practical, since
/// a theme becomes three multiplications rather than fifteen more recordings.
///
/// The house style, applied to all of them:
///
/// - **Nothing starts or stops instantly.** Every tone is enveloped; a hard edge is a
///   click, and a click is the opposite of calm.
/// - **Noise is always filtered.** Unfiltered noise is a hiss and sounds like a fault.
/// - **Everything is quiet.** These sounds accompany speech; they are not events in
///   their own right. If the user consciously notices one, it is too loud.
nonisolated struct AudioSynthesizer {
    let sampleRate: Double

    init(sampleRate: Double = 48_000) {
        self.sampleRate = sampleRate
    }

    // MARK: - The audio logo

    /// The full gesture for a sound, breath included.
    func render(_ sound: DictationSound, theme: SoundTheme) -> [Float] {
        switch sound {
        case .recordingStarted:
            openingChime(theme: theme)
        case .recordingStopped:
            twoNote(from: 900, to: 560, theme: theme, breath: .exhale, duration: 0.110)
        case .completed:
            crystal(theme: theme)
        case .failed:
            lowTone(theme: theme)
        }
    }

    /// Which way the air moves around a motif.
    private enum Breath {
        case inhale
        case exhale
    }

    /// A single tone gliding between two pitches, wrapped in moving air.
    ///
    /// One voice that *bends*, rather than two notes played in sequence. A sequence at
    /// this length (under a tenth of a second) would be heard as a stumble; a glide is
    /// heard as a single intentional gesture.
    private func twoNote(
        from startHz: Double,
        to endHz: Double,
        theme: SoundTheme,
        breath: Breath,
        duration: TimeInterval
    ) -> [Float] {
        let length = duration * theme.length
        let envelope = EnvelopeGenerator(attack: length * 0.18, decay: length * 0.82, curve: 2.0)
        let frameCount = Int(length * sampleRate)

        var tone = Oscillator(.sine)
        // A quiet triangle an octave up gives the tone its glassy edge without making
        // it shrill; on its own the sine is a little dull.
        var sheen = Oscillator(.triangle)
        var samples = [Float](repeating: 0, count: frameCount)

        for frame in 0..<frameCount {
            let time = Double(frame) / sampleRate
            let progress = time / length
            // Eased glide: the pitch moves most in the middle, so the ends settle.
            let eased = progress * progress * (3 - 2 * progress)
            let frequency = (startHz + (endHz - startHz) * eased) * theme.pitch

            let gain = envelope.amplitude(at: time)
            let core = tone.next(frequency: frequency, sampleRate: sampleRate)
            let edge = sheen.next(frequency: frequency * 2, sampleRate: sampleRate) * 0.12

            samples[frame] = (core + edge) * gain * theme.level
        }

        let air = self.breath(breath, theme: theme)
        // The breath leads the tone slightly on the way in and trails it on the way
        // out — air moving *before* a sound and *after* it, which is what makes the
        // capsule feel like it wakes up rather than switches on.
        var mixed = [Float](repeating: 0, count: max(frameCount, air.count))
        switch breath {
        case .inhale:
            Mixer.add(air, to: &mixed, at: 0)
            Mixer.add(samples, to: &mixed, at: 0)
        case .exhale:
            Mixer.add(samples, to: &mixed, at: 0)
            Mixer.add(air, to: &mixed, at: max(0, frameCount - air.count))
        }
        return mixed
    }

    /// A movement of air: filtered noise, 20–35 ms, very quiet.
    ///
    /// Explicitly not a human breath. The band is chosen to avoid that: real breathing
    /// has energy down in the low hundreds of hertz which is what makes it recognisably
    /// a person, so this is high-passed well above it. What is left reads as air moving
    /// past something, not through someone.
    private func breath(_ direction: Breath, theme: SoundTheme) -> [Float] {
        let length = 0.028 * theme.length
        let frameCount = Int(length * sampleRate)
        guard frameCount > 0 else { return [] }

        var noise = Oscillator(.noise, seed: direction == .inhale ? 0x9E3779B97F4A7C15 : 0xBF58476D1CE4E5B9)
        var lowPass = Filter(cutoff: 2_400, sampleRate: sampleRate)
        var highPass = HighPassFilter(cutoff: 700, sampleRate: sampleRate)
        var samples = [Float](repeating: 0, count: frameCount)

        for frame in 0..<frameCount {
            let progress = Double(frame) / Double(frameCount)
            // Inhale swells, exhale recedes: the shape carries the direction, which is
            // why the same noise reads as two different gestures.
            let shape = direction == .inhale ? progress : 1 - progress
            // Soft at both ends regardless, so the burst never begins or ends on an edge.
            let window = sin(progress * .pi)
            let gain = Float(shape * window)

            let raw = noise.next(frequency: 0, sampleRate: sampleRate)
            samples[frame] = lowPass.process(highPass.process(raw)) * gain * theme.level * theme.air * 0.55
        }
        return samples
    }

    // MARK: - The shorter gestures

    /// Recording has begun: a soft, pure-toned rise — the gentlest sound in the app.
    ///
    /// It is built like the completion chime on purpose: two consonant sine partials
    /// under one smooth envelope, and crucially *no* filtered-noise breath and *no*
    /// triangle overtone. Those two ingredients are what gave the earlier opening its
    /// airy, piercing edge — and an edge is the last thing a sound that arrives unbidden
    /// the instant you start speaking should have. What sets it apart from completion is
    /// direction and register: this one rises, sits lower, and lasts a little longer, so
    /// the start and the end still read as two different events rather than one repeated.
    private func openingChime(theme: SoundTheme) -> [Float] {
        let length = 0.105 * theme.length
        let attack = length * 0.45 // long, so the onset swells in rather than taps
        let envelope = EnvelopeGenerator(attack: attack, decay: length - attack, curve: 2.4)
        let frameCount = Int(length * sampleRate)

        var fundamental = Oscillator(.sine)
        var partial = Oscillator(.sine)
        var samples = [Float](repeating: 0, count: frameCount)

        for frame in 0..<frameCount {
            let time = Double(frame) / sampleRate
            let progress = time / length
            let eased = progress * progress * (3 - 2 * progress)
            // A gentle rise of about a major third, low in the register.
            let root = (440 + 110 * eased) * theme.pitch
            let gain = envelope.amplitude(at: time)
            let a = fundamental.next(frequency: root, sampleRate: sampleRate)
            // An octave above, quiet — pure reinforcement that gives the tone a little
            // body without adding a second pitch the ear has to place.
            let b = partial.next(frequency: root * 2, sampleRate: sampleRate) * 0.3
            samples[frame] = (a + b) * gain * theme.level * 0.7
        }
        return samples
    }

    /// Completion: a small, clean confirmation. 40–60 ms, two soft partials.
    private func crystal(theme: SoundTheme) -> [Float] {
        let length = 0.050 * theme.length
        let envelope = EnvelopeGenerator(attack: length * 0.10, decay: length * 0.90, curve: 2.6)
        let frameCount = Int(length * sampleRate)

        var fundamental = Oscillator(.sine)
        var partial = Oscillator(.sine)
        var samples = [Float](repeating: 0, count: frameCount)

        for frame in 0..<frameCount {
            let time = Double(frame) / sampleRate
            let gain = envelope.amplitude(at: time)
            // A perfect fifth above, quietly. Consonant intervals sound resolved, which
            // is the whole message: the work finished, nothing needs attention.
            let a = fundamental.next(frequency: 1_050 * theme.pitch, sampleRate: sampleRate)
            let b = partial.next(frequency: 1_575 * theme.pitch, sampleRate: sampleRate) * 0.35
            samples[frame] = (a + b) * gain * theme.level * 0.75
        }
        return samples
    }

    /// Failure: low, soft and brief. Never a buzzer.
    ///
    /// A minor third *down* — the smallest interval that is unmistakably not a success
    /// sound, without the alarm of a dissonance. It stays below 300 Hz, where the ear
    /// hears "something settled" rather than "something is wrong with you".
    private func lowTone(theme: SoundTheme) -> [Float] {
        let length = 0.150 * theme.length
        let envelope = EnvelopeGenerator(attack: length * 0.14, decay: length * 0.86, curve: 1.8)
        let frameCount = Int(length * sampleRate)

        var tone = Oscillator(.sine)
        var samples = [Float](repeating: 0, count: frameCount)

        for frame in 0..<frameCount {
            let time = Double(frame) / sampleRate
            let progress = time / length
            let frequency = (280 - 45 * progress) * theme.pitch
            samples[frame] = tone.next(frequency: frequency, sampleRate: sampleRate)
                * envelope.amplitude(at: time) * theme.level * 0.8
        }
        return samples
    }
}
