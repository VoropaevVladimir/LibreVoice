//
//  HotkeyShortcut.swift
//  LibreVoice
//

import Foundation

/// A key combination that triggers a LibreVoice action from anywhere in the system.
nonisolated struct HotkeyShortcut: Sendable, Hashable, Codable {
    /// A set of modifier keys.
    ///
    /// An `OptionSet` rather than `NSEvent.ModifierFlags` so `Core` stays free of
    /// AppKit and the value can be `Codable` for storage in settings.
    nonisolated struct Modifiers: OptionSet, Sendable, Hashable, Codable {
        let rawValue: UInt32

        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)
    }

    /// The virtual key code of the non-modifier key, as defined by Carbon's
    /// `kVK_` constants.
    let keyCode: UInt16

    /// The modifiers that must be held.
    let modifiers: Modifiers

    init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// LibreVoice's out-of-the-box shortcut: hold ⌥Space to dictate.
    ///
    /// Space suits push-to-talk: it is the biggest key on the board, comfortable to
    /// *hold* with a thumb while ⌥ sits under a finger — a chord you can keep down for a
    /// whole sentence without thinking about it. macOS leaves ⌥Space unbound by default
    /// (Spotlight is ⌘Space, input sources are ⌃Space), and while registered as a global
    /// hotkey it no longer types the non-breaking space it would otherwise produce.
    ///
    /// Earlier default ⌥⌘D was a trap: it is the system's own "Turn Dock Hiding On/Off"
    /// shortcut, and the system claims it first — found the hard way, as a dictation
    /// hotkey that never fired.
    static let defaultToggleDictation = HotkeyShortcut(
        keyCode: 0x31, // kVK_Space
        modifiers: [.option]
    )

    /// The shortcut written the way macOS shows it, for example `⌥⌘D`.
    ///
    /// Modifier order follows Apple's convention (⌃⌥⇧⌘), which is what people expect
    /// to read in a menu.
    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += Self.keyName(for: keyCode)
        return result
    }

    /// A printable name for a virtual key code.
    ///
    /// Covers the keys a dictation shortcut plausibly uses. Anything else is shown as
    /// its numeric code rather than guessed at, because a wrong key name in the UI is
    /// worse than an ugly one.
    private static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0x00: "A"
        case 0x01: "S"
        case 0x02: "D"
        case 0x03: "F"
        case 0x05: "G"
        case 0x08: "C"
        case 0x09: "V"
        case 0x0B: "B"
        case 0x0C: "Q"
        case 0x0D: "W"
        case 0x0E: "E"
        case 0x0F: "R"
        case 0x11: "T"
        case 0x1F: "O"
        case 0x23: "P"
        case 0x31: "Space"
        case 0x24: "↩"
        case 0x35: "⎋"
        case 0x60: "F5"
        case 0x61: "F6"
        case 0x62: "F7"
        case 0x63: "F3"
        case 0x64: "F8"
        case 0x65: "F9"
        default: "Key \(keyCode)"
        }
    }
}
