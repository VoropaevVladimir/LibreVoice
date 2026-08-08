//
//  WhisperSegmentJoiningTests.swift
//  LibreVoiceTests
//

import Foundation
import Testing
import WhisperRuntime
@testable import LibreVoice

/// The anti-hallucination filter, finally testable.
///
/// This logic decides what gets typed into someone's document. Until whisper.cpp was moved
/// behind ``WhisperRuntime`` it took a raw C context pointer, so exercising it needed a
/// 1.5 GB model and a microphone — which meant it was never exercised at all. It is a pure
/// function over plain values now, and these are the cases that matter.
@Suite("Whisper segment joining")
struct WhisperSegmentJoiningTests {
    private func segment(
        _ text: String,
        from start: TimeInterval = 0,
        to end: TimeInterval = 1,
        noSpeech: Float = 0
    ) -> WhisperSegment {
        WhisperSegment(
            text: text,
            startSeconds: start,
            endSeconds: end,
            noSpeechProbability: noSpeech
        )
    }

    @Test("Credible segments are joined in order and trimmed")
    func joinsCredibleSegments() {
        let (text, range) = WhisperCppEngine.join([
            segment(" Привет", from: 0, to: 1),
            segment(", как дела?", from: 1, to: 2.5),
        ])

        #expect(text == "Привет, как дела?")
        #expect(range == 0...2.5)
    }

    @Test("A segment the model itself doubts is never typed")
    func dropsDoubtfulSegments() {
        let (text, _) = WhisperCppEngine.join([
            segment("Real speech.", noSpeech: 0.1),
            segment(" Subtitles by the Amara.org community", from: 1, to: 9, noSpeech: 0.9),
        ])

        #expect(
            text == "Real speech.",
            "This exact hallucination is what Whisper invents over room tone."
        )
    }

    @Test("The span covers only the segments that were kept")
    func spanIgnoresDroppedSegments() {
        let (_, range) = WhisperCppEngine.join([
            segment("Kept.", from: 2, to: 3, noSpeech: 0.0),
            segment("Dropped.", from: 50, to: 90, noSpeech: 0.95),
        ])

        #expect(range == 2...3, "A dropped segment must not stretch the timestamp of what was said.")
    }

    @Test("Nothing credible yields empty text and no span, rather than a bogus range")
    func allDoubtfulYieldsNothing() {
        let (text, range) = WhisperCppEngine.join([
            segment("(wind blowing)", noSpeech: 0.99),
        ])

        #expect(text.isEmpty)
        #expect(range == nil)
    }

    @Test("No segments at all is not a crash")
    func emptyInput() {
        let (text, range) = WhisperCppEngine.join([])

        #expect(text.isEmpty)
        #expect(range == nil)
    }

    @Test("The boundary is inclusive — exactly one half is still credible")
    func boundaryIsInclusive() {
        let (text, _) = WhisperCppEngine.join([segment("Borderline.", noSpeech: 0.5)])

        #expect(text == "Borderline.", "0.5 is the documented threshold, not the first rejected value.")
    }
}
