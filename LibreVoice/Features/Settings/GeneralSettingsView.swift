//
//  GeneralSettingsView.swift
//  LibreVoice
//

import SwiftUI

/// Everything the user adjusts day to day: microphone, language, behaviour, shortcuts.
///
/// Shortcuts used to be their own screen. With one read-only row and a short list of
/// in-app keys, a whole section of the sidebar bought nothing — a screen that holds a
/// single fact is a screen the user has to go looking for.
struct GeneralSettingsView: View {
    @Environment(\.services) private var services
    @State private var devices: [AudioInputDevice] = []

    private var settings: AppSettings { services.settings }

    var body: some View {
        Form {
            Section {
                Picker("Microphone", selection: Bindable(settings).inputDeviceID) {
                    Text("System Default").tag(String?.none)
                    ForEach(devices) { device in
                        Text(device.name).tag(String?.some(device.id))
                    }
                }

                Picker("Language", selection: Bindable(settings).locale) {
                    Text("System Language").tag(Locale?.none)
                    ForEach(Self.commonLocales, id: \.identifier) { locale in
                        Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                            .tag(Locale?.some(locale))
                    }
                }
            } header: {
                Text("Input")
            }

            Section {
                Toggle("Type text into the frontmost app", isOn: Bindable(settings).insertTextAutomatically)
                    .help("When off, text stays in LibreVoice and you copy it yourself")

                Toggle("Play a sound when dictation starts and stops", isOn: Bindable(settings).playFeedbackSounds)

                Toggle("Show only in the menu bar", isOn: Bindable(settings).menuBarOnly)
                    .help("Hides the Dock icon; LibreVoice lives in the menu bar")

                Toggle("Show icon in the menu bar", isOn: Bindable(settings).showMenuBarIcon)
                    // Forced on while the Dock icon is hidden — otherwise there would be no
                    // way left to reach the app.
                    .disabled(settings.menuBarOnly)
            } header: {
                Text("Behaviour")
            }

            PermissionsSection()

            Section {
                if !services.hotkeyStatus.isRegistered {
                    Label(
                        "Another app is already using this combination, so holding it won't start dictation. Quit that app, or use ⌘D from this window.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }

                LabeledContent("Hold to dictate") {
                    shortcutChip(settings.toggleShortcut.displayString)
                }
                LabeledContent("Start / stop dictation", value: "⌘D")
                LabeledContent("Close window", value: "⌘W")
            } header: {
                Text("Shortcuts")
            } footer: {
                Label(
                    "Hold it down in any app and speak; release it and the text is typed at your cursor. Customising the combination isn't implemented yet.",
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            }
        }
        .formStyle(.grouped)
        .task {
            devices = await services.audioCapture.availableInputDevices()
        }
    }


    private func shortcutChip(_ text: String) -> some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: .rect(cornerRadius: 5))
            .accessibilityLabel("Current shortcut")
            .accessibilityValue(text)
    }

    /// A short list of languages to offer up front.
    ///
    /// Not every locale macOS knows: that list runs to hundreds and would be a worse
    /// experience than a handful of likely ones. Which languages actually work is a
    /// property of the chosen engine, so this stays a convenience rather than a promise.
    private static let commonLocales: [Locale] = [
        "en-US", "en-GB", "ru-RU", "de-DE", "fr-FR", "es-ES", "it-IT", "pt-BR",
        "nl-NL", "pl-PL", "uk-UA", "ja-JP", "ko-KR", "zh-CN",
    ].map(Locale.init(identifier:))
}

#Preview {
    GeneralSettingsView()
        .environment(\.services, PreviewServiceContainer())
        .frame(width: 520)
}
