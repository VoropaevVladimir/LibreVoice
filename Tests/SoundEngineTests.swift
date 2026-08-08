//
//  SoundEngineTests.swift
//  LibreVoiceTests
//

import Foundation
import Testing
@testable import LibreVoice

/// Sound is usually judged by ear, which makes it exactly the kind of thing that
/// regresses unnoticed. Everything here is synthesised deterministically, so the
/// qualities that matter — quiet, click-free, the right length, the right direction —
/// can be asserted as numbers instead.
@Suite("Oscillator")
struct OscillatorTests {
    private let sampleRate = 48_000.0

    private func render(_ waveform: Oscillator.Waveform, frequency: Double, frames: Int) -> [Float] {
        var oscillator = Oscillator(waveform)
        return (0..<frames).map { _ in oscillator.next(frequency: frequency, sampleRate: sampleRate) }
    }

    // `allSatisfy` and `contains` are `rethrows`, which the `#expect` macro cannot
    // expand inline, so every use is hoisted into a plain `let` first.
    @Test("A sine stays within its rails")
    func sineIsBounded() {
        let samples = render(.sine, frequency: 440, frames: 4_800)
        let inRange = samples.allSatisfy { $0 >= -1.001 && $0 <= 1.001 }
        let reachesPeak = samples.contains { $0 > 0.99 }
        let reachesTrough = samples.contains { $0 < -0.99 }

        #expect(inRange)
        #expect(reachesPeak, "should reach its peak")
        #expect(reachesTrough, "should reach its trough")
    }

    @Test("A sine completes the expected number of cycles")
    func sineFrequencyIsCorrect() {
        // 100 Hz over 1 second must cross zero going upwards 100 times.
        let samples = render(.sine, frequency: 100, frames: Int(sampleRate))
        var risingCrossings = 0
        for index in 1..<samples.count where samples[index - 1] < 0 && samples[index] >= 0 {
            risingCrossings += 1
        }
        #expect(abs(risingCrossings - 100) <= 1, "got \(risingCrossings) cycles")
    }

    @Test("A triangle stays within its rails")
    func triangleIsBounded() {
        let samples = render(.triangle, frequency: 300, frames: 4_800)
        let inRange = samples.allSatisfy { $0 >= -1.001 && $0 <= 1.001 }
        #expect(inRange)
    }

    @Test("Noise is bounded, centred and reproducible")
    func noiseIsWellBehaved() {
        let first = render(.noise, frequency: 0, frames: 20_000)
        let second = render(.noise, frequency: 0, frames: 20_000)

        let inRange = first.allSatisfy { $0 >= -1.001 && $0 <= 1.001 }
        #expect(inRange)
        // A DC offset would be an audible thump when the sound starts.
        let mean = first.reduce(0, +) / Float(first.count)
        #expect(abs(mean) < 0.02, "noise is off-centre by \(mean)")
        // Same seed, same noise: the breath must not be subtly different every time.
        #expect(first == second)
    }
}

@Suite("Envelope")
struct EnvelopeGeneratorTests {
    @Test("Silent before it begins and after it ends")
    func silentOutsideItsSpan() {
        let envelope = EnvelopeGenerator(attack: 0.01, decay: 0.05)
        #expect(envelope.amplitude(at: -0.1) == 0)
        #expect(envelope.amplitude(at: 0) == 0)
        #expect(envelope.amplitude(at: envelope.duration) == 0)
        #expect(envelope.amplitude(at: envelope.duration + 0.1) == 0)
    }

    @Test("Reaches full volume at the end of the attack")
    func peaksAfterAttack() {
        let envelope = EnvelopeGenerator(attack: 0.01, decay: 0.05)
        #expect(abs(envelope.amplitude(at: 0.01) - 1) < 0.01)
    }

    @Test("Both edges are gradual, so nothing clicks")
    func edgesAreGradual() {
        // A click is a discontinuity: a sound that begins or ends at full amplitude.
        // Sampling near each edge proves the envelope approaches zero rather than
        // jumping to it.
        let envelope = EnvelopeGenerator(attack: 0.02, decay: 0.08)
        #expect(envelope.amplitude(at: 0.0005) < 0.02, "onset is too abrupt")
        #expect(envelope.amplitude(at: envelope.duration - 0.0005) < 0.02, "ending is too abrupt")
    }

    @Test("Decay falls monotonically")
    func decayIsMonotonic() {
        let envelope = EnvelopeGenerator(attack: 0.01, decay: 0.10)
        let samples = stride(from: 0.011, to: 0.109, by: 0.005).map { envelope.amplitude(at: $0) }
        for (previous, next) in zip(samples, samples.dropFirst()) {
            #expect(next <= previous, "decay rose: \(samples)")
        }
    }
}

