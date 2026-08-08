//
//  ExperienceStateTests.swift
//  LibreVoiceTests
//

import Foundation
import Testing
@testable import LibreVoice

@Suite("Experience state machine")
struct ExperienceStateTests {
    @Test("The designed arc is legal end to end")
    func happyPathIsLegal() {
        #expect(ExperienceState.idle.canTransition(to: .preparing))
        #expect(ExperienceState.preparing.canTransition(to: .listening))
        #expect(ExperienceState.listening.canTransition(to: .thinking))
        #expect(ExperienceState.thinking.canTransition(to: .typing))
        #expect(ExperienceState.typing.canTransition(to: .completed))
        #expect(ExperienceState.completed.canTransition(to: .idle))
    }

    @Test("A session can start again straight from an ending")
    func canStartAgainImmediately() {
        // Dictating twice in quick succession is normal, so both closing states must
        // lead back into a new session without passing through idle first.
        #expect(ExperienceState.completed.canTransition(to: .preparing))
        #expect(ExperienceState.error.canTransition(to: .preparing))
    }

    @Test("The error arc is legal")
    func errorPathIsLegal() {
        #expect(ExperienceState.preparing.canTransition(to: .error))
        #expect(ExperienceState.listening.canTransition(to: .error))
        #expect(ExperienceState.thinking.canTransition(to: .error))
        #expect(ExperienceState.error.canTransition(to: .idle))
    }

    @Test("Cancelling before recognition returns quietly to idle")
    func cancellationIsLegal() {
        #expect(ExperienceState.preparing.canTransition(to: .idle))
        #expect(ExperienceState.listening.canTransition(to: .idle))
    }

    @Test("Nonsense jumps are rejected")
    func illegalJumpsAreRejected() {
        // Listening is never entered directly: the capsule must appear and get ready
        // first, or it would claim to be hearing before the microphone was open.
        #expect(!ExperienceState.idle.canTransition(to: .listening))
        #expect(!ExperienceState.idle.canTransition(to: .completed))
        #expect(!ExperienceState.idle.canTransition(to: .thinking))
        #expect(!ExperienceState.completed.canTransition(to: .typing))
        #expect(!ExperienceState.thinking.canTransition(to: .listening))
        #expect(!ExperienceState.preparing.canTransition(to: .thinking))
    }

    @Test("Recognition may bounce between thinking and typing")
    func thinkingTypingBounce() {
        #expect(ExperienceState.thinking.canTransition(to: .typing))
        #expect(ExperienceState.typing.canTransition(to: .thinking))
    }

    @Test("Only idle hides the capsule")
    func capsuleVisibility() {
        #expect(!ExperienceState.idle.showsCapsule)
        for state in ExperienceState.allCases where state != .idle {
            #expect(state.showsCapsule)
        }
    }

    @Test("Every state can eventually reach idle")
    func everyStateReachesIdle() {
        for start in ExperienceState.allCases {
            var frontier: Set<ExperienceState> = [start]
            var seen = frontier
            var reachedIdle = start == .idle
            while !reachedIdle, !frontier.isEmpty {
                let next = Set(frontier.flatMap(\.legalNextStates)).subtracting(seen)
                reachedIdle = next.contains(.idle)
                seen.formUnion(next)
                frontier = next
            }
            #expect(reachedIdle, "\(start) has no path home to idle")
        }
    }
}

@Suite("Experience transitions")
struct ExperienceTransitionTests {
    @Test("No transition is instant")
    func nothingIsInstant() {
        for from in ExperienceState.allCases {
            for to in from.legalNextStates {
                let duration = ExperienceTransition.duration(from: from, to: to)
                #expect(duration >= 0.3, "\(from) → \(to) is too fast (\(duration)s)")
            }
        }
    }

    @Test("Dissolving the wave into particles gets the most time")
    func signatureTransitionBreathes() {
        let dissolve = ExperienceTransition.duration(from: .listening, to: .thinking)
        let typing = ExperienceTransition.duration(from: .thinking, to: .typing)
        #expect(dissolve > typing)
    }
}

@Suite("Morph renderer")
struct MorphRendererTests {
    @Test("Progress runs 0 → 1 across the designed duration")
    func progressRuns() {
        var morph = MorphRenderer()
        morph.transition(to: .listening, at: 10)
        #expect(morph.progress(at: 10) == 0)
        let duration = ExperienceTransition.duration(from: .idle, to: .listening)
        #expect(morph.progress(at: 10 + duration) == 1)
        #expect(abs(morph.progress(at: 10 + duration / 2) - 0.5) < 0.01)
    }

    @Test("Re-targeting mid-morph keeps continuity")
    func retargetKeepsContinuity() {
        var morph = MorphRenderer()
        morph.transition(to: .listening, at: 0)
        // Late in the first morph, redirect: the reached state becomes the new origin.
        morph.transition(to: .thinking, at: 0.45)
        #expect(morph.fromState == .listening)
        #expect(morph.toState == .thinking)
        #expect(morph.progress(at: 0.45) == 0)
    }
}
