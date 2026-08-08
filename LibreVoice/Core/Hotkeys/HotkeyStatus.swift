//
//  HotkeyStatus.swift
//  LibreVoice
//

import Foundation
import Observation

/// Whether the global dictation shortcut is actually bound.
///
/// Registration fails when another app already owns the combination — an ordinary thing
/// to happen on someone's Mac. The whole product is that shortcut, so failing silently
/// leaves the user holding a key that does nothing, in front of a settings screen still
/// advertising it, with no reason to suspect anything but the app being broken.
///
/// Its own `@Observable` type rather than a property on ``AppEnvironment``, for a reason
/// learned the hard way: the container is held in `@State` but is not itself observable,
/// so a flag living there would change without ever redrawing the view that reads it —
/// a warning that exists in the code and never appears on screen. The same split already
/// exists for ``SpeechWarmUpStatus``.
@Observable
@MainActor
final class HotkeyStatus {
    /// `true` until proven otherwise, so the settings screen does not flash a warning in
    /// the moment before registration is attempted.
    private(set) var isRegistered = true

    func markRegistered() {
        isRegistered = true
    }

    func markFailed() {
        isRegistered = false
    }
}