@Suite("Filter")
struct FilterTests {
    private let sampleRate = 48_000.0

    /// Peak amplitude of a tone after passing through the filter.
    private func response(cutoff: Double, toneHz: Double) -> Float {
        var filter = Filter(cutoff: cutoff, sampleRate: sampleRate)
        var oscillator = Oscillator(.sine)
        var peak: Float = 0
        // Long enough to settle past the filter's own start-up transient.
        for _ in 0..<Int(sampleRate * 0.2) {
            let output = filter.process(oscillator.next(frequency: toneHz, sampleRate: sampleRate))
            peak = max(peak, abs(output))
        }
        return peak
    }

    @Test("A low-pass passes lows and attenuates highs")
    func lowPassAttenuatesHighs() {
        let low = response(cutoff: 1_000, toneHz: 100)
        let high = response(cutoff: 1_000, toneHz: 10_000)
        #expect(low > 0.9, "a tone well below cutoff should pass, got \(low)")
        #expect(high < 0.2, "a tone well above cutoff should be cut, got \(high)")
    }

    @Test("A high-pass does the opposite")
    func highPassAttenuatesLows() {
        var filter = HighPassFilter(cutoff: 1_000, sampleRate: sampleRate)
        var oscillator = Oscillator(.sine)
        var peak: Float = 0
        for _ in 0..<Int(sampleRate * 0.2) {
            peak = max(peak, abs(filter.process(oscillator.next(frequency: 60, sampleRate: sampleRate))))
        }
        #expect(peak < 0.2, "60 Hz should be well below a 1 kHz high-pass, got \(peak)")
    }

    @Test("An extreme cutoff cannot destabilise the filter")
    func extremeCutoffIsSafe() {
        // Above Nyquist, and below zero: both are clamped rather than producing NaN or
        // a runaway state, which would be a burst of noise at full volume.
        for cutoff in [0.0, -100.0, sampleRate, sampleRate * 4] {
            var filter = Filter(cutoff: cutoff, sampleRate: sampleRate)
            var oscillator = Oscillator(.sine)
            var peak: Float = 0
            for _ in 0..<2_000 {
                peak = max(peak, abs(filter.process(oscillator.next(frequency: 440, sampleRate: sampleRate))))
            }
            #expect(peak.isFinite && peak <= 1.001, "cutoff \(cutoff) produced \(peak)")
        }
    }
}

@Suite("Mixer")
struct MixerTests {
    @Test("Overlapping sounds never clip")
    func neverClips() {
        // Two loud sounds landing together is the realistic case: one motif can still
        // be decaying as the next begins when a user dictates in quick succession.
        #expect(abs(Mixer.mix([0.9, 0.9, 0.9])) <= 1)
        #expect(abs(Mixer.mix([-2, -2])) <= 1)
    }

    @Test("Quiet signals pass through essentially untouched")
    func quietSignalsAreLinear() {
        // Everything in this app lives far below full scale, so the limiter must be
        // transparent there — otherwise it would quietly distort every sound.
        #expect(abs(Mixer.mix([0.1]) - 0.1) < 0.005)
    }

    @Test("Adding past the end of a buffer is truncated, not a crash")
    func outOfRangeAddIsSafe() {
        var buffer = [Float](repeating: 0, count: 4)
        Mixer.add([1, 1, 1, 1], to: &buffer, at: 2)
        Mixer.add([1, 1], to: &buffer, at: 99)
        #expect(buffer.count == 4)
        #expect(buffer[0] == 0 && buffer[1] == 0)
        #expect(buffer[2] > 0 && buffer[3] > 0)
    }
}

@Suite("Audio identity")
struct AudioSynthesizerTests {
    private let sampleRate = 48_000.0
    private var synthesizer: AudioSynthesizer { AudioSynthesizer(sampleRate: sampleRate) }
    private var theme: SoundTheme { SoundTheme.theme(for: .smart) }

    private func duration(of samples: [Float]) -> TimeInterval {
        TimeInterval(samples.count) / sampleRate
    }

    /// Dominant frequency of a slice, by counting rising zero crossings.
    private func pitch(of samples: ArraySlice<Float>) -> Double {
        var crossings = 0
        let values = Array(samples)
        for index in 1..<values.count where values[index - 1] < 0 && values[index] >= 0 {
            crossings += 1
        }
        return Double(crossings) / (Double(values.count) / sampleRate)
    }

