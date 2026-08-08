//
//  EnergyVoiceGateTests.swift
//  LibreVoiceTests
//

import Foundation
import Testing
@testable import LibreVoice

@Suite("Voice activity gate")
struct EnergyVoiceGateTests {
    private let gate = EnergyVoiceGate()
    private let sampleRate = 16_000.0

    /// Synthesised "speech": a 220 Hz tone at a given amplitude.
    private func tone(seconds: TimeInterval, amplitude: Float) -> [Float] {
        let count = Int(seconds * sampleRate)
        return (0..<count).map { amplitude * sin(Float($0) * 2 * .pi * 220 / Float(sampleRate)) }
    }

    private func silence(seconds: TimeInterval, noise: Float = 0.0005) -> [Float] {
        let count = Int(seconds * sampleRate)
        var generator = SystemRandomNumberGenerator()
        return (0..<count).map { _ in Float.random(in: -noise...noise, using: &generator) }
    }

    @Test("Pure silence contains no speech")
    func pureSilence() {
        let gated = gate.gate(silence(seconds: 10), sampleRate: sampleRate)
        #expect(!gated.containsSpeech)
        #expect(gated.samples.isEmpty)
    }

    @Test("Pure speech passes through nearly whole")
    func pureSpeech() {
        let input = tone(seconds: 3, amplitude: 0.3)
        let gated = gate.gate(input, sampleRate: sampleRate)
        #expect(gated.containsSpeech)
        #expect(gated.speechDuration > 2.5)
        #expect(gated.samples.count > input.count * 9 / 10)
    }

    @Test("A sentence inside a long quiet recording is kept; the silence is not")
    func speechIslandSurvives() {
        // The live failure mode: a minute of room tone around 4 seconds of speech.
        let input = silence(seconds: 30) + tone(seconds: 4, amplitude: 0.3) + silence(seconds: 30)
        let gated = gate.gate(input, sampleRate: sampleRate)

        #expect(gated.containsSpeech)
        #expect(abs(gated.speechDuration - 4) < 0.5)
        // Speech plus padding plus at most one compressed pause — far less than input.
        let keptSeconds = TimeInterval(gated.samples.count) / sampleRate
        #expect(keptSeconds < 7, "kept \(keptSeconds)s of a 64s recording")
    }

    @Test("A pause between sentences is compressed, not removed")
    func pauseIsCompressed() {
        let input = tone(seconds: 2, amplitude: 0.3) + silence(seconds: 5) + tone(seconds: 2, amplitude: 0.3)
        let gated = gate.gate(input, sampleRate: sampleRate)

        let keptSeconds = TimeInterval(gated.samples.count) / sampleRate
        // Two sentences with padding plus a ~0.5 s compressed pause.
        #expect(keptSeconds > 4, "the pause must not vanish entirely")
        #expect(keptSeconds < 6.5, "the 5 s pause must not survive whole")
    }

    @Test("Quiet speech over a noisy floor still passes the adaptive threshold")
    func adaptiveThreshold() {
        let noisy = silence(seconds: 6, noise: 0.002) + tone(seconds: 2, amplitude: 0.05) + silence(seconds: 6, noise: 0.002)
        let gated = gate.gate(noisy, sampleRate: sampleRate)
        #expect(gated.containsSpeech)
    }
}
