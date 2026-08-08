//
//  SystemPermissionService.swift
//  LibreVoice
//

import AVFoundation
import AppKit
import ApplicationServices
import Foundation

/// Reads and requests real system authorizations through TCC.
///
/// The two permissions LibreVoice needs behave nothing alike, which is most of why
/// this type exists:
///
/// - **Microphone** has a proper API. `AVCaptureDevice` reports status and `requestAccess`
///   prompts once, then never again.
/// - **Accessibility** has almost none. `AXIsProcessTrusted()` reports a `Bool` — there
///   is no "not determined" — the prompt is a side effect of a check, the grant lands
///   asynchronously while the app is running, and nothing notifies anyone. Polling is
///   not a shortcut here; it is the only mechanism macOS offers.
///
/// Hiding that asymmetry behind ``PermissionService`` is what keeps it out of the UI.
nonisolated final class SystemPermissionService: PermissionService {
    private let logger: any Logger

    /// How often accessibility status is re-checked while someone is watching it.
    ///
    /// Half a second feels immediate when the user flips the switch in System Settings
    /// and is far too coarse to cost anything measurable.
    private let accessibilityPollInterval: Duration = .milliseconds(500)

    init(logger: any Logger = NullLogger()) {
        self.logger = logger
    }

    // MARK: - PermissionService

    func status(of permission: Permission) async -> PermissionStatus {
        switch permission {
        case .microphone: microphoneStatus()
        case .accessibility: accessibilityStatus()
        }
    }

    @discardableResult
    func request(_ permission: Permission) async -> PermissionStatus {
        switch permission {
        case .microphone: await requestMicrophone()
        case .accessibility: await requestAccessibility()
        }
    }

    func statusChanges(for permission: Permission) -> AsyncStream<PermissionStatus> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                var previous: PermissionStatus?
                while !Task.isCancelled {
                    let current = await status(of: permission)
                    if current != previous {
                        previous = current
                        continuation.yield(current)
                    }
                    try? await Task.sleep(for: accessibilityPollInterval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @MainActor
    func openSystemSettings(for permission: Permission) {
        guard let url = permission.systemSettingsURL else { return }
        logger.info("Opening System Settings for \(permission.rawValue).", category: .permissions)
        NSWorkspace.shared.open(url)
    }

    // MARK: - Microphone

    private func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: .notDetermined
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        @unknown default:
            // A status this build does not know about. Treating it as denied keeps the
            // app honest: it will not claim access it may not have.
            .denied
        }
    }

    private func requestMicrophone() async -> PermissionStatus {
        let current = microphoneStatus()
        guard current.isPromptable else {
            logger.debug(
                "Not prompting for microphone; status is already \(current).",
                category: .permissions
            )
            return current
        }

        logger.info("Requesting microphone access.", category: .permissions)
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        let result: PermissionStatus = granted ? .granted : .denied
        logger.info("Microphone access \(granted ? "granted" : "denied").", category: .permissions)
        return result
    }

    // MARK: - Accessibility

    private func accessibilityStatus() -> PermissionStatus {
        // AXIsProcessTrusted() cannot distinguish "never asked" from "refused", so
        // untrusted is reported as `.denied`. That is the conservative reading: the UI
        // offers a System Settings link, which works in both cases, rather than a
        // prompt, which works in neither.
        AXIsProcessTrusted() ? .granted : .denied
    }

    private func requestAccessibility() async -> PermissionStatus {
        if AXIsProcessTrusted() { return .granted }

        logger.info("Prompting for Accessibility access.", category: .permissions)

        // This shows the system's "open System Settings" alert. It returns immediately
        // and always reports the *current* (untrusted) state — the grant, if it comes,
        // arrives later while the app keeps running.
        //
        // The key is spelled out rather than read from `kAXTrustedCheckOptionPrompt`,
        // which is an unannotated global `var` and so counts as shared mutable state
        // under strict concurrency. The string is part of the API contract and cannot
        // change without breaking every app that uses it.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        return accessibilityStatus()
    }
}
