//
//  PermissionsView.swift
//  LibreVoice
//

import SwiftUI

/// Shows what LibreVoice has been allowed to do, and why it asked.
///
/// Every permission states its own reason in plain language. For an app asking for the
/// microphone and control of other apps — the two scariest things one can ask a Mac
/// user for — explaining the request is part of deserving it.
/// The permission rows, shaped to sit inside another screen's `Form`.
///
/// Permissions used to be a screen of their own. They are two rows that are almost always
/// green, so a whole sidebar entry made the app look more complicated than it is and gave
/// the user one more place to check. Living inside General puts them where someone goes
/// when something is not working, and takes an item out of the sidebar.
struct PermissionsSection: View {
    @Environment(\.services) private var services
    @State private var viewModel: PermissionsViewModel?

    var body: some View {
        Section {
            if let viewModel {
                ForEach(viewModel.rows) { row in
                    PermissionRowView(row: row) {
                        Task { await viewModel.resolve(row.permission) }
                    }
                }
            }
        } header: {
            Text("Permissions")
        }
        .task {
            let viewModel = viewModel ?? PermissionsViewModel(container: services)
            self.viewModel = viewModel
            await viewModel.refresh()
        }
        .task {
            await viewModel?.observeStatuses()
        }
    }
}

/// One permission: what it is, why it is needed, and what to do about it.
private struct PermissionRowView: View {
    let row: PermissionsViewModel.Row
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbolName)
                .font(.title2)
                .foregroundStyle(row.status.isUsable ? Color.accentColor : .secondary)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(row.permission.displayName)
                        .font(.headline)

                    if !row.permission.isRequired {
                        Text("Optional")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: .capsule)
                    }
                }

                Text(row.permission.rationale)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Shown only while the permission is missing: the "it is switched on
                // yet still refused" trap is invisible from inside the app, so the way
                // out has to be spelled out where the user is already looking.
                if !row.status.isUsable, let hint = row.permission.staleGrantHint {
                    Label(hint, systemImage: "exclamationmark.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                statusBadge

                if let title = row.actionTitle {
                    Button(title, action: action)
                        .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.permission.displayName)
        .accessibilityValue(statusText)
    }

    private var symbolName: String {
        switch row.permission {
        case .microphone: row.status.isUsable ? "mic.fill" : "mic.slash"
        case .accessibility: row.status.isUsable ? "accessibility.fill" : "accessibility"
        }
    }

    private var statusText: String {
        switch row.status {
        case .granted: String(localized: "Allowed")
        case .denied: String(localized: "Not allowed")
        case .notDetermined: String(localized: "Not requested")
        case .restricted: String(localized: "Blocked by policy")
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        Label(statusText, systemImage: row.status.isUsable ? "checkmark.circle.fill" : "circle.dashed")
            .font(.caption)
            .foregroundStyle(row.status.isUsable ? .green : .secondary)
            .labelStyle(.titleAndIcon)
            .accessibilityHidden(true)
    }
}

#Preview("Nothing granted") {
    Form { PermissionsSection() }
        .formStyle(.grouped)
        .environment(\.services, PreviewServiceContainer(permissions: StubPermissionService.notDetermined))
        .frame(width: 620, height: 320)
}

#Preview("All granted") {
    Form { PermissionsSection() }
        .formStyle(.grouped)
        .environment(\.services, PreviewServiceContainer())
        .frame(width: 620, height: 320)
}
