//
//  PermissionStatus.swift
//  LibreVoice
//

import Foundation

/// The current authorization state of a ``Permission``.
nonisolated enum PermissionStatus: Sendable, Equatable, CaseIterable {
    /// The user has not been asked yet. This is the only state in which prompting works.
    case notDetermined

    /// The user allowed access.
    case granted

    /// The user refused access. macOS will not prompt again; the user must change it
    /// in System Settings.
    case denied

    /// Access is blocked by a policy outside the user's control, such as an MDM profile
    /// or Screen Time restriction. Prompting is pointless.
    case restricted

    /// Whether LibreVoice may use the capability right now.
    var isUsable: Bool { self == .granted }

    /// Whether prompting the user could still produce a grant.
    ///
    /// When this is `false` and the status is not `granted`, the only path forward is
    /// deep-linking into System Settings.
    var isPromptable: Bool { self == .notDetermined }
}
