//
//  FileSystemModelRepository.swift
//  LibreVoice
//

import Foundation

/// Downloads, verifies, stores and deletes speech models on disk.
///
/// This is where the download subsystem's security lives, because it is the last thing
/// between a remote file and an engine loading it:
///
/// 1. **Path safety.** The model id and every file path come from a catalog that may be
///    hosted remotely, so they are untrusted. Each is checked to be a plain name — no
///    separators, no `..` — before it becomes part of a path, so a hostile catalog cannot
///    escape the models directory.
/// 2. **Disk space.** A multi-gigabyte download is refused up front if it would not fit,
///    rather than filling the disk and failing at the end.
/// 3. **Checksum.** Every file is hashed after download and compared to the catalog's
///    SHA-256. One mismatch fails the whole model and deletes what was fetched — a model
///    is loaded only if every byte is exactly what the distributor published.
/// 4. **Atomic install.** Files are downloaded into a staging directory and moved into
///    place only once all of them have verified. There is never a half-written model that
///    looks installed.
///
/// An `actor`: installs run concurrently with the UI reading state, and the state map and
/// staging directories must not be touched mid-mutation.
actor FileSystemModelRepository: ModelRepository {
    private let catalog: any ModelCatalog
    private let downloader: any ModelFileDownloading
    private let logger: any Logger
    private let fileManager = FileManager.default

    private let modelsDirectory: URL

    /// Free space to keep beyond a model's own size, so an install never fills the disk.
    private let diskSpaceMargin: Int64 = 100 * 1024 * 1024

    private var installStates: [ModelIdentifier: ModelInstallState] = [:]
    private var installTasks: [ModelIdentifier: Task<Void, Never>] = [:]
    private var observers: [UUID: AsyncStream<[ModelIdentifier: ModelInstallState]>.Continuation] = [:]

    /// Creates a repository storing models under Application Support.
    ///
    /// - Parameters:
    ///   - containerDirectory: The directory to create the models folder in.
    ///     Defaults to Application Support; tests pass a temporary directory.
    ///   - subdirectoryName: The folder name inside the container. Speech models live
    ///     in `Models`; language models pass `LanguageModels` so the two families can
    ///     never collide, whatever their catalogs name things.
    init(
        catalog: any ModelCatalog,
        downloader: any ModelFileDownloading,
        containerDirectory: URL? = nil,
        subdirectoryName: String = "Models",
        logger: any Logger = NullLogger()
    ) {
        self.catalog = catalog
        self.downloader = downloader
        self.logger = logger

        // "LibreVoice", not the bundle identifier: the models folder is a documented,
        // user-visible location (~/Library/Application Support/LibreVoice/Models) that
        // people are told about and may manage by hand.
        let container = containerDirectory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LibreVoice", isDirectory: true)
        self.modelsDirectory = container.appendingPathComponent(subdirectoryName, isDirectory: true)
    }

    // MARK: - Reading state

    func availableModels() async -> [ModelDescriptor] {
        do {
            let models = try await catalog.availableModels()
            // Reconcile: anything already on disk should read as installed on first look,
            // not "not installed" until someone downloads it again.
            for model in models where installStates[model.id] == nil {
                installStates[model.id] = detectInstalledState(for: model)
            }
            return models
        } catch {
            logger.error("Couldn't read the model catalog.", error: error, category: .speech)
            return []
        }
    }

    func currentStates() async -> [ModelIdentifier: ModelInstallState] { installStates }

    func installState(of id: ModelIdentifier) async -> ModelInstallState {
        installStates[id] ?? .notInstalled
    }

    func states() async -> AsyncStream<[ModelIdentifier: ModelInstallState]> {
        AsyncStream { continuation in
            let id = UUID()
            observers[id] = continuation
            continuation.yield(installStates)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(id) }
            }
        }
    }

    func installedLocation(of id: ModelIdentifier) async -> URL? {
        let directory = modelDirectory(for: id)
        guard let directory, fileManager.fileExists(atPath: directory.path) else { return nil }
        return directory
    }

    func totalInstalledSize() async -> Int64 {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return contents.reduce(0) { $0 + directorySize(at: $1) }
    }

    // MARK: - Installing

    func install(_ descriptor: ModelDescriptor) async {
        guard !(installStates[descriptor.id]?.isBusy ?? false) else { return }
        if case .installed = installStates[descriptor.id] { return }

        installTasks[descriptor.id] = Task { [weak self] in
            guard let self else { return }
            await self.performInstall(descriptor)
        }
    }

    func cancelInstall(of id: ModelIdentifier) async {
        installTasks[id]?.cancel()
        installTasks[id] = nil
    }

    func remove(_ id: ModelIdentifier) async {
        await cancelInstall(of: id)
        if let directory = modelDirectory(for: id) {
            try? fileManager.removeItem(at: directory)
        }
        update(id, to: .notInstalled)
    }

    // MARK: - The install pipeline

    private func performInstall(_ descriptor: ModelDescriptor) async {
        defer { installTasks[descriptor.id] = nil }

        do {
            let modelDirectory = try safeModelDirectory(for: descriptor.id)
            try checkDiskSpace(for: descriptor)

            update(descriptor.id, to: .downloading(.zero))

            let staging = modelsDirectory.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: staging) }

            try await downloadAndVerify(descriptor, into: staging)

            // Atomic swap: only now, with every file present and verified, does the model
            // become visible under its real name.
            if fileManager.fileExists(atPath: modelDirectory.path) {
                try fileManager.removeItem(at: modelDirectory)
            }
            try fileManager.moveItem(at: staging, to: modelDirectory)

            let size = directorySize(at: modelDirectory)
            update(descriptor.id, to: .installed(sizeBytes: size))
            logger.info("Installed model “\(descriptor.id.rawValue)”.", category: .speech)
        } catch is CancellationError {
            update(descriptor.id, to: .notInstalled)
        } catch let error as ModelError {
            if error == .cancelled {
                update(descriptor.id, to: .notInstalled)
            } else {
                logger.error("Install of “\(descriptor.id.rawValue)” failed.", error: error, category: .speech)
                update(descriptor.id, to: .failed(error))
            }
        } catch {
            update(descriptor.id, to: .failed(.storageFailed(reason: error.localizedDescription)))
        }
    }

    private func downloadAndVerify(_ descriptor: ModelDescriptor, into staging: URL) async throws {
        let totalBytes = descriptor.totalSizeBytes
        var completedBytes: Int64 = 0

        for file in descriptor.files {
            try Task.checkCancellation()

            let safeName = try safeRelativePath(file.path)
            guard file.url.scheme?.lowercased() == "https" else { throw ModelError.insecureURL(file.url) }

            // Progress across the whole model, not just this file, so a six-file model
            // shows one bar climbing to 100% rather than resetting per file.
            let baseline = completedBytes

            // Re-enter the downloading state at the start of each file. Without this, the
            // previous file's `.verifying` state would still be current, and
            // `reportProgress` — which only refines an existing `.downloading` — would
            // suppress this file's progress, leaving the UI stuck on "Verifying…".
            update(descriptor.id, to: .downloading(
                ModelDownloadProgress(bytesReceived: baseline, totalBytes: totalBytes)
            ))
            let temporaryFile = try await downloader.download(
                from: file.url,
                expectedSize: file.sizeBytes
            ) { [weak self] progress in
                Task { await self?.reportProgress(
                    for: descriptor.id,
                    ModelDownloadProgress(bytesReceived: baseline + progress.bytesReceived, totalBytes: totalBytes)
                ) }
            }
            defer { try? fileManager.removeItem(at: temporaryFile) }

            update(descriptor.id, to: .verifying)
            let digest = try FileChecksum.sha256Hex(ofFileAt: temporaryFile)
            guard file.sha256.matches(digest) else {
                logger.error("Checksum mismatch for “\(descriptor.id.rawValue)/\(file.path)”.", category: .speech)
                throw ModelError.checksumMismatch(expected: file.sha256.sha256, actual: digest)
            }

            // A nested path needs its folders to exist before the move. Core ML bundles
            // are directories, so this is the normal case for them, not an edge case.
            let destination = staging.appendingPathComponent(safeName)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: temporaryFile, to: destination)
            completedBytes += file.sizeBytes
        }
    }

    // MARK: - Path safety

    /// Turns a model id into its directory, refusing anything that is not a plain name.
    ///
    /// The id stays a *single* component even though file paths may nest: a model's own
    /// folder is the boundary everything else is validated against, so it must not be
    /// able to move.
    private func safeModelDirectory(for id: ModelIdentifier) throws -> URL {
        let name = try safeSingleComponent(id.rawValue)
        return modelsDirectory.appendingPathComponent(name, isDirectory: true)
    }

    /// The stored directory for `id`, or `nil` if its id is unsafe (so callers that only
    /// read never throw). Unsafe ids cannot have been installed in the first place.
    private func modelDirectory(for id: ModelIdentifier) -> URL? {
        try? safeModelDirectory(for: id)
    }

    /// Validates that `path` is a safe *relative* path inside the model's own folder.
    ///
    /// This is the guard against a remote catalog smuggling `../../…` into a file name and
    /// writing outside the models directory. It permits subdirectories, because some model
    /// formats are directories rather than files: a Core ML model is an `.mlmodelc` bundle
    /// whose weights live at `Encoder.mlmodelc/weights/weight.bin`. Refusing separators
    /// outright would have meant either flattening those names — losing the structure
    /// Core ML requires — or downloading such models outside the catalog, and with them
    /// outside its checksum verification. Structure is preserved; safety is kept by
    /// validating every component instead of the whole string:
    ///
    /// - no empty components, so `a//b` and a leading `/` (absolute) are refused,
    /// - no `.` or `..`, so no component can climb out of the folder,
    /// - a conservative character set per component, so backslashes, colons and control
    ///   characters never reach the file system.
    ///
    /// The result is joined with `/` and appended to the model's directory, so the worst a
    /// hostile catalog can do is create a nested folder inside the directory it was
    /// already allowed to write.
    private func safeRelativePath(_ path: String) throws -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)

        // A depth limit as well as a content check: nothing legitimate nests deeply, and
        // a bound keeps a catalog from building an absurd tree inside the folder.
        guard !components.isEmpty, components.count <= 8 else {
            throw ModelError.unsafeIdentifier(ModelIdentifier(rawValue: path))
        }
        for component in components {
            _ = try safeSingleComponent(component, reporting: path)
        }
        return components.joined(separator: "/")
    }

    /// Validates one path component: no traversal, no separators, no surprises.
    ///
    /// - Parameter reported: what to name in the error, when the component is part of a
    ///   longer path the user would recognise.
    private func safeSingleComponent(_ name: String, reporting reported: String? = nil) throws -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        guard !name.isEmpty,
              name != ".", name != "..",
              !name.contains("/"), !name.contains("\\"),
              name.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else {
            throw ModelError.unsafeIdentifier(ModelIdentifier(rawValue: reported ?? name))
        }
        return name
    }

    // MARK: - Disk space

    private func checkDiskSpace(for descriptor: ModelDescriptor) throws {
        try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let required = descriptor.totalSizeBytes + diskSpaceMargin
        let values = try? modelsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values?.volumeAvailableCapacityForImportantUsage else { return }

        guard available >= required else {
            throw ModelError.insufficientDiskSpace(required: descriptor.totalSizeBytes, available: available)
        }
    }

    // MARK: - Helpers

    private func detectInstalledState(for model: ModelDescriptor) -> ModelInstallState {
        guard let directory = modelDirectory(for: model.id),
              fileManager.fileExists(atPath: directory.path) else {
            return .notInstalled
        }
        // Treat a model as installed only if every expected file is present, so a download
        // interrupted before the atomic move never masquerades as complete.
        let complete = model.files.allSatisfy { file in
            (try? safeRelativePath(file.path)).map {
                fileManager.fileExists(atPath: directory.appendingPathComponent($0).path)
            } ?? false
        }
        return complete ? .installed(sizeBytes: directorySize(at: directory)) : .notInstalled
    }

    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize
            total += Int64(size ?? 0)
        }
        return total
    }

    private func update(_ id: ModelIdentifier, to state: ModelInstallState) {
        installStates[id] = state
        for continuation in observers.values {
            continuation.yield(installStates)
        }
    }

    /// Applies a progress update, but only while a download is actually in progress.
    ///
    /// Progress arrives via detached tasks, which can be delivered *after* the install has
    /// already moved on to verifying, installed, or failed. Refusing to overwrite anything
    /// but an existing `.downloading` state stops a late, stale progress event from
    /// resurrecting a finished install back into a spinner — a real race, not just a
    /// test artefact.
    private func reportProgress(for id: ModelIdentifier, _ progress: ModelDownloadProgress) {
        guard case .downloading = installStates[id] else { return }
        update(id, to: .downloading(progress))
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }
}
