//
//  AudioCaptureError.swift
//  LibreVoice
//

import Foundation

/// Something that stopped LibreVoice from capturing audio.
nonisolated enum AudioCaptureError: LocalizedError, Sendable, Equatable {
    /// The user has not granted microphone access.
    case microphonePermissionDenied

    /// The Mac reports no usable audio input.
    case noInputDeviceAvailable

    /// The device selected in settings has been unplugged or disabled.
    case selectedDeviceUnavailable(name: String)

    /// The audio engine refused to start.
    case engineFailedToStart(reason: String)

    /// `start()` was called on a service that is already capturing.
    case alreadyCapturing

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            String(localized: "LibreVoice doesn't have permission to use the microphone.")
        case .noInputDeviceAvailable:
            String(localized: "No microphone is available.")
        case .selectedDeviceUnavailable(let name):
            String(localized: "The microphone “\(name)” is no longer available.")
        case .engineFailedToStart(let reason):
            String(localized: "The audio engine couldn't start: \(reason)")
        case .alreadyCapturing:
            String(localized: "Audio capture is already running.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .microphonePermissionDenied:
            String(localized: "Open System Settings › Privacy & Security › Microphone and turn on LibreVoice.")
        case .noInputDeviceAvailable:
            String(localized: "Connect a microphone and try again.")
        case .selectedDeviceUnavailable:
            String(localized: "Choose a different microphone in LibreVoice Settings.")
        case .engineFailedToStart:
            String(localized: "Try again. If it keeps happening, restart LibreVoice.")
        case .alreadyCapturing:
            nil
        }
    }
}
