//
//  WritingProfileViewModel.swift
//  LibreVoice
//

import AppKit
import Foundation
import Observation

/// Drives the Writing Profile screen: one prompt, edited and saved as you type.
///
/// Saving is automatic and debounced. Typing is continuous and disks are not, so every
/// keystroke writing a file would be wasteful; waiting for an explicit Save would mean
/// losing work to a closed window. A short quiet period after the last keystroke is the
/// behaviour people expect from a native editor, and it is what this does.
@Observable
@MainActor
final class WritingProfileViewModel {
    /// The prompt being edited. Bound directly to the editor.
    var prompt: String = "" {
        didSet {
            guard prompt != oldValue, hasLoaded else { return }
            scheduleSave()
        }
    }

    /// What the screen last did with the prompt, shown quietly under the editor.
    private(set) var status: Status = .idle

    /// Whether the stored prompt has been read yet. Until it has, changes to `prompt`
    /// are the load itself and must not trigger a save.
    private(set) var hasLoaded = false

    enum Status: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    private let store: any WritingProfileStoring
    private var saveTask: Task<Void, Never>?

    /// How long to wait after the last keystroke before writing to disk.
    private let saveDelay: Duration

    init(container: any ServiceContainer, saveDelay: Duration = .milliseconds(600)) {
        self.store = container.writingProfile
        self.saveDelay = saveDelay
    }

    /// Reads the stored prompt.
    func load() async {
        let profile = await store.load()
        prompt = profile.prompt
        hasLoaded = true
        status = .idle
    }

    // MARK: - Saving

    private func scheduleSave() {
        status = .saving
        saveTask?.cancel()
        saveTask = Task { [saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    /// Writes the prompt now, without waiting for the debounce.
    ///
    /// Called when the screen goes away: a pending save that never ran would silently
    /// discard whatever was typed in the last half second.
    func flush() async {
        guard hasLoaded, status == .saving else { return }
        saveTask?.cancel()
        await save()
    }

    private func save() async {
        do {
            try await store.save(WritingProfile(prompt: prompt))
            status = .saved
        } catch {
            status = .failed(
                (error as? LocalizedError)?.errorDescription
                    ?? String(localized: "The prompt couldn't be saved.")
            )
        }
    }

    // MARK: - Actions

    /// Replaces the prompt with LibreVoice's default.
    func resetToDefault() {
        prompt = WritingProfile.defaultPrompt
    }

    /// Puts the prompt on the clipboard.
    func copyPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
    }

    /// Replaces the prompt with the clipboard's text.
    ///
    /// This is the other half of the generator workflow: the user pastes what an external
    /// AI produced. Whitespace-only clipboards are ignored rather than wiping the prompt.
    func pastePrompt() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        prompt = text
    }

    /// Copies the generator template for an external AI.
    ///
    /// LibreVoice contacts nothing: the user pastes this into ChatGPT, Claude, Gemini or
    /// Grok themselves, along with their own writing, and brings the answer back.
    func copyGeneratorTemplate() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.generatorTemplate, forType: .string)
    }

    /// Whether the prompt differs from the shipped default.
    var isCustomised: Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            != WritingProfile.defaultPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// How close the prompt is to the limit, for the character counter.
    var characterCount: Int { prompt.count }
    var characterLimit: Int { WritingProfile.characterLimit }

    /// The instruction the user hands to an external AI.
    ///
    /// Loaded from the bundled template so it can be revised without touching code, and
    /// deliberately not localised: it addresses the AI, and it tells that AI to answer in
    /// whatever language the user's own writing is in.
    static let generatorTemplate: String = {
        if let url = Bundle.main.url(forResource: "PromptGeneratorTemplate", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        return """
        Analyse how I write and produce one system prompt for a local model that corrects \
        my dictated text: improve punctuation, spacing, capitalisation and grammar while \
        preserving my wording, terminology and language. It must never summarise, invent, \
        or answer the text. Return the prompt as plain text in one code block.

        Here is my writing:
        """
    }()
}
