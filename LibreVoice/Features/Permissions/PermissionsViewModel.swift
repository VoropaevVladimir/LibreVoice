//
//  PermissionsViewModel.swift
//  LibreVoice
//

import Foundation
import Observation

/// Drives the permissions screen.
@Observable
@MainActor
final class PermissionsViewModel {
    /// One permission, as the screen needs to show it.
    struct Row: Identifiable {
        let permission: Permission
        var status: PermissionStatus

        var id: Permission { permission }

        /// What the button should say, given the status.
        ///
        /// `nil` once granted — there is nothing left to do, and a button that did
        /// nothing would be worse than no button.
        var actionTitle: String? {
            switch status {
            case .granted: nil
            case .notDetermined: String(localized: "Allow…")
            case .denied, .restricted: String(localized: "Open System Settings…")
            }
        }
    }

    private(set) var rows: [Row] = Permission.allCases.map { Row(permission: $0, status: .notDetermined) }

    private let permissions: any PermissionService

    init(container: any ServiceContainer) {
        self.permissions = container.permissions
    }

    /// Reads the current status of every permission.
    func refresh() async {
        var updated: [Row] = []
        for permission in Permission.allCases {
            updated.append(Row(permission: permission, status: await permissions.status(of: permission)))
        }
        rows = updated
    }

    /// Keeps every row current while the screen is visible.
    ///
    /// Accessibility in particular can be granted while the app runs, with no
    /// notification, so the screen has to watch rather than ask once.
    func observeStatuses() async {
        await withTaskGroup(of: Void.self) { group in
            for permission in Permission.allCases {
                group.addTask { [permissions] in
                    for await status in permissions.statusChanges(for: permission) {
                        await MainActor.run { self.update(permission, to: status) }
                    }
                }
            }
        }
    }

    /// Requests `permission`, falling back to System Settings when asking achieves nothing.
    ///
    /// Accessibility is asked for even when it reads as denied — see
    /// ``Permission/isWorthRequestingWhenDenied``. If the request leaves the status
    /// unchanged, the system either suppressed its prompt or the user has already
    /// refused, and System Settings is the only remaining route.
    func resolve(_ permission: Permission) async {
        let current = await permissions.status(of: permission)

        guard current.isPromptable || permission.isWorthRequestingWhenDenied else {
            permissions.openSystemSettings(for: permission)
            return
        }

        let result = await permissions.request(permission)
        update(permission, to: result)

        guard !result.isUsable, result == current else { return }

        // Asking changed nothing. Give the prompt a moment to appear — if it did, the
        // user is already being asked and opening Settings on top would be noise.
        try? await Task.sleep(for: .milliseconds(600))
        if await permissions.status(of: permission).isUsable == false {
            permissions.openSystemSettings(for: permission)
        }
    }

    private func update(_ permission: Permission, to status: PermissionStatus) {
        guard let index = rows.firstIndex(where: { $0.permission == permission }) else { return }
        rows[index].status = status
    }
}
