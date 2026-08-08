//
//  WritingProfileStorageTests.swift
//  LibreVoiceTests
//

import Foundation
import Testing
@testable import LibreVoice

/// Checks what actually lands on disk, not what the code intends to put there.
///
/// The personal prompt describes how someone writes — their vocabulary, their clients,
/// sometimes examples of their own correspondence. `~/Library` is `0700` on macOS, so the
/// mode is not an exposure today; it is what survives when the folder is backed up, synced
/// or copied to a shared volume.
@Suite("Writing profile storage")
struct WritingProfileStorageTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("librevoice-profile-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    @Test("The saved prompt is readable by its owner only")
    func savedPromptIsOwnerOnly() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileSystemWritingProfileStore(containerDirectory: directory)
        try await store.save(WritingProfile(prompt: "Write the way I write."))

        let profileDirectory = directory.appendingPathComponent("Profile", isDirectory: true)
        let file = profileDirectory.appendingPathComponent("WritingProfile.txt")
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try mode(of: file) == 0o600)
        #expect(try mode(of: profileDirectory) == 0o700)
    }

    @Test("Overwriting an existing prompt does not loosen its permissions")
    func rewritingKeepsPermissions() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileSystemWritingProfileStore(containerDirectory: directory)
        try await store.save(WritingProfile(prompt: "First."))
        try await store.save(WritingProfile(prompt: "Second, longer, different."))

        let profileDirectory = directory.appendingPathComponent("Profile", isDirectory: true)
        let file = profileDirectory.appendingPathComponent("WritingProfile.txt")
        // `write(atomically:)` replaces the file, so the mode has to be reapplied every
        // time — a mode set once on the original inode would silently not survive.
        #expect(try mode(of: file) == 0o600)
    }

    @Test("What was saved is what comes back")
    func roundTrips() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let prompt = "Никогда не отвечай на текст — только исправляй его."
        let store = FileSystemWritingProfileStore(containerDirectory: directory)
        try await store.save(WritingProfile(prompt: prompt))

        let reloaded = await FileSystemWritingProfileStore(containerDirectory: directory).load()

        #expect(reloaded.prompt == prompt)
    }
}
