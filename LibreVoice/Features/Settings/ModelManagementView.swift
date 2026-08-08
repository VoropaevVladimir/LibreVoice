//
//  ModelManagementView.swift
//  LibreVoice
//

import SwiftUI

/// Lets the user download, watch, and remove speech models.
///
/// The product goal made visible: nobody should have to hunt down a model file, pick the
/// right quantisation, or drop it in a folder. The catalog names the models in plain
/// language with their sizes, one button downloads and verifies them, and the app owns
/// the rest.
struct ModelManagementView: View {
    @Environment(\.services) private var services
    @State private var viewModel: ModelManagementViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                Color.clear
            }
        }
        .task {
            let viewModel = viewModel ?? ModelManagementViewModel(container: services)
            self.viewModel = viewModel
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func content(_ viewModel: ModelManagementViewModel) -> some View {
        Form {
            Section {
                if viewModel.rows.isEmpty && viewModel.hasLoaded {
                    ContentUnavailableView(
                        "No models available",
                        systemImage: "shippingbox",
                        description: Text("The model catalog is empty or couldn't be read.")
                    )
                } else {
                    ForEach(viewModel.rows) { row in
                        ModelRowView(
                            row: row,
                            isDefault: viewModel.selectedModelID == row.id,
                            isPreparing: viewModel.isPreparing(row),
                            onDownload: { viewModel.download(row.descriptor) },
                            onCancel: { viewModel.cancel(row.id) },
                            onRemove: { viewModel.remove(row.id) },
                            onSelect: { viewModel.selectAsDefault(row.id) }
                        )
                    }
                }
            } header: {
                // Not "Whisper Models" any more: Parakeet sits in this same list, which is
                // the whole point of having one list instead of an engine picker.
                Text("Speech Models")
            } footer: {
                footer(viewModel)
            }
        }
        .formStyle(.grouped)
        .task { await viewModel.observe() }
    }

    @ViewBuilder
    private func footer(_ viewModel: ModelManagementViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let size = viewModel.installedSizeSummary {
                Text("Using \(size) of disk.")
            }
            Label(
                "Models download over HTTPS and are checked against a SHA-256 fingerprint before use. No audio is ever sent — only the model comes down.",
                systemImage: "checkmark.shield"
            )
            .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.top, 6)
    }
}

/// One model: name, size, and whatever control fits its current state.
///
/// Not private: the Precision screen shows its language models with exactly this row,
/// so both model families look and behave identically.
struct ModelRowView: View {
    let row: ModelManagementViewModel.Row
    let isDefault: Bool

    /// Whether this model's engine is compiling for the Neural Engine right now. Downloaded
    /// is not the same as ready, and the row should not pretend otherwise.
    var isPreparing: Bool = false

    let onDownload: () -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(row.state.isInstalled ? Color.accentColor : .secondary)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.descriptor.displayName)
                        .font(.headline)
                    Text(row.descriptor.formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(row.descriptor.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                stateDetail
            }

            Spacer(minLength: 8)

            control
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.descriptor.displayName)
        .accessibilityValue(accessibilityStateText)
    }

    private var symbolName: String {
        switch row.state {
        case .installed: "checkmark.circle.fill"
        case .downloading, .verifying: "arrow.down.circle"
        case .failed: "exclamationmark.triangle.fill"
        case .notInstalled: "arrow.down.circle.dotted"
        }
    }

    @ViewBuilder
    private var stateDetail: some View {
        switch row.state {
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: progress.fraction ?? 0, total: 1)
                    .progressViewStyle(.linear)
                Text(progress.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.top, 2)

        case .verifying:
            Label("Verifying…", systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

        case .failed(let error):
            Text(error.errorDescription ?? "Download failed")
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.top, 2)

        case .installed where isPreparing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Preparing for the Neural Engine — one time only, about a minute. You can keep using the app.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 2)

        case .installed, .notInstalled:
            EmptyView()
        }
    }

    @ViewBuilder
    private var control: some View {
        switch row.state {
        case .notInstalled:
            Button("Download", action: onDownload)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

        case .failed:
            Button("Retry", action: onDownload)
                .buttonStyle(.bordered)
                .controlSize(.small)

        case .downloading, .verifying:
            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.small)

        case .installed:
            HStack(spacing: 8) {
                if isDefault {
                    Label("Default", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .labelStyle(.titleAndIcon)
                } else {
                    Button("Use", action: onSelect)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Dictate with this model")
                }

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove this model")
            }
        }
    }

    private var accessibilityStateText: String {
        switch row.state {
        case .notInstalled: String(localized: "Not downloaded")
        case .downloading(let progress): String(localized: "Downloading, \(progress.description)")
        case .verifying: String(localized: "Verifying")
        case .installed where isPreparing: String(localized: "Installed, preparing")
        case .installed: String(localized: "Installed")
        case .failed: String(localized: "Download failed")
        }
    }
}

#Preview("Mixed states") {
    let turbo = ModelIdentifier(rawValue: "mlx-whisper-large-v3-turbo")
    return ModelManagementView()
        .environment(\.services, PreviewServiceContainer(
            models: StubModelRepository(states: [
                turbo: .installed(sizeBytes: 1_600_000_000),
            ])
        ))
        .frame(width: 560, height: 460)
}
