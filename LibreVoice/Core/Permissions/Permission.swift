//
//  Permission.swift
//  LibreVoice
//

import Foundation

/// A system authorization LibreVoice may need in order to work.
///
/// Only the authorizations the app genuinely uses appear here. Global hotkeys are
/// intentionally absent: LibreVoice registers them through Carbon's
/// `RegisterEventHotKey`, which needs no authorization, rather than an event tap,
/// which would require Input Monitoring. Asking for less is a feature.
nonisolated enum Permission: String, Sendable, CaseIterable, Identifiable {
    /// Access to the microphone. Without it there is nothing to transcribe.
    case microphone

    /// Control of other applications, used to type transcribed text into them.
    case accessibility

    var id: String { rawValue }

    /// A short, human-readable name.
    var displayName: String {
        switch self {
        case .microphone: String(localized: "Microphone")
        case .accessibility: String(localized: "Accessibility")
        }
    }

    /// A plain-language explanation of why LibreVoice asks for this, written for the
    /// person deciding whether to grant it.
    var rationale: String {
        switch self {
        case .microphone:
            String(localized: "LibreVoice needs the microphone to hear what you say. Audio is transcribed on this Mac and is never uploaded.")
        case .accessibility:
            String(localized: "LibreVoice needs Accessibility access to type transcribed text into other apps. It only writes text you dictated — it never reads your screen.")
        }
    }

    /// Whether the app is unusable without this authorization.
    ///
    /// Accessibility is optional: without it dictation still works, the text just
    /// stays inside LibreVoice instead of being typed into the frontmost app.
    var isRequired: Bool {
        switch self {
        case .microphone: true
        case .accessibility: false
        }
    }

    /// Whether asking is worth attempting even when the status already reads as denied.
    ///
    /// Microphone has a truthful API: denied means the user said no, and only System
    /// Settings can undo that. Accessibility does not — `AXIsProcessTrusted()` returns a
    /// bare `Bool`, so "never asked" and "refused" are indistinguishable and both surface
    /// as denied. Treating that as final meant the system prompt was never shown, and the
    /// one path that actually establishes the grant was unreachable.
    var isWorthRequestingWhenDenied: Bool {
        switch self {
        case .microphone: false
        case .accessibility: true
        }
    }

    /// What to try when the permission looks granted in System Settings but the app
    /// still cannot use it. `nil` when no such trap exists.
    ///
    /// This is a real and deeply confusing macOS behaviour rather than a hypothetical:
    /// an unsigned or ad-hoc-signed build is identified to TCC by the hash of its
    /// executable, so every rebuild registers as a *different* application. The old row
    /// stays in the list, still switched on, while the running copy is denied — and
    /// toggling that row only flips a bit on the stale record. Removing the entry is
    /// what forces macOS to record the current build.
    var staleGrantHint: String? {
        switch self {
        case .microphone:
            nil
        case .accessibility:
            String(localized: "Already switched on in System Settings but still not working? Select LibreVoice in the list, remove it with the “−” button, then add it again — macOS ties this permission to a specific copy of the app, and an update leaves the old entry behind.")
        }
    }

    /// The System Settings pane where this authorization can be changed.
    ///
    /// macOS offers no API to grant a permission directly, and a denied permission
    /// cannot be re-prompted, so deep-linking here is the only way to help someone
    /// recover from a "Don't Allow" they later regret.
    var systemSettingsURL: URL? {
        switch self {
        case .microphone:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }
}
