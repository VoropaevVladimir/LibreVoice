//
//  ModelRepository.swift
//  LibreVoice
//

import Foundation

/// Manages the speech models on this Mac: what is available, what is installed, and the
/// downloading, verifying and deleting in between.
///
/// The design mirrors ``DictationCoordinator``: actions do not throw, they drive state.
/// A download that fails lands the model in ``ModelInstallState/failed(_:)`` where the UI
/// can show why and offer a retry, rather than making every call site a `do/catch`.
/// Progress and outcomes are observed through ``states()``.
///
/// A speech engine, once implemented, will ask its repository for
/// ``installedLocation(of:)`` to find the model file to load — which is the whole point
/// of this subsystem existing ahead of the engines.
nonisolated protocol ModelRepository: Sendable {
    /// The models on offer, from the catalog. Returns `[]` (and logs) if the catalog
    /// cannot be read, because an empty list is something the UI can show and a thrown
    /// error at the top of a screen is not.
    func availableModels() async -> [ModelDescriptor]

    /// The current state of every model the repository knows about.
    func currentStates() async -> [ModelIdentifier: ModelInstallState]

    /// A stream that emits the full state map whenever anything changes.
    ///
    /// - Important: Intended for a single observer (the model-management screen). Progress
    ///   updates are throttled so a fast download does not flood the UI.
    func states() async -> AsyncStream<[ModelIdentifier: ModelInstallState]>

    /// The state of one model right now.
    func installState(of id: ModelIdentifier) async -> ModelInstallState

    /// Starts downloading, verifying and installing `descriptor`.
    ///
    /// Does nothing if the model is already installed or an install is already running.
    /// Outcome is reported through state, not by throwing.
    func install(_ descriptor: ModelDescriptor) async

    /// Cancels an in-flight install for `id`. Safe to call when nothing is running.
    func cancelInstall(of id: ModelIdentifier) async

    /// Deletes an installed model.
    func remove(_ id: ModelIdentifier) async

    /// The on-disk location of an installed model, or `nil` if it is not installed.
    ///
    /// This is what an engine calls to find the file it should load.
    func installedLocation(of id: ModelIdentifier) async -> URL?

    /// The total size of every installed model, for the "using 1.2 GB" summary.
    func totalInstalledSize() async -> Int64
}
