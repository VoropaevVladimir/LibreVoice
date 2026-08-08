//
//  WritingProfileStoring.swift
//  LibreVoice
//

import Foundation

/// Stores the user's personal prompt.
///
/// One value in, one value out. The store owns persistence and nothing else: no
/// formatting, no assembly, no interpretation of what the prompt says. That keeps the
/// prompt the user edits and the prompt the model receives literally the same string.
nonisolated protocol WritingProfileStoring: Sendable {
    /// The stored profile, or the default when nothing has been written yet.
    func load() async -> WritingProfile

    /// Persists `profile`.
    ///
    /// - Throws: ``WritingProfileError`` if the prompt is rejected or cannot be written.
    func save(_ profile: WritingProfile) async throws
}
