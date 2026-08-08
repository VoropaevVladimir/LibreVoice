//
//  HotkeyService.swift
//  LibreVoice
//

import Foundation

/// Identifies a system-wide action that a shortcut can trigger.
///
/// A named identifier rather than a closure per shortcut: closures would tie the
/// service's lifetime to whatever captured them, and identifiers survive the shortcut
/// being changed in settings.
nonisolated struct HotkeyID: RawRepresentable, Sendable, Hashable, Codable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension HotkeyID {
    /// Start dictation, or stop it if it is already running.
    static let toggleDictation = HotkeyID(rawValue: "toggleDictation")
}

/// Whether a shortcut was just pressed down or just released.
///
/// Both phases exist because dictation is push-to-talk: hold the key to speak, let go
/// to insert. A press-only stream cannot express "let go".
nonisolated enum HotkeyPhase: Sendable, Hashable {
    case pressed
    case released
}

/// One thing that happened to a registered shortcut.
nonisolated struct HotkeyEvent: Sendable, Hashable {
    let id: HotkeyID
    let phase: HotkeyPhase

    init(id: HotkeyID, phase: HotkeyPhase) {
        self.id = id
        self.phase = phase
    }
}

/// Something that stopped a shortcut from being registered.
nonisolated enum HotkeyError: LocalizedError, Sendable, Equatable {
    /// Another application already owns this combination.
    case shortcutAlreadyInUse(HotkeyShortcut)

    /// The system refused the registration.
    case registrationFailed(status: Int32)

    var errorDescription: String? {
        switch self {
        case .shortcutAlreadyInUse(let shortcut):
            String(localized: "\(shortcut.displayString) is already used by another app.")
        case .registrationFailed(let status):
            String(localized: "The shortcut couldn't be registered (error \(status)).")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .shortcutAlreadyInUse:
            String(localized: "Choose a different shortcut in LibreVoice Settings › Shortcuts.")
        case .registrationFailed:
            nil
        }
    }
}

/// Registers system-wide keyboard shortcuts and reports presses and releases.
///
/// Events arrive as an `AsyncStream` rather than via a delegate or callback, so
/// consumers `for await` them in a structured task that dies with its owner — no
/// unregistering in `deinit`, no retain cycles.
nonisolated protocol HotkeyService: Sendable {
    /// Fires whenever a registered shortcut is pressed or released.
    ///
    /// Deliberately one shared stream for every shortcut: a stream per shortcut would
    /// need a task per shortcut, and the event already says which fired and how.
    var events: AsyncStream<HotkeyEvent> { get }

    /// Registers `shortcut` to fire `id`, replacing any shortcut already bound to `id`.
    ///
    /// - Throws: ``HotkeyError`` if the combination is unavailable.
    func register(_ shortcut: HotkeyShortcut, for id: HotkeyID) async throws

    /// Unregisters whatever is bound to `id`. Safe to call when nothing is.
    func unregister(_ id: HotkeyID) async

    /// Unregisters every shortcut this service owns.
    func unregisterAll() async
}