    @Test("Every sound renders and is audible")
    func allSoundsRender() {
        for sound in DictationSound.allCases {
            let samples = synthesizer.render(sound, theme: theme)
            let hasSignal = samples.contains { $0 != 0 }
            let allFinite = samples.allSatisfy(\.isFinite)

            #expect(!samples.isEmpty, "\(sound) rendered nothing")
            #expect(hasSignal, "\(sound) is pure silence")
            #expect(allFinite, "\(sound) contains NaN or infinity")
        }
    }

    @Test("Every sound is quiet")
    func everythingIsQuiet() {
        // These accompany speech. Anything approaching full scale would be an
        // interruption rather than an accent.
        for sound in DictationSound.allCases {
            let peak = synthesizer.render(sound, theme: theme).map(abs).max() ?? 0
            #expect(peak < 0.45, "\(sound) peaks at \(peak) — too loud")
        }
    }

    @Test("Nothing begins or ends on an edge")
    func noClicks() {
        // A non-zero first or last sample is a step discontinuity, which the ear hears
        // as a click — the single most common flaw in synthesised UI sounds.
        for sound in DictationSound.allCases {
            let samples = synthesizer.render(sound, theme: theme)
            #expect(abs(samples.first ?? 1) < 0.02, "\(sound) starts on an edge")
            #expect(abs(samples.last ?? 1) < 0.02, "\(sound) ends on an edge")
        }
    }

    @Test("The start motif ascends and the stop motif descends")
    func startRisesAndStopFalls() {
        // Opposite directions are what keep the two halves distinguishable: the opening
        // rises into the session, the close falls out of it. If both ever moved the same
        // way, one would be mistaken for the other.
        let started = synthesizer.render(.recordingStarted, theme: theme)
        let stopped = synthesizer.render(.recordingStopped, theme: theme)

        // Start is pure tone end to end, so compare its halves — wide windows give the
        // gentle rise enough resolution to register.
        let startEarly = pitch(of: started[0..<(started.count / 2)])
        let startLate = pitch(of: started[(started.count / 2)...])
        #expect(startLate > startEarly, "the start motif should rise (\(startEarly) → \(startLate))")

        // Stop trails off into a breath of filtered noise; measuring across it would count
        // the noise as pitch. The first and third quarters are both clear of it.
        let quarter = stopped.count / 4
        let stopEarly = pitch(of: stopped[0..<quarter])
        let stopLate = pitch(of: stopped[(quarter * 2)..<(quarter * 3)])
        #expect(stopLate < stopEarly, "the stop motif should fall (\(stopEarly) → \(stopLate))")
    }

    @Test("Durations match the design")
    func durationsAreAsDesigned() {
        // The brief's numbers, which are what keep these gestures feeling instant.
        #expect((0.070...0.130).contains(duration(of: synthesizer.render(.recordingStarted, theme: theme))))
        #expect((0.090...0.150).contains(duration(of: synthesizer.render(.recordingStopped, theme: theme))))
        #expect((0.035...0.070).contains(duration(of: synthesizer.render(.completed, theme: theme))))
        #expect(duration(of: synthesizer.render(.failed, theme: theme)) < 0.25)
    }

    @Test("The opening chime is the gentlest motif")
    func startIsSofterThanStop() {
        // The start sound arrives unprompted the moment the user speaks, so it must be
        // the least sharp: it tops out at a lower pitch and carries less of the glassy
        // overtone than the stop motif, which the user has asked for by releasing a key.
        let started = synthesizer.render(.recordingStarted, theme: theme)
        let stopped = synthesizer.render(.recordingStopped, theme: theme)

        func peakPitch(_ samples: [Float]) -> Double {
            // The brightest stretch is the sustained tone after the attack.
            pitch(of: samples[(samples.count / 3)..<(samples.count * 2 / 3)])
        }

        #expect(peakPitch(started) < peakPitch(stopped), "the start motif should top out lower")
    }

    @Test("The sound is the same in every mode")
    func soundIsUniformAcrossModes() {
        // The identity used to vary per mode; it no longer does. Whichever mode is
        // selected, a sound renders identically — one app, one voice.
        for sound in DictationSound.allCases {
            let fast = AudioSynthesizer(sampleRate: sampleRate).render(sound, theme: .theme(for: .fast))
            let precision = AudioSynthesizer(sampleRate: sampleRate).render(sound, theme: .theme(for: .precision))
            #expect(fast == precision, "\(sound) differs between modes")
        }
    }
}
