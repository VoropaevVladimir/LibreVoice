//
//  CapsuleView.swift
//  LibreVoice
//

import SwiftUI

/// The floating capsule's content: liquid glass and the Metal wave, and nothing else.
///
/// It shows no text on purpose. The capsule sits over whatever the user is working in,
/// and its whole job is to answer one question at a glance — *is it hearing me?* — from
/// peripheral vision. Words there compete with the words being dictated, ask to be read
/// at the exact moment attention belongs elsewhere, and put the transcript on screen
/// above whatever else is open. The wave answers the question without being read.
struct CapsuleView: View {
    let coordinator: ExperienceCoordinator

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)

            MetalWaveView(coordinator: coordinator, isRendering: coordinator.state.showsCapsule)
                .clipShape(Capsule(style: .continuous))
        }
        .overlay {
            // A hairline of the theme colour: enough to read the mode at a glance,
            // subtle enough to stay out of the way.
            Capsule(style: .continuous)
                .strokeBorder(themeColor.opacity(0.35), lineWidth: 1)
        }
        .compositingGroup()
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("LibreVoice"))
        .accessibilityValue(Text(accessibilityDescription))
    }

    private var themeColor: Color {
        Color(
            red: Double(coordinator.tint.x),
            green: Double(coordinator.tint.y),
            blue: Double(coordinator.tint.z)
        )
    }

    /// The capsule shows no text, so this is the only description of its state — which
    /// makes it the whole experience for anyone using VoiceOver.
    private var accessibilityDescription: String {
        switch coordinator.state {
        case .idle: String(localized: "Idle")
        case .preparing: String(localized: "Getting ready")
        case .listening: String(localized: "Listening")
        case .thinking: String(localized: "Recognising your speech")
        case .typing: String(localized: "Inserting text")
        case .completed: String(localized: "Done")
        case .error: String(localized: "Something went wrong")
        }
    }
}
