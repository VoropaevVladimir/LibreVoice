//
//  TranscriptTests.swift
//  LibreVoiceTests
//

import Testing
@testable import LibreVoice

@Suite("Transcript")
struct TranscriptTests {
    @Test("A partial result is shown but not committed")
    func partialIsNotCommitted() {
        var transcript = Transcript()

        let settled = transcript.apply(.partial(TranscriptionSegment(text: "hello wor")))

        #expect(settled == nil, "A partial must never be handed to the caller to type — it will be revised.")
        #expect(transcript.displayText == "hello wor")
        #expect(transcript.committedText.isEmpty)
    }

    @Test("A final result replaces the pending partial rather than appending to it")
    func finalReplacesPartial() {
        var transcript = Transcript()
        transcript.apply(.partial(TranscriptionSegment(text: "hello wor")))

        let settled = transcript.apply(.final(TranscriptionSegment(text: "hello world")))

        #expect(settled == "hello world")
        #expect(transcript.displayText == "hello world", "The partial must not survive alongside the final.")
        #expect(transcript.committedText == "hello world")
    }

    @Test("Each final result is returned exactly once, so no word is typed twice")
    func eachFinalIsReturnedOnce() {
        var transcript = Transcript()

        let first = transcript.apply(.final(TranscriptionSegment(text: "one ")))
        let second = transcript.apply(.final(TranscriptionSegment(text: "two")))

        #expect(first == "one ")
        #expect(second == "two")
        #expect(transcript.committedText == "one two")
    }

    @Test("Completion promotes a trailing partial instead of dropping the user's last words")
    func completionPromotesPendingPartial() {
        var transcript = Transcript()
        transcript.apply(.partial(TranscriptionSegment(text: "goodbye")))

        let settled = transcript.apply(.completed)

        #expect(settled == "goodbye", "Text still pending at completion will never be revised, so it must be committed.")
        #expect(transcript.committedText == "goodbye")
    }

    @Test("Completion with nothing pending settles nothing")
    func completionWithoutPartialSettlesNothing() {
        var transcript = Transcript()
        transcript.apply(.final(TranscriptionSegment(text: "done")))

        let settled = transcript.apply(.completed)

        #expect(settled == nil, "Committing again would type the same words twice.")
        #expect(transcript.committedText == "done")
    }

    @Test("Reset clears everything")
    func resetClearsEverything() {
        var transcript = Transcript()
        transcript.apply(.final(TranscriptionSegment(text: "text")))
        transcript.apply(.partial(TranscriptionSegment(text: "more")))

        transcript.reset()

        #expect(transcript.isEmpty)
        #expect(transcript.displayText.isEmpty)
    }
}
