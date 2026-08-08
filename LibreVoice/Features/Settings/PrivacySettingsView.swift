//
//  PrivacySettingsView.swift
//  LibreVoice
//

import SwiftUI

/// States plainly what LibreVoice does and does not do with the user's data.
///
/// Every item here is a fact about the code, not a marketing promise, and each is
/// checkable: the network claim by `nm` on the binary or Little Snitch, the logging
/// claim on the Activity screen, the audio claim in `AVAudioEngineCaptureService`.
/// A privacy page that cannot be verified is just an advertisement.
struct PrivacySettingsView: View {
    @Environment(\.services) private var services

    var body: some View {
        Form {
            Section {
                PrivacyClaim(
                    symbolName: "mic.slash",
                    title: "Your voice never leaves this Mac",
                    detail: "Audio is transcribed on-device and never uploaded. The network is used for one thing only: downloading the speech models you choose, over HTTPS and verified by checksum. Those downloads carry no audio, no transcripts, and nothing that identifies you."
                )

                PrivacyClaim(
                    symbolName: "chart.bar.xaxis",
                    title: "No analytics, no telemetry",
                    detail: "Nothing is measured, counted, or reported. There is no server to report to."
                )

                PrivacyClaim(
                    symbolName: "externaldrive.badge.xmark",
                    title: "Your speech is never stored",
                    detail: "Audio is processed and discarded. Transcripts live in memory until the session ends. The only thing written to disk is the speech models you download — and you can remove those any time."
                )

                PrivacyClaim(
                    symbolName: "text.append",
                    title: "Logs stay on this Mac",
                    detail: "Log records never contain what you said, are kept in memory only, and you can read every one of them on the Activity screen."
                )
            } header: {
                Text("What LibreVoice Does")
            }

            Section {
                LabeledContent("Version") {
                    Text(Self.versionString)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Licence") {
                    Text("MIT — free and open source")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("About")
            } footer: {
                Text("Because the source is open, none of the claims above have to be taken on trust.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }

            Section {
                Button("Reset All Settings…", role: .destructive) {
                    services.settings.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// One verifiable statement about the app's behaviour.
private struct PrivacyClaim: View {
    let symbolName: String
    // `LocalizedStringKey`, not `String`, so the literal titles and details at the call
    // sites localize — a `String` would be rendered verbatim.
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .foregroundStyle(.green)
                .font(.title3)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    PrivacySettingsView()
        .environment(\.services, PreviewServiceContainer())
        .frame(width: 520, height: 560)
}
