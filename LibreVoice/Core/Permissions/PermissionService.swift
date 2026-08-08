//
//  PermissionService.swift
//  LibreVoice
//

import Foundation

/// Reads and requests the system authorizations LibreVoice depends on.
///
/// Abstracting this is what makes the permission flow testable: TCC state belongs to
/// the machine, cannot be reset from inside the app, and cannot be simulated. A fake
/// conformance lets the onboarding UI be exercised in every state — including
/// `.restricted`, which is nearly impossible to reproduce by hand.
nonisolated protocol PermissionService: Sendable {
    /// The current status of `permission`, without prompting.
    func status(of permission: Permission) async -> PermissionStatus

    /// Asks the user for `permission`, and returns the resulting status.
    ///
    /// If the status is not ``PermissionStatus/notDetermined``, no prompt is shown and
    /// the existing status is returned unchanged — macOS only ever prompts once.
    @discardableResult
    func request(_ permission: Permission) async -> PermissionStatus

    /// A stream of status changes for `permission`.
    ///
    /// Accessibility can be granted or revoked in System Settings while the app is
    /// running, with no notification from the system, so observing it is the only way
    /// to keep the UI honest.
    func statusChanges(for permission: Permission) -> AsyncStream<PermissionStatus>

    /// Opens the System Settings pane for `permission`.
    @MainActor
    func openSystemSettings(for permission: Permission)
}
