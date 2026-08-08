//
//  SpeechEngineDescriptor.swift
//  LibreVoice
//

import Foundation

/// Where a speech engine does its work.
///
/// This is modelled as a type rather than a `Bool` because it is the single most
/// important thing a privacy-first app can tell someone about a backend, and because
/// the remote case has to name a host. A `isOnDevice: Bool` could not.
nonisolated enum ProcessingLocation: Sendable, Hashable {
    /// Audio never leaves the Mac.
    case onDevice

    /// Audio is uploaded to `host` for transcription.
    case remote(host: String)

    /// Whether using this engine sends audio off the machine.
    var sendsAudioOffDevice: Bool {
        switch self {
        case .onDevice: false
        case .remote: true
        }
    }
}

/// Static, user-facing metadata about a speech backend.
///
/// A descriptor can be read without instantiating the engine, which is what lets the
/// settings UI list every backend — including ones that need a multi-gigabyte model —
/// without loading any of them.
nonisolated struct SpeechEngineDescriptor: Sendable, Identifiable, Hashable {
    let id: SpeechEngineID

    /// The name shown in the engine picker, such as "Whisper (MLX)".
    let name: String

    /// One line describing the trade-off this engine makes, shown under `name`.
    let summary: String

    /// Whether audio leaves the device.
    let processing: ProcessingLocation

    /// The locales this engine can transcribe. Empty means "unknown until loaded".
    let supportedLocales: [Locale]

    /// Whether the engine needs a model downloaded before first use.
    let requiresModelDownload: Bool

    init(
        id: SpeechEngineID,
        name: String,
        summary: String,
        processing: ProcessingLocation,
        supportedLocales: [Locale] = [],
        requiresModelDownload: Bool = false
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.processing = processing
        self.supportedLocales = supportedLocales
        self.requiresModelDownload = requiresModelDownload
    }
}
