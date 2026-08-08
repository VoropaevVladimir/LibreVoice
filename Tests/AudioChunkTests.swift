//
//  AudioChunkTests.swift
//  LibreVoiceTests
//

import Foundation
import Testing
@testable import LibreVoice

@Suite("AudioChunk")
struct AudioChunkTests {
    private func chunk(_ samples: [Float]) -> AudioChunk {
        AudioChunk(samples: samples, format: .speech, startTime: 0)
    }

    @Test("An empty chunk is silent rather than undefined")
    func emptyChunkIsSilent() {
        #expect(chunk([]).level == .silent, "Dividing by a zero sample count must not produce NaN in the meter.")
    }

    @Test("Peak is the largest magnitude, regardless of sign")
    func peakIgnoresSign() {
        let level = chunk([0.1, -0.8, 0.3]).level

        #expect(abs(level.peak - 0.8) < 0.0001, "A negative sample is just as loud as a positive one.")
    }

    @Test("RMS of a constant signal is its magnitude")
    func rmsOfConstantSignal() {
        let level = chunk([0.5, 0.5, 0.5, 0.5]).level

        #expect(abs(level.rms - 0.5) < 0.0001)
    }

    @Test("Levels are clamped to the meter's range")
    func levelsAreClamped() {
        // Samples outside -1...1 do occur: a hot interface can overshoot.
        let level = chunk([2.0, -3.0]).level

        #expect(level.peak <= 1.0)
        #expect(level.rms <= 1.0)
    }

    @Test("A full-scale signal reports clipping")
    func fullScaleClips() {
        #expect(chunk([1.0, -1.0]).level.isClipping)
        #expect(!chunk([0.5]).level.isClipping)
    }

    @Test("Duration follows from the sample count and rate")
    func durationMatchesSampleCount() {
        // One second of 16 kHz mono.
        let oneSecond = chunk(Array(repeating: 0, count: 16_000))

        #expect(abs(oneSecond.duration - 1.0) < 0.0001)
    }

    @Test("A zero sample rate cannot produce a divide by zero")
    func zeroSampleRateIsSafe() {
        let broken = AudioChunk(
            samples: [0.1],
            format: AudioFormat(sampleRate: 0, channelCount: 0),
            startTime: 0
        )

        #expect(broken.duration == 0)
    }
}

@Suite("HotkeyShortcut")
struct HotkeyShortcutTests {
    @Test("Modifiers are written in Apple's order")
    func modifiersUseAppleOrder() {
        let shortcut = HotkeyShortcut(keyCode: 0x02, modifiers: [.command, .shift, .option, .control])

        #expect(shortcut.displayString == "⌃⌥⇧⌘D", "Menus always read ⌃⌥⇧⌘, so anything else looks wrong to a Mac user.")
    }

    @Test("The default shortcut reads as ⌥Space")
    func defaultShortcutReadsCorrectly() {
        #expect(HotkeyShortcut.defaultToggleDictation.displayString == "⌥Space")
    }

    @Test("The default shortcut avoids system-owned combinations")
    func defaultShortcutAvoidsSystemCombos() {
        // ⌥⌘D is macOS's own "Turn Dock Hiding On/Off" — shipping it as the default
        // meant the hotkey never fired. This pins the fix.
        let dockToggle = HotkeyShortcut(keyCode: 0x02, modifiers: [.command, .option])
        #expect(HotkeyShortcut.defaultToggleDictation != dockToggle)
    }

    @Test("An unknown key code is shown honestly rather than guessed at")
    func unknownKeyCodeIsNotGuessed() {
        let shortcut = HotkeyShortcut(keyCode: 0xFE, modifiers: .command)

        #expect(shortcut.displayString == "⌘Key 254", "A wrong key name in the UI is worse than an ugly one.")
    }

    @Test("A shortcut survives a round trip through storage")
    func shortcutIsCodable() throws {
        let original = HotkeyShortcut(keyCode: 0x31, modifiers: [.control, .option])

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(HotkeyShortcut.self, from: data)

        #expect(restored == original)
    }
}
