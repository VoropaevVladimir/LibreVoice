//
//  ExperienceCoordinator.swift
//  LibreVoice
//

import Foundation
import Observation
import QuartzCore
import simd
import SwiftUI

/// Runs the entire user-facing experience: which ``ExperienceState`` the app is in, how
/// it morphs between them, and when the floating capsule is on screen.
///
/// It deliberately knows nothing about whisper.cpp — it reacts only to
/// ``DictationCoordinator``'s published state, the transcript, and the settings. That
/// one-way dependency is what the brief demands, and it is also what makes this
/// testable: drive the dictation states, assert on the experience arc.
///
/// The mapping is not one-to-one. `completed` exists only here: the pipeline is already
/// idle while the capsule still acknowledges success. And `thinking` versus `typing`
/// during recognition is decided by whether text has arrived recently — recognition
/// that is producing words *is* typing, whatever the pipeline calls it.
@Observable
@MainActor
final class ExperienceCoordinator {
    /// Where the experience is right now.
    private(set) var state: ExperienceState = .idle

    /// When the current state was entered, for time-based effects like the glow swell.
    private(set) var stateEnteredAt: TimeInterval = CACurrentMediaTime()

    /// The morph between experience recipes, read by the renderer every frame.
    private(set) var morph = MorphRenderer()

    /// The theme colour as the shader wants it.
    private(set) var tint: SIMD4<Float> = SIMD4(0.3, 0.6, 1.0, 1.0)

    private let dictation: DictationCoordinator
    private let settings: AppSettings
    private let sounds: any SoundPlaying
    private let logger: any Logger

    private var panel: CapsulePanelController?
    private var observationTask: Task<Void, Never>?
    private var lingerTask: Task<Void, Never>?

    /// When the transcript last grew, distinguishing "thinking" from "typing".
    private var lastTextChange = Date.distantPast
    private var lastSeenText = ""

    init(
        dictation: DictationCoordinator,
        settings: AppSettings,
        sounds: any SoundPlaying,
        logger: any Logger
    ) {
        self.dictation = dictation
        self.settings = settings
        self.sounds = sounds
        self.logger = logger
    }

    /// The raw microphone level for the renderer's envelope follower.
    var rawAudioLevel: Float {
        Float(dictation.audioLevel.rms)
    }

    // MARK: - Lifecycle

    /// Starts reacting to dictation. Called once from the composition root.
    func start() {
        guard observationTask == nil else { return }
        panel = CapsulePanelController(coordinator: self)
        applyTheme()

        observationTask = Task { [weak self] in
            guard let self else { return }
            for await _ in self.observedChanges() {
                self.reduce()
            }
        }
    }

    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
        lingerTask?.cancel()
    }

    // MARK: - The state machine

    /// Reads the dictation world and moves the experience accordingly.
    private func reduce() {
        applyTheme()
        trackTranscript()

        let target: ExperienceState
        switch dictation.state {
        case .idle:
            // The pipeline finished. If the experience was mid-arc, close it with a
            // completion beat; a linger task then flows it home to idle.
            switch state {
            case .thinking, .typing:
                target = .completed
            case .preparing, .listening:
                target = .idle // cancelled before any recognition
            default:
                target = state // completed/error linger on their own timers
            }
        case .preparing:
            target = .preparing
        case .listening:
            target = .listening
        case .finishing:
            // Recognition is running. Words arriving now means we are typing;
            // silence from the engine means we are thinking.
            let textIsFlowing = Date().timeIntervalSince(lastTextChange) < 0.6
            target = textIsFlowing ? .typing : .thinking
        case .failed:
            target = .error
        }

        transition(to: target)
    }

    /// Moves to `state` if that is a designed transition, scheduling any linger.
    private func transition(to newState: ExperienceState) {
        guard newState != state else { return }
        guard state.canTransition(to: newState) else {
            logger.debug(
                "Clamped experience transition \(state.rawValue) → \(newState.rawValue).",
                category: .app
            )
            return
        }

        let now = CACurrentMediaTime()
        morph.transition(to: newState, at: now)
        let previous = state
        state = newState
        stateEnteredAt = now

        panel?.setVisible(newState.showsCapsule)
        playSound(entering: newState, from: previous)

        lingerTask?.cancel()
        switch newState {
        case .completed:
            lingerTask = linger(for: ExperienceTransition.completedLinger)
        case .error:
            lingerTask = linger(for: ExperienceTransition.errorLinger)
        case .idle:
            lastSeenText = ""
        default:
            break
        }
    }

    /// Makes the sound that belongs to entering `newState`.
    ///
    /// Sounds are tied to *transitions*, not to states, which is why this takes both:
    /// the same state can be arrived at for different reasons, and only some of them
    /// deserve to be heard. Entering `listening` from `preparing` is the start of
    /// dictation and gets the ascending motif; there is no other route into it, but
    /// stating the origin keeps that a fact rather than an assumption.
    private func playSound(entering newState: ExperienceState, from previous: ExperienceState) {
        guard settings.playFeedbackSounds else { return }

        switch newState {
        case .listening where previous == .preparing:
            play(.recordingStarted)

        case .thinking where previous == .listening:
            // The descending motif closes the recording as the wave dissolves into
            // particles. Recognition itself is silent: an ambience under the wait was
            // one sound too many, so processing is shown, not heard.
            play(.recordingStopped)

        case .completed:
            play(.completed)

        case .error:
            play(.failed)

        default:
            // Cancellation (→ idle before recognition) and every other arrival are
            // silent.
            break
        }
    }

    private func play(_ sound: DictationSound) {
        let mode = settings.dictationMode
        Task { [sounds] in await sounds.play(sound, mode: mode) }
    }

    /// After `duration`, flows the current acknowledgement state home to idle.
    private func linger(for duration: TimeInterval) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self else { return }
            // A new session may have started during the linger; only fall home if not.
            if self.state == .completed || self.state == .error {
                self.transition(to: .idle)
            }
        }
    }

    // MARK: - Inputs

    /// Notes transcript growth, which is what separates typing from thinking.
    ///
    /// The text itself is never published — the capsule shows none — but *when* it last
    /// grew is what tells the state machine that recognition is producing words rather
    /// than still chewing on the audio.
    private func trackTranscript() {
        let text = dictation.transcript.displayText
        guard text != lastSeenText else { return }
        lastSeenText = text
        lastTextChange = Date()
    }

    /// Applies the mode's theme colour — or error red, which overrides any theme.
    private func applyTheme() {
        let color: Color = state == .error ? Color(red: 1.0, green: 0.28, blue: 0.25) : settings.dictationMode.themeColor
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
        tint = SIMD4(
            Float(resolved.redComponent),
            Float(resolved.greenComponent),
            Float(resolved.blueComponent),
            1
        )
    }

    /// A stream that ticks whenever anything the experience depends on changes.
    private func observedChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            Task { @MainActor [weak self] in
                self?.armObservation(continuation)
            }
        }
    }

    /// Registers one round of observation; `onChange` fires once, so it re-arms itself.
    private func armObservation(_ continuation: AsyncStream<Void>.Continuation) {
        withObservationTracking {
            _ = dictation.state
            _ = dictation.transcript.displayText
            _ = dictation.audioLevel
            _ = settings.dictationMode
        } onChange: { [weak self] in
            continuation.yield()
            Task { @MainActor in
                self?.armObservation(continuation)
            }
        }
    }
}
