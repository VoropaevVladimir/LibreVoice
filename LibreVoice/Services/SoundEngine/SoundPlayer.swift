//
//  SoundPlayer.swift
//  LibreVoice
//

import AVFoundation
import Foundation

/// Plays synthesised sounds through `AVAudioEngine`.
///
/// An `actor`, because the engine and its player node are shared mutable state that
/// the experience coordinator drives from the main actor while audio renders on its own
/// real-time thread.
///
/// Two design decisions worth stating:
///
/// - **Sounds are rendered ahead of time and cached, not streamed.** Each one is a few
///   thousand frames of arithmetic; computing it on the audio thread would risk a
///   dropout, and computing it fresh on every play would repeat that work for no gain.
///   The cache is keyed by sound *and* theme, so switching modes re-renders once.
/// - **The engine starts lazily and stays running.** Starting `AVAudioEngine` takes
///   milliseconds that would otherwise land between the user's keypress and the first
///   sound — exactly where latency is most noticeable.
actor SoundPlayer: SoundPlaying {
    private let synthesizer: AudioSynthesizer
    private let logger: any Logger

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private var format: AVAudioFormat?
    private var isRunning = false
    private var cache: [CacheKey: AVAudioPCMBuffer] = [:]

    /// Cached buffers are per sound *and* per theme: the same gesture sounds different
    /// in each mode, so one buffer per sound would play the wrong character.
    private struct CacheKey: Hashable {
        let sound: DictationSound
        let mode: DictationMode
    }

    init(sampleRate: Double = 48_000, logger: any Logger = NullLogger()) {
        self.synthesizer = AudioSynthesizer(sampleRate: sampleRate)
        self.logger = logger
    }

    // MARK: - SoundPlaying

    func play(_ sound: DictationSound, mode: DictationMode) async {
        guard prepareEngine() else { return }
        guard let buffer = buffer(for: sound, mode: mode) else { return }

        schedule(buffer)
    }

    /// Hands a buffer to the player node and starts it.
    ///
    /// Deliberately not `async`. `scheduleBuffer` has an `async` overload that suspends
    /// until playback *finishes*, which would make every caller wait out the sound —
    /// and in an async context the compiler steers towards exactly that. Keeping this
    /// method synchronous makes the fire-and-forget overload the only candidate.
    ///
    /// The node is not stopped first: two short sounds may legitimately overlap — the
    /// stop motif can still be decaying as the next gesture begins — and cutting one off
    /// mid-decay would click.
    private func schedule(_ buffer: AVAudioPCMBuffer) {
        playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        playerNode.play()
    }

    // MARK: - Engine

    /// Starts the engine on first use. Returns `false` if audio is unavailable.
    ///
    /// A failure here is logged and swallowed: no sound is a small loss, and an app that
    /// refused to dictate because it could not chime would be absurd.
    private func prepareEngine() -> Bool {
        if isRunning { return true }

        let format = AVAudioFormat(
            standardFormatWithSampleRate: synthesizer.sampleRate,
            channels: 1
        )
        guard let format else { return false }
        self.format = format

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            isRunning = true
            return true
        } catch {
            logger.warning("Couldn't start the audio engine; sounds are off.", category: .audio)
            return false
        }
    }

    /// The rendered buffer for a sound, synthesised once and kept.
    private func buffer(for sound: DictationSound, mode: DictationMode) -> AVAudioPCMBuffer? {
        let key = CacheKey(sound: sound, mode: mode)
        if let cached = cache[key] { return cached }

        guard let format else { return nil }
        let samples = synthesizer.render(sound, theme: SoundTheme.theme(for: mode))
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channel = buffer.floatChannelData
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel[0].update(from: source.baseAddress!, count: source.count)
        }

        cache[key] = buffer
        return buffer
    }
}
