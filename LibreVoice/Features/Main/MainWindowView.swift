//
//  MainWindowView.swift
//  LibreVoice
//

import SwiftUI

/// A destination in the main window's sidebar.
///
/// An enum rather than free-form navigation state: the set of screens is fixed and
/// known, so making it a type means an unhandled destination is a compiler error, and
/// the sidebar and the detail pane cannot drift apart.
///
/// Every screen the app has lives here, settings included. A separate Settings window
/// is the Mac default, but for an app this small it meant two windows to manage, two
/// places to look, and a preferences pane the user had to know to open with ⌘,. One
/// window with a sidebar puts everything one click away — and ⌘, still works, it just
/// selects a section here rather than opening something new.
enum MainDestination: String, CaseIterable, Identifiable, Hashable {
    case dictate
    case models
    case precision
    case general
    case privacy
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictate: String(localized: "Dictate")
        case .models: String(localized: "Models")
        case .precision: String(localized: "Precision")
        case .general: String(localized: "General")
        case .privacy: String(localized: "Privacy")
        case .activity: String(localized: "Activity")
        }
    }

    var symbolName: String {
        switch self {
        case .dictate: "mic"
        case .models: "arrow.down.circle"
        case .precision: "scope"
        case .general: "gearshape"
        case .privacy: "hand.raised"
        case .activity: "list.bullet.rectangle"
        }
    }

    /// Which group the item sits in, so the sidebar reads as "the thing" and then
    /// "everything about the thing" rather than one undifferentiated list.
    enum Group: String, CaseIterable, Identifiable {
        case dictation
        case setup
        case about

        var id: String { rawValue }

        var title: String? {
            switch self {
            case .dictation: nil // The first item needs no heading above it.
            case .setup: String(localized: "Setup")
            case .about: String(localized: "About")
            }
        }

        var destinations: [MainDestination] {
            switch self {
            case .dictation: [.dictate]
            case .setup: [.models, .precision, .general]
            case .about: [.privacy, .activity]
            }
        }
    }
}

/// The app's main — and only — window.
///
/// `NavigationSplitView` is the native shape for this: it gives a real sidebar, full
/// keyboard navigation and the standard collapse behaviour for free, none of which a
/// hand-rolled `HStack` would.
struct MainWindowView: View {
    @Environment(\.services) private var services

    /// Bound to the app's shared selection so ⌘, can steer it from the menu bar.
    @Binding var selection: MainDestination

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(MainDestination.Group.allCases) { group in
                    Section {
                        ForEach(group.destinations) { destination in
                            NavigationLink(value: destination) {
                                Label(destination.title, systemImage: destination.symbolName)
                            }
                        }
                    } header: {
                        if let title = group.title {
                            Text(title)
                        }
                    }
                }
            }
            // Wide enough for the longest label in the longest language: "Конфиденциальность"
            // is half again the width of "Privacy", and a sidebar item that truncates to
            // "Конфиденциально…" is a sidebar item nobody can scan.
            .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 260)
            .safeAreaInset(edge: .bottom) {
                statusFooter
            }
        } detail: {
            detail
                .navigationTitle(selection.title)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .dictate: HomeView()
        case .models: ModelManagementView()
        case .precision: PrecisionSettingsView()
        case .general: GeneralSettingsView()
        case .privacy: PrivacySettingsView()
        case .activity: ActivityView()
        }
    }

    /// A persistent reminder of what dictation is doing, visible from every screen.
    @ViewBuilder
    private var statusFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                StatusIndicator(state: services.dictation.state)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

#Preview {
    @Previewable @State var selection: MainDestination = .dictate
    return MainWindowView(selection: $selection)
        .environment(\.services, PreviewServiceContainer(speechEngines: StubSpeechEngineProvider.planned))
        .frame(width: 900, height: 560)
}
