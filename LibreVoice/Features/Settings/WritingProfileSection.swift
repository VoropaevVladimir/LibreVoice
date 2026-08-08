//
//  WritingProfileSection.swift
//  LibreVoice
//

import SwiftUI

/// The personal prompt editor, shaped to sit inside the Precision screen's `Form`.
///
/// It used to be its own sidebar entry. That separated the prompt from the model it
/// instructs and from the strength slider that scales it — three parts of one feature in
/// two places, and one more item to scan. Here everything Precision needs is on the screen
/// called Precision.
///
/// `TextEditor` rather than a hand-rolled `NSTextView`: undo, redo, copy, paste, spell
/// checking and find all arrive for free and behave the way every other Mac app behaves.
struct WritingProfileSection: View {
    @Environment(\.services) private var services
    @State private var viewModel: WritingProfileViewModel?
    @State private var isConfirmingReset = false

    /// Tall enough for a real prompt to be read and edited, short enough that the model
    /// list above it stays reachable without scrolling past a wall of text.
    private let editorHeight: CGFloat = 220

    var body: some View {
        Section {
            if let viewModel {
                content(viewModel)
            }
        } header: {
            Text("Writing Profile")
        } footer: {
            Text("This prompt is given to the local language model. It teaches the model how you write — nothing else is sent with it, and it never leaves this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .task {
            let viewModel = viewModel ?? WritingProfileViewModel(container: services)
            self.viewModel = viewModel
            await viewModel.load()
        }
        .onDisappear {
            // A debounced save still pending when the screen goes away would be lost.
            Task { [viewModel] in await viewModel?.flush() }
        }
        .confirmationDialog(
            "Reset the prompt to the LibreVoice default?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { viewModel?.resetToDefault() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current prompt will be replaced. Copy it first if you want to keep it.")
        }
    }

    @ViewBuilder
    private func content(_ viewModel: WritingProfileViewModel) -> some View {
        @Bindable var viewModel = viewModel

        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $viewModel.prompt)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(height: editorHeight)
                .padding(6)
                .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 1)
                }
                .accessibilityLabel("Personal prompt")

            HStack(spacing: 12) {
                Button {
                    viewModel.copyGeneratorTemplate()
                } label: {
                    Label("Generate Personal Prompt", systemImage: "sparkles")
                }
                .help("Copies an instruction for an external AI. LibreVoice contacts nothing.")

                Spacer()

                statusLabel(viewModel)

                Text("\(viewModel.characterCount) / \(viewModel.characterLimit)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(
                        viewModel.characterCount > viewModel.characterLimit ? .red : .secondary
                    )
            }

            HStack(spacing: 12) {
                Button("Copy") { viewModel.copyPrompt() }
                Button("Paste") { viewModel.pastePrompt() }
                Button("Reset to default") { isConfirmingReset = true }
                    .disabled(!viewModel.isCustomised)
            }

            Text("Copy the instruction, paste it into ChatGPT, Claude, Gemini or Grok together with your own writing, then paste the prompt it returns back here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusLabel(_ viewModel: WritingProfileViewModel) -> some View {
        switch viewModel.status {
        case .idle:
            EmptyView()
        case .saving:
            Text("Saving…").font(.caption).foregroundStyle(.secondary)
        case .saved:
            Label("Saved", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }
}

#Preview {
    Form { WritingProfileSection() }
        .formStyle(.grouped)
        .environment(\.services, PreviewServiceContainer())
        .frame(width: 640, height: 560)
}
