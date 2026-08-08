//
//  NoticeBanner.swift
//  LibreVoice
//

import SwiftUI

/// An inline message explaining a problem, with the actions that resolve it.
///
/// Used instead of an alert. A modal alert would be the reflex, but these messages are
/// conditions rather than events — the microphone is *still* not granted — and a banner
/// can say so persistently without a dialog demanding to be dismissed each time the
/// screen appears.
struct NoticeBanner<Actions: View>: View {
    let title: String
    let message: String
    let symbolName: String
    let tint: Color

    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .foregroundStyle(tint)
                .font(.title3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)

                if !message.isEmpty {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    actions()
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(tint.opacity(0.25))
        }
        // Combined so VoiceOver reads the problem as one statement rather than three
        // disconnected fragments, while the buttons stay individually reachable.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityHint(message)
    }
}

#Preview {
    VStack(spacing: 12) {
        NoticeBanner(
            title: "Microphone access needed",
            message: "LibreVoice can't hear you until microphone access is turned on.",
            symbolName: "exclamationmark.triangle.fill",
            tint: .orange
        ) {
            Button("Open System Settings…") {}
        }

        NoticeBanner(
            title: "Dictation failed",
            message: "No speech engine is available.",
            symbolName: "xmark.octagon.fill",
            tint: .red
        ) {
            Button("Dismiss") {}
        }
    }
    .padding()
    .frame(width: 460)
}
