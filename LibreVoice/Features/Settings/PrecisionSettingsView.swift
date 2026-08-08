//
//  PrecisionSettingsView.swift
//  LibreVoice
//

import SwiftUI

/// Configures Precision mode: the local language model, how strongly it applies the
/// personal prompt, and how long it may stay in memory.
///
/// The screen is honest about state. Its header says plainly whether dictating in
/// Precision will actually use the model or fall back to rules only — readiness has three
/// parts (model, strength, prompt), and a user who satisfied two of them deserves to know
/// which one is missing rather than wonder why nothing changed.
struct PrecisionSettingsView: View {
    @Environment(\.services) private var services
    @State private var viewModel: PrecisionViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                Color.clear
            }
        }
        .task {
            let viewModel = viewModel ?? PrecisionViewModel(container: services)
            self.viewModel = viewModel
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func content(_ viewModel: PrecisionViewModel) -> some View {
        @Bindable var settings = viewModel.settings

        Form {
            statusSection(viewModel)
            modelSection(viewModel)
            WritingProfileSection()
            strengthSection(settings: settings)
            memorySection(settings: settings)
        }
        .formStyle(.grouped)
        .task { await viewModel.observe() }
    }

    // MARK: - Sections

    @ViewBuilder
    private func statusSection(_ viewModel: PrecisionViewModel) -> some View {
        Section {
            if viewModel.isEnhancementConfigured {
                Label(
                    "Precision dictation is enhanced by your local language model, following your personal prompt.",
                    systemImage: "checkmark.seal.fill"
                )
                .foregroundStyle(Color.accentColor)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        "Precision currently runs rules and terminology only. To enhance with a local model, all three are needed:",
                        systemImage: "info.circle"
                    )
                    requirement(
                        "A downloaded language model, selected below",
                        isMet: viewModel.settings.selectedLanguageModelID != nil
                    )
                    requirement(
                        "Style strength above zero",
                        isMet: viewModel.settings.styleStrength > 0
                    )
                    requirement(
                        "A personal prompt, below",
                        isMet: viewModel.hasWritingProfile
                    )
                }
                .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Everything on this screen runs on this Mac. Your text is never sent anywhere.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func requirement(_ title: LocalizedStringKey, isMet: Bool) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isMet ? Color.accentColor : .secondary)
        }
        .font(.callout)
        .padding(.leading, 22)
    }

    @ViewBuilder
    private func modelSection(_ viewModel: PrecisionViewModel) -> some View {
        Section {
            if viewModel.models.rows.isEmpty && viewModel.models.hasLoaded {
                ContentUnavailableView(
                    "No models available",
                    systemImage: "shippingbox",
                    description: Text("The model catalog is empty or couldn't be read.")
                )
            } else {
                ForEach(viewModel.models.rows) { row in
                    ModelRowView(
                        row: row,
                        isDefault: viewModel.models.selectedModelID == row.id,
                        onDownload: { viewModel.models.download(row.descriptor) },
                        onCancel: { viewModel.models.cancel(row.id) },
                        onRemove: { viewModel.models.remove(row.id) },
                        onSelect: { viewModel.models.selectAsDefault(row.id) }
                    )
                }
            }
        } header: {
            Text("Language model")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if viewModel.models.selectedModelID != nil {
                    Button("Stop using a language model") {
                        viewModel.models.clearSelection()
                    }
                    .buttonStyle(.link)
                }
                Text("Llama, Qwen and Gemma are interchangeable — pick whichever suits your language and Mac. Downloads are verified against a SHA-256 fingerprint before use.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func strengthSection(settings: AppSettings) -> some View {
        @Bindable var settings = settings
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Slider(value: $settings.styleStrength, in: 0...1, step: 0.25) {
                    Text("Style strength")
                } minimumValueLabel: {
                    Text(verbatim: "0%")
                } maximumValueLabel: {
                    Text(verbatim: "100%")
                }
                Text(Self.strengthLabel(for: settings.styleStrength))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Style strength")
        }
    }

    @ViewBuilder
    private func memorySection(settings: AppSettings) -> some View {
        @Bindable var settings = settings
        Section {
            Picker("Unload the model after", selection: $settings.languageModelUnloadTimeout) {
                Text("30 seconds").tag(TimeInterval(30))
                Text("45 seconds").tag(TimeInterval(45))
                Text("60 seconds").tag(TimeInterval(60))
                Text("2 minutes").tag(TimeInterval(120))
            }
        } header: {
            Text("Memory")
        } footer: {
            Text("The model loads only while improving text and is released after this much idle time, so it never sits in memory permanently.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private static func strengthLabel(for strength: Double) -> String {
        switch strength {
        case ..<0.125: String(localized: "Disabled — the language model is not used.")
        case ..<0.375: String(localized: "Light — only clear errors are fixed.")
        case ..<0.625: String(localized: "Balanced — corrections follow your prompt where they help.")
        case ..<0.875: String(localized: "Strong — wording and formatting actively follow your prompt.")
        default: String(localized: "Maximum — the text reads exactly as you write.")
        }
    }
}

#Preview {
    PrecisionSettingsView()
        .environment(\.services, PreviewServiceContainer())
        .frame(width: 620, height: 700)
}
