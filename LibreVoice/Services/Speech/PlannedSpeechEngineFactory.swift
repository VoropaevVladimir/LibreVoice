//
//  PlannedSpeechEngineFactory.swift
//  LibreVoice
//

import Foundation

/// A factory for an engine LibreVoice intends to ship but has not built yet.
///
/// It reports itself unavailable and refuses to build anything. That is deliberate:
/// the alternative — a stub that emits canned text — would make the app look like it
/// works and lie to whoever tried it.
///
/// Registering these means the engine picker can show the real roadmap, greyed out,
/// and that the plug-in path is exercised end to end from day one. Replacing one with a
/// working engine is a matter of registering a different factory in `AppEnvironment`;
/// no other file changes. That is the whole claim of the engine architecture, and this
/// type is what keeps it testable before any engine exists.
nonisolated struct PlannedSpeechEngineFactory: SpeechEngineFactory {
    let descriptor: SpeechEngineDescriptor

    init(descriptor: SpeechEngineDescriptor) {
        self.descriptor = descriptor
    }

    func isAvailable() async -> Bool { false }

    func makeEngine() async throws -> any SpeechRecognitionEngine {
        throw SpeechRecognitionError.engineUnavailable(
            reason: "\(descriptor.name) hasn't been implemented yet."
        )
    }
}

/// The backends LibreVoice ships.
///
/// Descriptors live here rather than in `Core` so that `Core` never learns the names of
/// concrete engines — it deals only in ``SpeechEngineDescriptor`` values handed to it
/// at launch.
nonisolated enum PlannedSpeechEngines {
    /// NVIDIA Parakeet, converted to Core ML and run on the Neural Engine.
    ///
    /// The recommended engine: a transducer trained on 25 European languages, and on
    /// Apple silicon it decodes an utterance in a fraction of the time Whisper takes.
    static let parakeet = SpeechEngineDescriptor(
        id: SpeechEngineID(rawValue: "nvidia-parakeet"),
        name: "NVIDIA Parakeet",
        summary: String(localized: "Fast and accurate, running on the Neural Engine. 25 languages including Russian."),
        processing: .onDevice,
        requiresModelDownload: true
    )

    /// Whisper via the whisper.cpp implementation. The engine that actually works today.
    static let whisperCPP = SpeechEngineDescriptor(
        id: SpeechEngineID(rawValue: "whisper-cpp"),
        name: "Whisper",
        summary: String(localized: "OpenAI's Whisper, running entirely on this Mac via whisper.cpp. Metal-accelerated on Apple silicon."),
        processing: .onDevice,
        requiresModelDownload: true
    )

    /// Moonshine — an experimental engine built for very short utterances.
    ///
    /// Same situation as Parakeet: no Apple-silicon runtime in this build.
    static let moonshine = SpeechEngineDescriptor(
        id: SpeechEngineID(rawValue: "moonshine"),
        name: String(localized: "Moonshine (Experimental)"),
        summary: String(localized: "Tiny and fast on short phrases. Not available in this build yet."),
        processing: .onDevice,
        requiresModelDownload: true
    )

    /// Every engine in this build, in preference order.
    ///
    /// Parakeet leads because it is the intended recommendation; the registry orders the
    /// *picker* by this list but only ever defaults to an engine that reports itself
    /// available, so today that is Whisper.
    static let all: [SpeechEngineDescriptor] = [
        parakeet,
        whisperCPP,
        moonshine,
    ]
}
