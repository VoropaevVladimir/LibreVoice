//
//  TranscriptProcessingTests.swift
//  LibreVoiceTests
//

import Foundation
import Testing
@testable import LibreVoice

@Suite("Dictation modes")
struct ModeTranscriptProcessorTests {
    private let processor = ModeTranscriptProcessor()

    @Test("Fast passes text through, trimming only outer whitespace")
    func fastIsUntouched() {
        #expect(processor.process("  так и было сказано,да \n", mode: .fast) == "так и было сказано,да")
    }

    @Test("Smart cleans spacing, punctuation and capitalisation")
    func smartCleansUp() {
        let raw = "привет , мир.это  тест!  правда"
        #expect(processor.process(raw, mode: .smart) == "Привет, мир. Это тест! Правда")
    }

    @Test("Precision applies the terminology dictionary on top of Smart")
    func precisionAppliesTerminology() {
        let raw = "я диктую в либре войс каждый день"
        #expect(processor.process(raw, mode: .precision) == "Я диктую в LibreVoice каждый день")
    }
}

@Suite("SmartTextCorrector")
struct SmartTextCorrectorTests {
    @Test("Collapses runs of spaces")
    func collapsesWhitespace() {
        #expect(SmartTextCorrector.collapseWhitespace(in: "a  b   c") == "a b c")
    }

    @Test("Removes space before punctuation and inserts one after")
    func fixesPunctuationSpacing() {
        #expect(SmartTextCorrector.normalisePunctuationSpacing(in: "слово , ещё,раз") == "слово, ещё, раз")
    }

    @Test("Capitalises the first letter of each sentence, Cyrillic included")
    func capitalisesSentences() {
        #expect(SmartTextCorrector.capitaliseSentences(in: "привет. как дела? хорошо!") == "Привет. Как дела? Хорошо!")
    }

    @Test("Does not break decimal numbers")
    func decimalsSurvive() {
        // "3.14" contains a full stop, but no letter follows it directly, so no space is
        // inserted and nothing is capitalised.
        #expect(SmartTextCorrector.correct("значение 3.14 верно") == "Значение 3.14 верно")
    }
}

@Suite("TerminologyDictionary")
struct TerminologyDictionaryTests {
    @Test("Replaces case-insensitively and preserves surrounding text")
    func replaces() {
        let dictionary = TerminologyDictionary(replacements: ["либре войс": "LibreVoice"])
        #expect(dictionary.apply(to: "открой Либре Войс сейчас") == "открой LibreVoice сейчас")
    }

    @Test("Longest pattern wins")
    func longestWins() {
        let dictionary = TerminologyDictionary(replacements: [
            "либре": "Libre",
            "либре войс": "LibreVoice",
        ])
        #expect(dictionary.apply(to: "это либре войс") == "это LibreVoice")
    }

    @Test("An empty dictionary changes nothing")
    func emptyIsIdentity() {
        #expect(TerminologyDictionary(replacements: [:]).apply(to: "как есть") == "как есть")
    }
}
