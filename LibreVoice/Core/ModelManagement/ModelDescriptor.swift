//
//  ModelDescriptor.swift
//  LibreVoice
//

import Foundation

/// Which languages a model can transcribe.
nonisolated enum ModelLanguageSupport: String, Sendable, Hashable, Codable {
    /// Trained on many languages.
    case multilingual

    /// English only. Smaller and faster, at the cost of every other language.
    case englishOnly

    var displayName: String {
        switch self {
        case .multilingual: String(localized: "Multilingual")
        case .englishOnly: String(localized: "English only")
        }
    }
}

/// Everything needed to offer, download, verify and store one speech model.
///
/// A descriptor is plain `Codable` data on purpose: the catalog it comes from is meant to
/// live where the distributor controls it — bundled today, hosted on a website tomorrow —
/// so new models can be published without shipping an app update. That also makes a
/// descriptor **untrusted input**: every file URL is checked for HTTPS before use, and
/// every file path is checked for traversal before it touches the disk.
///
/// A model is a *set* of ``ModelFile``s (see that type for why), all installed together
/// into one folder named after the model.
nonisolated struct ModelDescriptor: Sendable, Identifiable, Hashable, Codable {
    let id: ModelIdentifier

    /// The engine that consumes this model, tying it to a ``SpeechEngineID``.
    let engineID: SpeechEngineID

    /// The name shown in the model list, such as "Whisper Small".
    let displayName: String

    /// One line describing the trade-off, shown under the name.
    let summary: String

    /// The languages this model handles.
    let languageSupport: ModelLanguageSupport

    /// The files that make up the model. Never empty in a valid catalog.
    let files: [ModelFile]

    init(
        id: ModelIdentifier,
        engineID: SpeechEngineID,
        displayName: String,
        summary: String,
        languageSupport: ModelLanguageSupport = .multilingual,
        files: [ModelFile]
    ) {
        self.id = id
        self.engineID = engineID
        self.displayName = displayName
        self.summary = summary
        self.languageSupport = languageSupport
        self.files = files
    }

    /// The combined size of every file, for the disk-space check and the UI.
    var totalSizeBytes: Int64 {
        files.reduce(0) { $0 + $1.sizeBytes }
    }

    /// The total download size, formatted for display.
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }
}
