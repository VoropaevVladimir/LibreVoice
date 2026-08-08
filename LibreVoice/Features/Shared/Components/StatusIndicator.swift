//
//  StatusIndicator.swift
//  LibreVoice
//

import SwiftUI

/// A dot and a label describing what dictation is doing.
///
/// The dot alone would be prettier and would fail every accessibility test worth
/// passing: colour is not information anyone is guaranteed to perceive. Shape, text and
/// an accessibility label all carry the same state, so nothing depends on seeing red.
struct StatusIndicator: View {
    let state: DictationState

    /// Whether to show the text label beside the dot.
    var showsLabel = true

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.tint)
                .frame(width: 8, height: 8)
                .overlay {
                    // A ring while active, so the state is distinguishable without colour.
                    if state.isActive {
                        Circle()
                            .stroke(state.tint.opacity(0.35), lineWidth: 4)
                            .scaleEffect(1.8)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: state)

            if showsLabel {
                Text(state.label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dictation status")
        .accessibilityValue(state.label)
    }
}

extension DictationState {
    /// A short description of this state, shown to the user and read by VoiceOver.
    var label: String {
        switch self {
        case .idle: String(localized: "Ready")
        case .preparing: String(localized: "Starting…")
        case .listening: String(localized: "Listening")
        case .finishing: String(localized: "Finishing…")
        case .failed: String(localized: "Error")
        }
    }

    /// The colour associated with this state.
    ///
    /// Semantic colours from the system palette, so they adapt to Dark Mode, Increase
    /// Contrast, and the user's accent colour without a second set of values.
    var tint: Color {
        switch self {
        case .idle: .secondary
        case .preparing, .finishing: .orange
        case .listening: .red
        case .failed: .red
        }
    }

    /// The SF Symbol representing this state.
    var symbolName: String {
        switch self {
        case .idle: "mic"
        case .preparing: "mic.badge.plus"
        case .listening: "mic.fill"
        case .finishing: "waveform"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    /// A tiny badge shown beside the LV mark in the menu bar, or `nil` when at rest.
    ///
    /// The menu bar mark is the wordmark, so state can no longer be carried by the icon
    /// itself changing shape. It moves to this badge rather than to colour: the menu bar
    /// is monochrome, and a status only a sighted user with colour vision can read is not
    /// a status. Resting shows nothing at all — an icon that always wears a badge trains
    /// people to stop seeing it.
    var menuBarBadgeSymbol: String? {
        switch self {
        case .idle: nil
        case .preparing: "circle.dotted"
        case .listening: "circle.fill"
        case .finishing: "ellipsis"
        case .failed: "exclamationmark"
        }
    }
}

#Preview("States") {
    VStack(alignment: .leading, spacing: 12) {
        StatusIndicator(state: .idle)
        StatusIndicator(state: .preparing)
        StatusIndicator(state: .listening)
        StatusIndicator(state: .finishing)
        StatusIndicator(state: .failed(.noEngineAvailable))
    }
    .padding()
}
