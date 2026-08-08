//
//  ModelFile.swift
//  LibreVoice
//

import Foundation

/// One file that makes up a model.
///
/// This type exists because the models LibreVoice ships are not single files. An MLX
/// Whisper model is a Hugging Face repository — a `config.json` plus a multi-gigabyte
/// `weights.npz` (or `weights.safetensors`) — so "download the model" means fetching a
/// *set* of files and keeping them together. A single-file backend (whisper.cpp's one
/// `.bin`) is just the degenerate case of a model with one file.
///
/// The checksum is **required**, not optional. Integrity is the entire security premise
/// of downloading models, so the type makes it impossible to describe a file without the
/// fingerprint that will be checked against it.
nonisolated struct ModelFile: Sendable, Hashable, Codable {
    /// Where this file goes within the model's folder, e.g. `config.json`.
    ///
    /// Treated as untrusted input when it becomes a path: the repository rejects any
    /// value containing a path separator or `..`, so a hostile catalog cannot write
    /// outside the model's own directory.
    let path: String

    /// Where to fetch the file from. **Must be HTTPS** — enforced at download time.
    let url: URL

    /// The expected size, for the disk-space check and progress.
    let sizeBytes: Int64

    /// The SHA-256 the downloaded bytes must match before the file is kept.
    let sha256: ModelChecksum

    init(path: String, url: URL, sizeBytes: Int64, sha256: ModelChecksum) {
        self.path = path
        self.url = url
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
    }
}
