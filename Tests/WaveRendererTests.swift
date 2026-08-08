//
//  WaveRendererTests.swift
//  LibreVoiceTests
//

import Foundation
import Testing
@testable import LibreVoice

/// The wave's response curve is what makes speaking *look* like speaking, so it is
/// pinned here rather than left to be judged by eye. Every expectation below is about
/// one thing: does the picture change enough between quiet and loud to be read as a
/// voice rather than as a busy ribbon?
@Suite("Wave response")
struct WaveRendererTests {
    /// Runs the envelope to a steady state at `rawLevel`, as a held sound would.
    private func settled(at rawLevel: Float, seconds: Float = 1.0) -> WaveRenderer {
        var renderer = WaveRenderer()
        let dt: Float = 1.0 / 120
        for _ in 0..<Int(seconds / dt) {
            renderer.advance(rawLevel: rawLevel, dt: dt)
        }
        return renderer
    }

    @Test("Silence leaves the wave at rest")
    func silenceIsStill() {
        // Room tone sits below the noise floor and must not animate the wave: an idle
        // capsule that keeps rippling reads as "still listening" when it is not.
        #expect(settled(at: 0).level < 0.01)
        #expect(settled(at: 0.003).level < 0.05)
    }

    @Test("Ordinary speech uses most of the range")
    func speechIsExpressive() {
        // The bug this replaces: RMS 0.02–0.15 mapped linearly by 3.2 gave 0.06–0.48,
        // so normal talking never rose past half and the wave looked the same however
        // loudly it was spoken to.
        let quiet = settled(at: 0.02).level
        let normal = settled(at: 0.08).level
        let loud = settled(at: 0.20).level

        #expect(quiet > 0.15, "quiet speech must still be visible, got \(quiet)")
        #expect(normal > 0.55, "normal speech should use most of the range, got \(normal)")
        #expect(loud > 0.95, "loud speech should reach the top, got \(loud)")
    }

    @Test("The gap between quiet and loud speech is large enough to see")
    func dynamicRangeIsWide() {
        let quiet = settled(at: 0.02).level
        let loud = settled(at: 0.20).level
        #expect(loud - quiet > 0.5, "only \(loud - quiet) separates a whisper from a shout")
    }

    @Test("The response is monotonic — louder never looks quieter")
    func responseIsMonotonic() {
        let samples: [Float] = [0, 0.01, 0.02, 0.05, 0.08, 0.12, 0.2, 0.4]
        let levels = samples.map { settled(at: $0).level }
        for (previous, next) in zip(levels, levels.dropFirst()) {
            #expect(next >= previous, "response dipped: \(levels)")
        }
    }

    @Test("A syllable's onset is caught quickly")
    func attackIsFast() {
        var renderer = WaveRenderer()
        let dt: Float = 1.0 / 120
        // 80 ms of sound — about the length of a vowel onset.
        for _ in 0..<10 { renderer.advance(rawLevel: 0.12, dt: dt) }
        #expect(renderer.level > 0.5, "attack too slow: \(renderer.level)")
    }

    @Test("The wave falls away after speech rather than snapping flat")
    func releaseIsGraceful() {
        var renderer = settled(at: 0.15)
        let peak = renderer.level
        let dt: Float = 1.0 / 120

        // One frame of silence must barely move it…
        renderer.advance(rawLevel: 0, dt: dt)
        #expect(renderer.level > peak * 0.9, "release is snapping, not falling")

        // …but half a second of silence should bring it most of the way down.
        for _ in 0..<60 { renderer.advance(rawLevel: 0, dt: dt) }
        #expect(renderer.level < peak * 0.3, "wave is still up at \(renderer.level)")
    }

    @Test("Level never leaves 0...1, whatever arrives")
    func levelStaysInRange() {
        // The shader trusts this range; a value above 1 would drive the crest past the
        // capsule edge, and a negative one would invert the wave.
        for raw in [Float(0), 0.5, 1, 5, -1] {
            let renderer = settled(at: raw)
            #expect(renderer.level >= 0 && renderer.level <= 1, "level \(renderer.level) for raw \(raw)")
            #expect(renderer.energy >= 0 && renderer.energy <= 1)
        }
    }

    @Test("Energy trails the level rather than tracking it instantly")
    func energyIsSlower() {
        var renderer = WaveRenderer()
        let dt: Float = 1.0 / 120
        for _ in 0..<12 { renderer.advance(rawLevel: 0.15, dt: dt) }
        #expect(renderer.energy < renderer.level, "energy should lag behind level")
    }
}
