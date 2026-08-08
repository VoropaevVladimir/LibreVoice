//
//  ModelRepositoryTests.swift
//  LibreVoiceTests
//

import CryptoKit
import Foundation
import Testing
@testable import LibreVoice

/// A downloader backed by in-memory bytes, so the repository's real logic — disk checks,
/// checksum verification, atomic install, path safety — is exercised with no network.
///
/// This is the whole reason ``ModelFileDownloading`` is a separate seam: the interesting,
/// security-critical behaviour lives in the repository, and none of it should need a
/// server to test.
private final class FakeDownloader: ModelFileDownloading, @unchecked Sendable {
    /// Bytes to serve, keyed by URL. A URL absent here fails as "not found".
    var payloads: [URL: Data]

    /// URLs told to fail with a network error.
    var failing: Set<URL> = []

    init(payloads: [URL: Data] = [:]) {
        self.payloads = payloads
    }

    func download(
        from url: URL,
        expectedSize: Int64?,
        onProgress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> URL {
        guard url.scheme == "https" else { throw ModelError.insecureURL(url) }
        if failing.contains(url) { throw ModelError.downloadFailed(reason: "simulated failure") }
        guard let data = payloads[url] else { throw ModelError.downloadFailed(reason: "not found") }

        onProgress(ModelDownloadProgress(bytesReceived: Int64(data.count), totalBytes: Int64(data.count)))

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-\(UUID().uuidString)")
        try data.write(to: temp)
        return temp
    }
}

@Suite("ModelRepository")
struct ModelRepositoryTests {
    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func temporaryContainer() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("librevoice-tests-\(UUID().uuidString)")
        return url
    }

    /// Builds a repository over a fake catalog and downloader, isolated to a temp dir.
    private func makeRepository(
        models: [ModelDescriptor],
        downloader: FakeDownloader
    ) -> (FileSystemModelRepository, URL) {
        let container = temporaryContainer()
        let repository = FileSystemModelRepository(
            catalog: StubModelCatalog(models: models),
            downloader: downloader,
            containerDirectory: container
        )
        return (repository, container)
    }

    /// A one-file model whose checksum matches `data`.
    private func model(id: String, url: URL, data: Data, checksum: String? = nil) -> ModelDescriptor {
        ModelDescriptor(
            id: ModelIdentifier(rawValue: id),
            engineID: SpeechEngineID(rawValue: "mlx-whisper"),
            displayName: id,
            summary: "test model",
            files: [
                ModelFile(
                    path: "weights.npz",
                    url: url,
                    sizeBytes: Int64(data.count),
                    sha256: ModelChecksum(sha256: checksum ?? sha256(data))
                )
            ]
        )
    }

    @Test("A model with a matching checksum installs")
    func installsWithMatchingChecksum() async throws {
        let url = URL(string: "https://example.com/weights.npz")!
        let data = Data("the model weights".utf8)
        let descriptor = model(id: "good", url: url, data: data)
        let (repository, container) = makeRepository(models: [descriptor], downloader: FakeDownloader(payloads: [url: data]))
        defer { try? FileManager.default.removeItem(at: container) }

        await repository.install(descriptor)
        try await waitForState(repository, id: descriptor.id) { $0.isInstalled }

        #expect(await repository.installState(of: descriptor.id).isInstalled)
        let location = await repository.installedLocation(of: descriptor.id)
        #expect(location != nil)
    }

    @Test("A checksum mismatch is rejected and nothing is installed")
    func rejectsChecksumMismatch() async throws {
        // The served bytes differ from what the catalog's checksum describes — exactly the
        // MITM / compromised-mirror case the checksum exists to catch.
        let url = URL(string: "https://example.com/tampered.npz")!
        let advertised = Data("what the distributor published".utf8)
        let served = Data("what an attacker swapped in".utf8)
        let descriptor = model(id: "tampered", url: url, data: advertised)
        let (repository, container) = makeRepository(
            models: [descriptor],
            downloader: FakeDownloader(payloads: [url: served])
        )
        defer { try? FileManager.default.removeItem(at: container) }

        await repository.install(descriptor)
        try await waitForState(repository, id: descriptor.id) {
            if case .failed = $0 { return true } else { return false }
        }

        let state = await repository.installState(of: descriptor.id)
        guard case .failed(let error) = state else {
            Issue.record("Expected a failure, got \(state)")
            return
        }
        guard case .checksumMismatch = error else {
            Issue.record("Expected a checksumMismatch, got \(error)")
            return
        }
        #expect(await repository.installedLocation(of: descriptor.id) == nil, "A model that failed verification must not be on disk.")
    }

