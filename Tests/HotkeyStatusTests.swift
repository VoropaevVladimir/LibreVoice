//
//  HotkeyStatusTests.swift
//  LibreVoiceTests
//

import Foundation
import Observation
import Testing
@testable import LibreVoice

/// The point of this type is that a *view* redraws when it changes.
///
/// Checking the value flips would prove nothing: the first attempt at this feature put the
/// flag on `AppEnvironment`, which is held in `@State` but is not `@Observable`. The value
/// changed correctly and the warning never appeared on screen. So these tests assert the
/// observation itself fires, which is the part that was actually broken.

/// A flag the observation callback can set — it runs outside the test's isolation, so a
/// plain captured `var` will not compile.
private nonisolated final class ChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func raise() {
        lock.lock(); defer { lock.unlock() }
        value = true
    }

    var wasRaised: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

@Suite("Hotkey status")
@MainActor
struct HotkeyStatusTests {
    @Test("A healthy shortcut is the starting assumption")
    func startsRegistered() {
        #expect(HotkeyStatus().isRegistered)
    }

    @Test("Failing to bind the shortcut notifies observers")
    func failureNotifiesObservers() {
        let status = HotkeyStatus()
        let notified = ChangeFlag()

        withObservationTracking {
            _ = status.isRegistered
        } onChange: {
            notified.raise()
        }

        status.markFailed()

        #expect(status.isRegistered == false)
        #expect(notified.wasRaised, "Without this, the settings screen never redraws and the warning is dead code.")
    }

    @Test("Recovering notifies observers too")
    func recoveryNotifiesObservers() {
        let status = HotkeyStatus()
        status.markFailed()

        let notified = ChangeFlag()
        withObservationTracking {
            _ = status.isRegistered
        } onChange: {
            notified.raise()
        }

        status.markRegistered()

        #expect(status.isRegistered)
        #expect(notified.wasRaised)
    }
}
