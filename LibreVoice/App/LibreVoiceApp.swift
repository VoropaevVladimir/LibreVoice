//
//  LibreVoiceApp.swift
//  LibreVoice
//

import AppKit
import SwiftUI

/// Keeps LibreVoice running when its window is closed.
///
/// Closing the window is not quitting. This app is driven by a global shortcut from
/// inside whatever the user is actually working in, so the window is somewhere you
/// visit — not the app itself. Without this, SwiftUI ends the process with the last
/// window and the shortcut would go quiet with no indication why.
///
/// Quitting stays deliberate: the Quit item in the menu bar (and ⌘Q when the Dock icon
/// is shown). The menu bar item is what brings the window back.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// Stable identifiers for the app's windows.
///
/// String literals scattered across `openWindow(id:)` calls are a typo waiting to fail
/// silently at run time; these fail at compile time instead.
enum WindowIdentifier {
    static let main = "librevoice.main"
}

/// LibreVoice: offline voice dictation for macOS.
///
/// The scene layout mirrors how the app is actually used:
///
/// - A `Window` rather than a `WindowGroup`, because a dictation app has exactly one
///   main window. `WindowGroup` would let ⌘N spawn a second one, each showing the same
///   single dictation session.
/// - A `MenuBarExtra` for the everyday path, since dictation happens while working in
///   some other app.
///
/// There is deliberately **no `Settings` scene**. The standard Mac shape is a separate
/// preferences window, but for an app with this few screens it split a small interface
/// across two windows and hid half of it behind a keystroke the user had to know. Every
/// screen now lives in the one window's sidebar; ⌘, is kept working by selecting the
/// settings section instead of opening anything.
///
/// The app owns exactly one ``AppEnvironment`` and injects it into every scene. That is
/// the only global-ish thing in the project, and it is passed explicitly rather than
/// reached for through a singleton.
@main
struct LibreVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment()

    /// Which sidebar section the main window is showing. Held here, not inside the
    /// window, so menu commands can steer it.
    @State private var selection: MainDestination = .dictate

    var body: some Scene {
        Window("LibreVoice", id: WindowIdentifier.main) {
            MainWindowView(selection: $selection)
                .environment(\.services, environment)
                .task {
                    // Registers speech engines and binds the global shortcut. Runs once:
                    // the main window is a single window, so its task is not repeated.
                    await environment.start()
                }
        }
        .defaultSize(width: 900, height: 560)
        .windowToolbarStyle(.unified)
        .commands {
            DictationCommands(environment: environment, selection: $selection)
        }

        MenuBarExtra(isInserted: Bindable(environment.settings).showMenuBarIcon) {
            MenuBarContentView()
                .environment(\.services, environment)
        } label: {
            MenuBarLabel(state: environment.dictation.state)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menu bar commands, so dictation and the settings sections are reachable from the
/// menus and the keyboard.
///
/// A keyboard-first app has to put its main action in a menu: that is what makes it
/// discoverable, scriptable, and reachable by anyone navigating with the keyboard alone.
struct DictationCommands: Commands {
    let environment: AppEnvironment
    @Binding var selection: MainDestination

    var body: some Commands {
        // Replaces the app-menu Settings item that the removed `Settings` scene used to
        // provide, so ⌘, still lands somewhere sensible instead of doing nothing.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                selection = .general
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandMenu("Dictation") {
            Button(environment.dictation.state.canStart ? "Start Dictation" : "Stop Dictation") {
                environment.dictation.toggle()
            }
            .keyboardShortcut("d", modifiers: .command)

            Divider()

            Button("Models") { selection = .models }
            Button("Precision") { selection = .precision }
            Button("Activity") { selection = .activity }

            Divider()

            Text("Global shortcut: \(environment.settings.toggleShortcut.displayString)")
        }
    }
}
