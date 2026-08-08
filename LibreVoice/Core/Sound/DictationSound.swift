//
//  DictationSound.swift
//  LibreVoice
//

import Foundation

/// A sound LibreVoice can make.
///
/// Named for what happened, never for how it sounds. The synthesiser owns the timbre and
/// the theme owns its character; everything upstream only ever says *what occurred*, so
/// the entire audio identity can be redesigned without a single call site changing.
///
/// The set is deliberately tiny. Every sound an app makes is an interruption it has
/// decided is worth the user's attention, and a dictation tool that chirps at every
/// opportunity becomes something people switch off.
nonisolated enum DictationSound: String, Sendable, CaseIterable {
    /// Recording has begun — an ascending motif. The first half of the audio logo.
    case recordingStarted

    /// Recording has ended — the same motif descending. The second half.
    case recordingStopped

    /// Text is ready. A small crystalline confirmation.
    case completed

    /// Something failed. Low, soft and brief.
    case failed
}
