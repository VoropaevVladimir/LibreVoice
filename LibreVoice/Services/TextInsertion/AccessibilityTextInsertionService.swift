//
//  AccessibilityTextInsertionService.swift
//  LibreVoice
//

import AppKit
import ApplicationServices
import Foundation

/// Types transcribed text into the frontmost app by pasting it.
///
/// ## Why pasting, and not the "proper" Accessibility write
///
/// The obvious approach is to set the focused element's `kAXSelectedTextAttribute`,
/// which asks the app's own text system to replace the selection. It is tidier in
/// principle — undo and autocorrect behave exactly as if the user had typed — and it was
/// how this worked first.
///
/// It had to go, because a great many applications **accept that write, report
/// `.success`, and do nothing at all.** Electron apps, browsers, editors with custom
/// text engines: they expose an accessibility tree that looks writable and silently
/// discards what is written to it. There is no reliable way to detect this from the
/// outside — `AXUIElementIsAttributeSettable` lies in exactly the same cases — so the
/// code could not tell "inserted" from "swallowed", and reported success either way.
/// The symptom was text that landed in one or two applications and vanished in every
/// other one, with nothing in the logs to show for it.
///
/// Pasting works wherever ⌘V works, which is everywhere a text field exists. The costs
/// are real but small and are paid for here: the clipboard is borrowed rather than
/// taken (its previous contents are restored afterwards), and the insertion appears in
/// the target app's undo stack as a paste rather than as typing.
///
/// Deliberately *not* main-actor isolated. The waits below must not block LibreVoice's
/// interface, and `NSPasteboard`/`CGEvent` are safe to use off the main thread.
nonisolated final class AccessibilityTextInsertionService: TextInsertionService {
    private let logger: any Logger

    /// How long the target application is given to read the clipboard before the user's
    /// own contents are put back.
    ///
    /// Generous on purpose: a slow or busy application that reads the clipboard late
    /// would otherwise paste whatever was restored in the meantime, which is a far
    /// nastier bug than a clipboard that stays borrowed a moment longer than needed.
    private let pasteSettlingTime: Duration = .milliseconds(900)

    /// The virtual key code for `V`.
    private static let vKeyCode: CGKeyCode = 0x09

    init(logger: any Logger = NullLogger()) {
        self.logger = logger
    }

    // MARK: - TextInsertionService

    func isAvailable() async -> Bool {
        AXIsProcessTrusted()
    }

    func insert(_ text: String) async throws {
        guard !text.isEmpty else { return }

        guard AXIsProcessTrusted() else {
            copyToPasteboard(text)
            throw TextInsertionError.accessibilityPermissionDenied
        }

        // Dictating with LibreVoice's own window in front is a real flow (the button,
        // rather than the hotkey). Pasting into ourselves would put the text in whatever
        // control happens to be focused here, which is never what was meant — and the
        // words are already on screen in the transcript.
        let target = NSWorkspace.shared.frontmostApplication
        if target?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            copyToPasteboard(text)
            logger.debug("LibreVoice is frontmost; text copied to the clipboard.", category: .textInsertion)
            return
        }

        // Named in the log because "it works in one app and not another" is the failure
        // this subsystem actually has, and the app's name is the first thing worth
        // knowing about it. The text itself is never logged.
        let targetName = target?.localizedName ?? "an unknown app"

        let pasteboard = NSPasteboard.general
        let saved = savedContents(of: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        guard postPasteKeystroke() else {
            // The keystroke could not be synthesised; leave the text on the clipboard so
            // nothing the user said is lost, and say so.
            logger.error("Couldn't synthesise ⌘V for \(targetName).", category: .textInsertion)
            throw TextInsertionError.insertionFailed(reason: Self.keystrokeFailureReason)
        }

        logger.debug("Pasted \(text.count) characters into \(targetName).", category: .textInsertion)

        try? await Task.sleep(for: pasteSettlingTime)
        restore(saved, to: pasteboard, ifUnchangedFrom: ourChangeCount)
    }

    // MARK: - Pasting

    /// Posts ⌘V to the system, as though the user had pressed it.
    ///
    /// - Returns: `false` if the events could not be created at all.
    private func postPasteKeystroke() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: false)
        else { return false }

        // Only Command. Any modifier the user still happens to be holding — Option, from
        // the ⌥Space shortcut they just let go of — would otherwise combine into a
        // different command entirely (⌥⌘V is "Paste and Match Style" in many apps).
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    // MARK: - Borrowing the clipboard

    /// Everything currently on the pasteboard, deeply copied so it survives being cleared.
    private func savedContents(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { contents[type] = data }
            }
            return contents
        }
    }

    /// Puts the user's clipboard back, unless they have copied something since.
    ///
    /// The change-count check matters: someone who hits ⌘C while the paste is settling
    /// would otherwise have their new clipboard silently replaced by the old one.
    private func restore(
        _ saved: [[NSPasteboard.PasteboardType: Data]],
        to pasteboard: NSPasteboard,
        ifUnchangedFrom changeCount: Int
    ) {
        guard pasteboard.changeCount == changeCount, !saved.isEmpty else { return }

        pasteboard.clearContents()
        pasteboard.writeObjects(saved.map { contents in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        })
    }

    /// Leaves the text on the clipboard when it cannot be inserted, so it is never lost.
    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static let keystrokeFailureReason = "the paste keystroke couldn't be synthesised"
}
