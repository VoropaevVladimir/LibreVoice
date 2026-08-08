//
//  SpeechEngineRegistry.swift
//  LibreVoice
//

import Foundation

/// The set of speech backends known to this build of LibreVoice.
///
/// The registry is the only place where the plug-in system is assembled, and it is
/// populated exactly once, at the composition root. That single fact is what makes
/// "the application must not depend on any engine implementation" true rather than
/// aspirational: `Core` and `Features` see only ``SpeechEngineProviding``, and the one
/// file that names concrete engines is `AppEnvironment`.
///
/// An `actor` because registration happens during launch while lookups happen from
/// dictation sessions, and the roster must not be read mid-mutation.
actor SpeechEngineRegistry: SpeechEngineProviding {
    private var factories: [SpeechEngineID: any SpeechEngineFactory] = [:]

    /// Registration order, which is also preference order. A dictionary alone would
    /// lose it, and the default engine depends on it.
    private var order: [SpeechEngineID] = []

    private let logger: any Logger

    init(logger: any Logger = NullLogger()) {
        self.logger = logger
    }

    /// Adds `factory` to the registry.
    ///
    /// Registration order is preference order: the first registered engine that is
    /// available becomes the default. Registering a duplicate identifier replaces the
    /// previous factory and keeps the original position.
    func register(_ factory: any SpeechEngineFactory) {
        let id = factory.descriptor.id

        if factories[id] == nil {
            order.append(id)
        } else {
            logger.warning(
                "Speech engine “\(id.rawValue)” was registered twice; replacing the earlier one.",
                category: .speech
            )
        }

        factories[id] = factory
        logger.info("Registered speech engine “\(id.rawValue)”.", category: .speech)
    }

    // MARK: - SpeechEngineProviding

    func descriptors() async -> [SpeechEngineDescriptor] {
        order.compactMap { factories[$0]?.descriptor }
    }

    func availableDescriptors() async -> [SpeechEngineDescriptor] {
        var available: [SpeechEngineDescriptor] = []
        for id in order {
            guard let factory = factories[id] else { continue }
            if await factory.isAvailable() {
                available.append(factory.descriptor)
            }
        }
        return available
    }

    func defaultEngineID() async -> SpeechEngineID? {
        await availableDescriptors().first?.id
    }

    func makeEngine(for id: SpeechEngineID) async throws -> any SpeechRecognitionEngine {
        guard let factory = factories[id] else {
            logger.error("No speech engine registered for “\(id.rawValue)”.", category: .speech)
            throw SpeechRecognitionError.unknownEngine(id)
        }
        logger.info("Building speech engine “\(id.rawValue)”.", category: .speech)
        return try await factory.makeEngine()
    }
}