    @Test("A non-HTTPS file URL is refused")
    func refusesInsecureURL() async throws {
        let url = URL(string: "http://example.com/weights.npz")!
        let data = Data("weights".utf8)
        let descriptor = model(id: "insecure", url: url, data: data)
        let (repository, container) = makeRepository(models: [descriptor], downloader: FakeDownloader(payloads: [url: data]))
        defer { try? FileManager.default.removeItem(at: container) }

        await repository.install(descriptor)
        try await waitForState(repository, id: descriptor.id) {
            if case .failed = $0 { return true } else { return false }
        }

        guard case .failed(.insecureURL) = await repository.installState(of: descriptor.id) else {
            Issue.record("Expected an insecureURL failure.")
            return
        }
    }

    @Test("A model id attempting path traversal is refused")
    func refusesPathTraversalIdentifier() async throws {
        // A hostile catalog trying to write outside the models directory.
        let url = URL(string: "https://example.com/weights.npz")!
        let data = Data("weights".utf8)
        let descriptor = model(id: "../../../../tmp/escape", url: url, data: data)
        let (repository, container) = makeRepository(models: [descriptor], downloader: FakeDownloader(payloads: [url: data]))
        defer { try? FileManager.default.removeItem(at: container) }

        await repository.install(descriptor)
        try await waitForState(repository, id: descriptor.id) {
            if case .failed = $0 { return true } else { return false }
        }

        guard case .failed(.unsafeIdentifier) = await repository.installState(of: descriptor.id) else {
            Issue.record("Expected an unsafeIdentifier failure.")
            return
        }
    }

    @Test("A file path attempting traversal is refused even with a safe model id")
    func refusesTraversalInFilePath() async throws {
        let url = URL(string: "https://example.com/weights.npz")!
        let data = Data("weights".utf8)
        let descriptor = ModelDescriptor(
            id: ModelIdentifier(rawValue: "safe-id"),
            engineID: SpeechEngineID(rawValue: "mlx-whisper"),
            displayName: "safe",
            summary: "test",
            files: [
                ModelFile(
                    path: "../../etc/evil",
                    url: url,
                    sizeBytes: Int64(data.count),
                    sha256: ModelChecksum(sha256: sha256(data))
                )
            ]
        )
        let (repository, container) = makeRepository(models: [descriptor], downloader: FakeDownloader(payloads: [url: data]))
        defer { try? FileManager.default.removeItem(at: container) }

        await repository.install(descriptor)
        try await waitForState(repository, id: descriptor.id) {
            if case .failed = $0 { return true } else { return false }
        }

        guard case .failed(.unsafeIdentifier) = await repository.installState(of: descriptor.id) else {
            Issue.record("Expected the traversal file path to be refused.")
            return
        }
    }

    @Test("Removing an installed model deletes it")
    func removeDeletesModel() async throws {
        let url = URL(string: "https://example.com/weights.npz")!
        let data = Data("weights".utf8)
        let descriptor = model(id: "removable", url: url, data: data)
        let (repository, container) = makeRepository(models: [descriptor], downloader: FakeDownloader(payloads: [url: data]))
        defer { try? FileManager.default.removeItem(at: container) }

        await repository.install(descriptor)
        try await waitForState(repository, id: descriptor.id) { $0.isInstalled }

        await repository.remove(descriptor.id)

        #expect(await repository.installedLocation(of: descriptor.id) == nil)
        #expect(await repository.installState(of: descriptor.id) == .notInstalled)
    }

