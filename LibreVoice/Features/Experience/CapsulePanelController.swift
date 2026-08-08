//
//  CapsulePanelController.swift
//  LibreVoice
//

import AppKit
import SwiftUI

/// Owns the floating capsule window.
///
/// The window characteristics are the product requirements, each one deliberate:
///
/// - **`.nonactivatingPanel`** — appearing must never steal focus from the app the user
///   is dictating into; stolen focus would send the text to the wrong place.
/// - **`.statusBar` level + top-centre placement** — the capsule sits against the top
///   edge, visually joining the MacBook notch; on external displays it stays centred at
///   the same edge.
/// - **`ignoresMouseEvents`** — the capsule is pure display in v1; clicks fall through
///   to whatever is beneath it.
/// - **No shadow, clear background** — the SwiftUI capsule shape *is* the window; a
///   rectangular shadow around a transparent window would give the frame away.
/// - **`.canJoinAllSpaces` + `.fullScreenAuxiliary`** — dictation happens wherever the
///   user is, including over full-screen apps.
@MainActor
final class CapsulePanelController {
    private let panel: NSPanel

    /// Capsule dimensions: a discreet pill, closer to a menu-bar item than a window.
    ///
    /// Small enough to ignore while working, large enough that the wave still reads as a
    /// wave — below roughly 24pt tall the crest and its bloom stop being distinguishable.
    private static let size = NSSize(width: 168, height: 28)

    /// Gap between the menu bar's bottom edge and the capsule.
    private static let topInset: CGFloat = 5

    init(coordinator: ExperienceCoordinator) {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.alphaValue = 0

        let host = NSHostingView(rootView: CapsuleView(coordinator: coordinator))
        host.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = host
    }

    /// Slides the capsule out of the notch, or back into it.
    ///
    /// The capsule does not appear, it *emerges*: it starts tucked entirely behind the
    /// menu bar and travels down into place while fading in, then retreats the same way.
    /// Position and opacity are animated together — a fade alone reads as a popup, and
    /// scaling would read as a notification. Nothing about it should feel like a window
    /// being shown; it should feel like part of the hardware waking up.
    func setVisible(_ visible: Bool) {
        if visible {
            position()
            // Start from behind the menu bar so the first frame is already off-screen,
            // otherwise the capsule flashes at its final position before moving.
            if panel.alphaValue == 0 {
                panel.setFrameOrigin(hiddenOrigin)
            }
            panel.orderFrontRegardless()
        }

        let destination = visible ? visibleOrigin : hiddenOrigin

        NSAnimationContext.runAnimationGroup { context in
            context.duration = visible ? 0.50 : 0.32
            // Out of the notch: decelerating, like something settling into place.
            // Back into it: accelerating away, so the eye lets go of it sooner.
            context.timingFunction = CAMediaTimingFunction(
                name: visible ? .easeOut : .easeIn
            )
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = visible ? 1 : 0
            panel.animator().setFrameOrigin(destination)
        } completionHandler: { [panel] in
            if !visible {
                Task { @MainActor in
                    if panel.alphaValue == 0 { panel.orderOut(nil) }
                }
            }
        }
    }

    /// Puts the capsule at its resting place for the current screen.
    private func position() {
        panel.setFrameOrigin(visibleOrigin)
    }

    /// The screen the user is working on.
    ///
    /// `NSScreen.main` is the screen with the key window — where attention is — which is
    /// also the right place on multi-display setups.
    private var activeScreen: NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }

    /// Where the capsule rests: horizontally centred, just below the menu bar.
    ///
    /// `visibleFrame`, not `frame`: on notched MacBooks the top band of `frame` is the
    /// notch itself, where the webcam lives — an early version parked the capsule
    /// exactly over the camera. The visible frame's top edge starts under the menu bar,
    /// and therefore under the notch, on every display.
    private var visibleOrigin: NSPoint {
        guard let screen = activeScreen else { return .zero }
        let visible = screen.visibleFrame
        return NSPoint(
            x: visible.midX - Self.size.width / 2,
            y: visible.maxY - Self.size.height - Self.topInset
        )
    }

    /// Where the capsule hides: entirely above the *physical* top of the screen, so its
    /// whole body is genuinely off-display and it has real distance to travel down.
    ///
    /// `frame.maxY`, not `visibleFrame.maxY`: the capsule panel sits at `.statusBar`
    /// level, which draws *over* the menu bar rather than behind it. Parked at the menu
    /// bar's lower edge it would already be fully visible, so the slide collapsed into a
    /// fade-in-place. Starting a window-height above the physical edge means the first
    /// frame is truly off-screen and the capsule descends from under the top bezel —
    /// past the notch — into place. Same x, so the travel is purely vertical.
    private var hiddenOrigin: NSPoint {
        guard let screen = activeScreen else { return .zero }
        return NSPoint(x: visibleOrigin.x, y: screen.frame.maxY)
    }
}
