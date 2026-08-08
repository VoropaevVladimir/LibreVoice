//
//  LogCategory.swift
//  LibreVoice
//

import Foundation

/// The subsystem a log record originated from.
///
/// Categories map onto `os.Logger` categories, so they show up as filterable
/// columns in Console.app.
nonisolated enum LogCategory: String, Sendable, CaseIterable, Identifiable {
    /// Application lifecycle and composition root.
    case app

    /// Microphone capture and audio routing.
    case audio

    /// Speech recognition engines and model management.
    case speech

    /// Global hotkey registration and delivery.
    case hotkeys

    /// System authorization requests and status changes.
    case permissions

    /// Inserting transcribed text into other applications.
    case textInsertion

    /// The dictation session state machine.
    case dictation

    /// Reading and writing user preferences.
    case settings

    var id: String { rawValue }

    /// A short, human-readable name suitable for display in the log viewer.
    var displayName: String {
        switch self {
        case .app: String(localized: "App")
        case .audio: String(localized: "Audio")
        case .speech: String(localized: "Speech")
        case .hotkeys: String(localized: "Hotkeys")
        case .permissions: String(localized: "Permissions")
        case .textInsertion: String(localized: "Text Insertion")
        case .dictation: String(localized: "Dictation")
        case .settings: String(localized: "Settings")
        }
    }
}
