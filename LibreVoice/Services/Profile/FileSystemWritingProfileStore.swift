//
//  FileSystemWritingProfileStore.swift
//  LibreVoice
//

import Foundation

/// Stores the personal prompt as one plain-text file on disk.
///
/// `~/Library/Application Support/LibreVoice/Profile/WritingProfile.txt` — a documented,
/// human-readable location. The prompt is the user's own writing about how they write;
/// they should be able to open it in any editor, back it up, or delete it with nothing
/// but Finder. No database, no opaque blob, no lock-in.
///
/// An `actor` because saving races against loading — the editor saves as you type.
actor FileSystemWritingProfileStore: WritingProfileStoring {
    private let directory: URL
    private let logger: any Logger
    private let fileManager = FileManager.default

    /// Cached after the first read so the editor's frequent saves do not re-read disk.
    private var cached: WritingProfile?

    /// Creates a store under Application Support.
    ///
    /// - Parameter containerDirectory: The directory to create the `Profile` folder in.
    ///   Defaults to Application Support; tests pass a temporary directory.
    init(containerDirectory: URL? = nil, logger: any Logger = NullLogger()) {
        let container = containerDirectory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LibreVoice", isDirectory: true)
        self.directory = container.appendingPathComponent("Profile", isDirectory: true)
        self.logger = logger
    }

    // MARK: - WritingProfileStoring

    func load() async -> WritingProfile {
        if let cached { return cached }

        if let text = try? String(contentsOf: promptURL, encoding: .utf8) {
            let profile = WritingProfile(prompt: text)
            cached = profile
            return profile
        }

        // Nothing stored yet. Someone who used the six-file scheme should not have to
        // start over, so their old files are folded into one prompt exactly once.
        if let migrated = migrateLegacyDocuments() {
            cached = migrated
            do {
                try persist(migrated)
                logger.info("Migrated the legacy Markdown profile into one personal prompt.", category: .settings)
            } catch {
                // Not fatal: the migrated prompt is live for this session, and the legacy
                // files are still on disk, so the next launch tries again. Worth saying
                // out loud though — announcing a migration that did not reach the disk is
                // how a silent repeat every launch goes unnoticed.
                logger.error(
                    "Migrated the legacy profile but couldn't save it; it will be migrated again next launch.",
                    error: error,
                    category: .settings
                )
            }
            return migrated
        }

        let fresh = WritingProfile.default
        cached = fresh
        return fresh
    }

    func save(_ profile: WritingProfile) async throws {
        guard profile.prompt.count <= WritingProfile.characterLimit else {
            throw WritingProfileError.tooLong(
                characters: profile.prompt.count,
                limit: WritingProfile.characterLimit
            )
        }
        try persist(profile)
        cached = profile
    }

    // MARK: - Disk

    private var promptURL: URL {
        directory.appendingPathComponent("WritingProfile.txt", isDirectory: false)
    }

    private func persist(_ profile: WritingProfile) throws {
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try profile.prompt.write(to: promptURL, atomically: true, encoding: .utf8)

            // Owner-only. The personal prompt describes how someone writes — their
            // vocabulary, their clients, sometimes examples of their own correspondence.
            // `~/Library` is 0700 on macOS, so the default 0644 is not an exposure today;
            // this is depth, for the day the folder is copied into a backup, a shared
            // volume, or a synced directory where the mode is all that is left.
            //
            // Set after the write, not before: `write(atomically:)` replaces the file, and
            // a mode applied to the previous inode would not survive.
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: promptURL.path)
        } catch {
            throw WritingProfileError.notSaved(reason: error.localizedDescription)
        }
    }

    // MARK: - Migration

    /// The file names the previous design used, in the order they were assembled.
    private static let legacyFiles = [
        "PROMPT.md", "STYLE.md", "TERMINOLOGY.md", "VOCABULARY.md", "FORMATTING.md", "EXAMPLES.md",
    ]

    /// Folds any legacy Markdown documents into a single prompt, or returns `nil` when
    /// there are none.
    ///
    /// The old files are left on disk rather than deleted: migration should not destroy
    /// something the user spent effort on, and a stale copy costs a few kilobytes.
    private func migrateLegacyDocuments() -> WritingProfile? {
        var sections: [String] = []
        for name in Self.legacyFiles {
            let url = directory.appendingPathComponent(name, isDirectory: false)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            sections.append(trimmed)
        }
        guard !sections.isEmpty else { return nil }

        let combined = sections.joined(separator: "\n\n")
        // A migrated prompt that blew the limit would fail to save and leave the user
        // with nothing; truncating keeps the beginning, which is where PROMPT.md was.
        let prompt = combined.count <= WritingProfile.characterLimit
            ? combined
            : String(combined.prefix(WritingProfile.characterLimit))
        return WritingProfile(prompt: prompt)
    }
}
