//
//  MenuBarContentView.swift
//  LibreVoice
//

import SwiftUI

/// The panel shown when the menu bar icon is clicked.
///
/// This is the app's real interface. A dictation tool is used *while working in another
/// app*, so the main window is somewhere you visit occasionally and the menu bar is
/// where you actually live. It is kept to what can be answered at a glance: what is the
/// state, start or stop it, and how to get to everything else.
struct MenuBarContentView: View {
    @Environment(\.services) private var services
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            Button {
                services.dictation.toggle()
            } label: {
                Label(
                    services.dictation.state.canStart ? "Start Dictation" : "Stop Dictation",
                    systemImage: services.dictation.state.canStart ? "mic.fill" : "stop.fill"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(services.dictation.state.isActive ? .red : .accentColor)

            if !services.dictation.transcript.isEmpty {
                transcriptPreview
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                MenuBarRow(title: "Open LibreVoice", symbolName: "macwindow") {
                    openWindow(id: WindowIdentifier.main)
                    NSApp.activate(ignoringOtherApps: true)
                }

                MenuBarRow(title: "Settings…", symbolName: "gearshape") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }

                MenuBarRow(title: "Quit LibreVoice", symbolName: "power") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("LibreVoice")
                    .font(.headline)
                StatusIndicator(state: services.dictation.state)
            }

            Spacer()

            AudioLevelMeter(
                level: services.dictation.audioLevel,
                isActive: services.dictation.state == .listening
            )
        }
    }

    @ViewBuilder
    private var transcriptPreview: some View {
        Text(services.dictation.transcript.displayText)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
    }
}

/// A row in the menu bar panel, styled like a menu item rather than a button.
private struct MenuBarRow: View {
    // A `LocalizedStringKey`, not a `String`, so the literal titles at the call sites are
    // localized automatically — a plain `String` would render verbatim.
    let title: LocalizedStringKey
    let symbolName: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbolName)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(
                    isHovering ? Color.accentColor.opacity(0.15) : .clear,
                    in: .rect(cornerRadius: 5)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// The menu bar icon itself: the LV wordmark, matching the app icon.
///
/// Letters rather than a microphone glyph, so the row of menu bar icons carries the
/// app's identity instead of a symbol a dozen other utilities also use. The rounded
/// heavy face is the one the app icon is drawn in, which is what makes the two read as
/// the same product at a glance.
///
/// State still changes the *shape* of what is drawn — via a small badge — and never only
/// its colour: the menu bar is monochrome, so a colour-only status would be no status at
/// all. `verbatim` because "LV" is a mark, not a word to be translated.
struct MenuBarLabel: View {
    let state: DictationState

    var body: some View {
        HStack(spacing: 2) {
            Text(verbatim: "LV")
                .font(.system(size: 13, weight: .heavy, design: .rounded))

            if let badge = state.menuBarBadgeSymbol {
                Image(systemName: badge)
                    .font(.system(size: 7, weight: .bold))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("LibreVoice")
        .accessibilityValue(state.label)
    }
}

#Preview {
    MenuBarContentView()
        .environment(\.services, PreviewServiceContainer())
}
