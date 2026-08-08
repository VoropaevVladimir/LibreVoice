//
//  HomeView.swift
//  LibreVoice
//

import SwiftUI

/// The main dictation screen: press a button, speak, watch text appear.
struct HomeView: View {
    @Environment(\.services) private var services
    @State private var viewModel: HomeViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                // One frame at most, while the view model is built from the environment.
                Color.clear
            }
        }
        .task {
            // Built here rather than in `init` because a SwiftUI view's `init` runs on
            // every parent redraw, and the environment isn't readable there.
            let viewModel = viewModel ?? HomeViewModel(container: services)
            self.viewModel = viewModel
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private func content(_ viewModel: HomeViewModel) -> some View {
        VStack(spacing: 0) {
            header(viewModel)
            Divider()
            transcriptArea(viewModel)
            Divider()
            controls(viewModel)
        }
        .task { await viewModel.observeMicrophoneStatus() }
        .task { await viewModel.observeModelChanges() }
        .navigationTitle("Dictate")
    }

    // MARK: - Header

    @ViewBuilder
    private func header(_ viewModel: HomeViewModel) -> some View {
        HStack {
            StatusIndicator(state: viewModel.state)
            Spacer()
            AudioLevelMeter(level: viewModel.audioLevel, isActive: viewModel.state == .listening)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Transcript

    @ViewBuilder
    private func transcriptArea(_ viewModel: HomeViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let issue = viewModel.blockingIssue {
                    blockingIssueBanner(issue, viewModel: viewModel)
                }

                if case .failed(let error) = viewModel.state {
                    errorBanner(error, viewModel: viewModel)
                }

                if viewModel.transcript.isEmpty {
                    emptyState(viewModel)
                } else {
                    Text(viewModel.transcript.displayText)
                        .font(.title3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func emptyState(_ viewModel: HomeViewModel) -> some View {
        VStack(spacing: 10) {
            Image(systemName: viewModel.state.symbolName)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
                .symbolEffect(.pulse, isActive: viewModel.state == .listening)

            Text(viewModel.state == .listening ? "Listening…" : "Your words appear here")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Everything is transcribed on this Mac. Nothing is uploaded, stored, or sent anywhere.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func blockingIssueBanner(_ issue: HomeViewModel.BlockingIssue, viewModel: HomeViewModel) -> some View {
        NoticeBanner(
            title: issue.title,
            message: issue.message,
            symbolName: "exclamationmark.triangle.fill",
            tint: .orange
        ) {
            if case .microphoneNotGranted(let status) = issue {
                Button(status.isPromptable ? "Allow Microphone…" : "Open System Settings…") {
                    Task { await viewModel.resolveMicrophoneAccess() }
                }
            }
        }
    }

    @ViewBuilder
    private func errorBanner(_ error: DictationError, viewModel: HomeViewModel) -> some View {
        NoticeBanner(
            title: error.errorDescription ?? "Dictation failed",
            message: error.recoverySuggestion ?? "",
            symbolName: "xmark.octagon.fill",
            tint: .red
        ) {
            Button("Dismiss") { viewModel.dismissError() }
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private func controls(_ viewModel: HomeViewModel) -> some View {
        @Bindable var viewModel = viewModel
        HStack(spacing: 16) {
            Text(services.settings.toggleShortcut.displayString)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .help("Hold this shortcut in any app and speak; release it to insert the text")

            Spacer()

            Picker("Mode", selection: $viewModel.dictationMode) {
                ForEach(DictationMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.symbolName)
                        .tag(mode)
                        .help(mode.summary)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(Text("Dictation mode"))
            .help(viewModel.dictationMode.summary)

            Button {
                viewModel.toggleDictation()
            } label: {
                Label(viewModel.primaryButtonTitle, systemImage: viewModel.primaryButtonSymbol)
                    .frame(minWidth: 130)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(viewModel.state.isActive ? .red : .accentColor)
            .disabled(!viewModel.isPrimaryButtonEnabled || viewModel.blockingIssue != nil)
            // The styled Label was reaching accessibility as an unnamed "button" —
            // useless to VoiceOver and to UI automation alike.
            .accessibilityLabel(Text(viewModel.primaryButtonTitle))
            // ⌘D from the keyboard; the global shortcut works even when unfocused.
            .keyboardShortcut("d", modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

#Preview("Ready") {
    HomeView()
        .environment(\.services, PreviewServiceContainer(speechEngines: StubSpeechEngineProvider.planned))
        .frame(width: 640, height: 440)
}

#Preview("Microphone denied") {
    HomeView()
        .environment(\.services, PreviewServiceContainer(permissions: StubPermissionService.microphoneDenied))
        .frame(width: 640, height: 440)
}

#Preview("No engine") {
    HomeView()
        .environment(\.services, PreviewServiceContainer())
        .frame(width: 640, height: 440)
}
