//
//  SpeechEngineFactory.swift
//  LibreVoice
//

import Foundation

/// Creates instances of one speech backend, and reports whether it can run here.
///
/// The indirection matters because engines are expensive and conditional. Listing the
/// engine picker must not load a single model, and "is MLX usable on this Mac?" can
/// only be answered at run time. A factory answers both questions cheaply, and stays
/// the only type that knows the concrete engine's name.
nonisolated protocol SpeechEngineFactory: Sendable {
    /// Metadata for the engine this factory builds, available without building it.
    var descriptor: SpeechEngineDescriptor { get }

    /// Whether the engine can actually run on this Mac right now.
    ///
    /// Checks things that vary by machine and moment: Apple silicon for MLX, a
    /// downloaded model for whisper.cpp, on-device recognition support for `Speech`.
    /// An unavailable engine is shown in the UI but cannot be selected, which is
    /// friendlier than hiding it and leaving the user wondering.
    func isAvailable() async -> Bool

    /// Builds a new, unprepared engine.
    ///
    /// - Throws: ``SpeechRecognitionError`` if the engine cannot be constructed.
    func makeEngine() async throws -> any SpeechRecognitionEngine
}
