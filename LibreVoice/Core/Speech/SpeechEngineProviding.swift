//
//  SpeechEngineProviding.swift
//  LibreVoice
//

import Foundation

/// Read-only access to the speech backends the app was built with.
///
/// Consumers — the settings picker, the dictation coordinator — depend on this rather
/// than on ``SpeechEngineRegistry`` itself, so they can be tested against a fake roster
/// and cannot register anything. Registration is a composition-root privilege, and
/// keeping it off this protocol is what enforces that.
nonisolated protocol SpeechEngineProviding: Sendable {
    /// Every registered engine, in preference order.
    func descriptors() async -> [SpeechEngineDescriptor]

    /// The registered engines that can run on this Mac right now.
    func availableDescriptors() async -> [SpeechEngineDescriptor]

    /// The engine to use when the user has not chosen one.
    ///
    /// `nil` when no engine can run here — a real possibility, and one the UI must
    /// handle rather than crash on.
    func defaultEngineID() async -> SpeechEngineID?

    /// Builds the engine registered under `id`.
    ///
    /// - Throws: ``SpeechRecognitionError/unknownEngine(_:)`` if nothing is registered
    ///   under `id`.
    func makeEngine(for id: SpeechEngineID) async throws -> any SpeechRecognitionEngine
}