    @Test("A multi-file model installs all its files together")
    func installsMultiFileModel() async throws {
        let configURL = URL(string: "https://example.com/config.json")!
        let weightsURL = URL(string: "https://example.com/weights.npz")!
        let configData = Data(#"{"model":"tiny"}"#.utf8)
        let weightsData = Data("lots of weights".utf8)

        let descriptor = ModelDescriptor(
            id: ModelIdentifier(rawValue: "multi"),
            engineID: SpeechEngineID(rawValue: "mlx-whisper"),
            displayName: "Multi",
            summary: "config + weights",
            files: [
                ModelFile(path: "config.json", url: configURL, sizeBytes: Int64(configData.count), sha256: ModelChecksum(sha256: sha256(configData))),
                ModelFile(path: "weights.npz", url: weightsURL, sizeBytes: Int64(weightsData.count), sha256: ModelChecksum(sha256: sha256(weightsData))),
            ]
        )
        let (repository, container) = makeRepository(
            models: [descriptor],
            downloader: FakeDownloader(payloads: [configURL: configData, weightsURL: weightsData])
        )
        defer { try? FileManager.default.removeItem(at: container) }

        await repository.install(descriptor)
        try await waitForState(repository, id: descriptor.id) { $0.isInstalled }

        let location = try #require(await repository.installedLocation(of: descriptor.id))
        #expect(FileManager.default.fileExists(atPath: location.appendingPathComponent("config.json").path))
        #expect(FileManager.default.fileExists(atPath: location.appendingPathComponent("weights.npz").path))
    }

    @Test("If one file of a multi-file model fails, nothing is left installed")
    func partialMultiFileLeavesNothing() async throws {
        let configURL = URL(string: "https://example.com/config.json")!
        let weightsURL = URL(string: "https://example.com/weights.npz")!
        let configData = Data(#"{"model":"tiny"}"#.utf8)
        let weightsData = Data("weights".utf8)

        let descriptor = ModelDescriptor(
            id: ModelIdentifier(rawValue: "partial"),
            engineID: SpeechEngineID(rawValue: "mlx-whisper"),
            displayName: "Partial",
            summary: "second file will fail",
            files: [
                ModelFile(path: "config.json", url: configURL, sizeBytes: Int64(configData.count), sha256: ModelChecksum(sha256: sha256(configData))),
                ModelFile(path: "weights.npz", url: weightsURL, sizeBytes: Int64(weightsData.count), sha256: ModelChecksum(sha256: sha256(weightsData))),
            ]
        )
        // Serve config but make weights fail — the atomic-install guarantee says a partial
        // download must not appear as an installed model.
        let downloader = FakeDownloader(payloads: [configURL: configData, weightsURL: weightsData])
        downloader.failing = [weightsURL]
        let (repository, container) = makeRepository(models: [descriptor], downloader: downloader)
        defer { try? FileManager.default.removeItem(at: container) }

        await repository.install(descriptor)
        try await waitForState(repository, id: descriptor.id) {
            if case .failed = $0 { return true } else { return false }
        }

        #expect(await repository.installedLocation(of: descriptor.id) == nil, "A half-downloaded model must never look installed.")
    }

    // MARK: - Helper

    /// Polls the repository until `condition` holds, since installs run detached.
    private func waitForState(
        _ repository: FileSystemModelRepository,
        id: ModelIdentifier,
        timeout: Duration = .seconds(3),
        _ condition: @Sendable (ModelInstallState) -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition(await repository.installState(of: id)) { return }
            try await Task.sleep(for: .milliseconds(15))
        }
        Issue.record("Timed out waiting for model \(id.rawValue) to reach the expected state.")
    }

    // MARK: - Nested paths (Core ML bundles)

    @Test("A Core ML bundle installs with its directory structure intact")
    func nestedPathsInstall() async throws {
        // A Core ML model is a directory, not a file, so the catalog had to learn nested
        // paths. This pins that the structure Core ML requires actually survives install.
        let url = URL(string: "https://example.com/weight.bin")!
        let data = Data("encoder weights".utf8)
        let descriptor = ModelDescriptor(
            id: ModelIdentifier(rawValue: "coreml-model"),
            engineID: SpeechEngineID(rawValue: "nvidia-parakeet"),
            displayName: "Core ML model",
            summary: "test",
            files: [
                ModelFile(
                    path: "Encoder.mlmodelc/weights/weight.bin",
                    url: url,
                    sizeBytes: Int64(data.count),
                    sha256: ModelChecksum(sha256: sha256(data))
                )
            ]
        )
        let (repository, container) = makeRepository(
            models: [descriptor], downloader: FakeDownloader(payloads: [url: data])
        )

        await repository.install(descriptor)
        try await waitForState(repository, id: descriptor.id) { $0.isInstalled }

        let location = try #require(await repository.installedLocation(of: descriptor.id))
        let file = location.appendingPathComponent("Encoder.mlmodelc/weights/weight.bin")
        #expect(FileManager.default.fileExists(atPath: file.path))
        // And the relaxation must not have moved anything outside the model's folder.
        #expect(location.path.hasPrefix(container.path))
    }

    @Test("Traversal is still refused, however it is spelled")
    func traversalStillRefused() async throws {
        for hostile in ["../escaped.bin", "a/../../escaped.bin", "/etc/passwd", "a//b.bin", "a/./b.bin"] {
            let url = URL(string: "https://example.com/x.bin")!
            let data = Data("x".utf8)
            let descriptor = ModelDescriptor(
                id: ModelIdentifier(rawValue: "hostile"),
                engineID: SpeechEngineID(rawValue: "test"),
                displayName: "Hostile",
                summary: "test",
                files: [
                    ModelFile(
                        path: hostile,
                        url: url,
                        sizeBytes: Int64(data.count),
                        sha256: ModelChecksum(sha256: sha256(data))
                    )
                ]
            )
            let (repository, _) = makeRepository(
                models: [descriptor], downloader: FakeDownloader(payloads: [url: data])
            )

            await repository.install(descriptor)

            let state = await repository.installState(of: descriptor.id)
            let installed = if case .installed = state { true } else { false }
            #expect(!installed, "“\(hostile)” must not install")
        }
    }
}
