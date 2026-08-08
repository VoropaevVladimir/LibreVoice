//
//  TextInsertionService.swift
//  LibreVoice
//

import Foundation

/// Something that stopped text from being inserted.
nonisolated enum TextInsertionError: LocalizedError, Sendable, Equatable {
    /// LibreVoice has not been granted Accessibility access.
    case accessibilityPermissionDenied

    /// Nothing in the frontmost app is accepting text.
    case noFocusedTextField

    /// The frontmost app rejected the insertion.
    case insertionFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            String(localized: "LibreVoice doesn't have permission to type into other apps.")
        case .noFocusedTextField:
            String(localized: "There's no text field to type into.")
        case .insertionFailed(let reason):
            String(localized: "The text couldn't be inserted: \(reason)")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .accessibilityPermissionDenied:
            String(localized: "Your text is on the clipboard — press ⌘V to paste it. To have it typed automatically, open System Settings › Privacy & Security › Accessibility and turn on LibreVoice.")
        case .noFocusedTextField:
            String(localized: "Your text is on the clipboard — click where it should go and press ⌘V.")
        case .insertionFailed:
            String(localized: "Your text is on the clipboard — press ⌘V to paste it.")
        }
    }
}

/// Delivers transcribed text into whatever app the user is working in.
///
/// This is the service that decides LibreVoice cannot be sandboxed: reaching into
/// another process's text field needs the Accessibility API, which the App Sandbox
/// forbids. See `Documentation/Architecture.md`.
///
/// The protocol says nothing about *how* text arrives — Accessibility, synthesised
/// key events, clipboard-and-paste — because that is exactly the decision that should
/// stay swappable. A future sandboxed App Store build would supply a clipboard-based
/// conformance and change nothing else.
nonisolated protocol TextInsertionService: Sendable {
    /// Whether text can be inserted right now.
    ///
    /// Depends on both permission and what the user has focused, so it must be checked
    /// at the moment of use rather than cached.
    func isAvailable() async -> Bool

    /// Inserts `text` at the insertion point of the frontmost application.
    ///
    /// - Throws: ``TextInsertionError`` if the text could not be delivered.
    func insert(_ text: String) async throws
}
