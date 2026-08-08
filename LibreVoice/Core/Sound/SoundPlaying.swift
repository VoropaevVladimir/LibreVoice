//
//  SoundPlaying.swift
//  LibreVoice
//

import Foundation

/// Plays LibreVoice's sounds.
///
/// The protocol says nothing about synthesis, sample rates or audio engines — a
/// conformance could equally play files, and the previews' conformance plays nothing at
/// all. What the app knows is only "this happened, make the sound for it".
///
/// Every method is non-throwing and returns immediately. Audio is a courtesy: a sound
/// that fails to play must never interrupt dictation, and a caller must never have to
/// wait for one before getting on with the work.
nonisolated protocol SoundPlaying: Sendable {
    /// Plays `sound` once, in the character of `mode`.
    ///
    /// Every sound is a brief, self-contained gesture — there are no looping or
    /// continuous sounds to stop.
    func play(_ sound: DictationSound, mode: DictationMode) async
}
