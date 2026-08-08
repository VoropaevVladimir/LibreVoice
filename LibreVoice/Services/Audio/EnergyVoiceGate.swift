//
//  EnergyVoiceGate.swift
//  LibreVoice
//

import Foundation

/// Voice activity detection: keeps the frames that contain speech, drops the silence.
///
/// This is the VAD stage of the dictation pipeline, and it exists because of a failure
/// observed live: Whisper *hallucinates* on silence. Left with a minute of quiet room
/// tone around one sentence, it invented an entire dialogue. Removing the silence before
/// inference kills the hallucinations at the source — and, as a bonus, transcribing 5
/// seconds of actual speech instead of 2 minutes of mostly-quiet audio is dramatically
/// faster.
///
/// Energy-based on purpose: a learned VAD model would be another download and another
/// inference engine, all to answer "is anyone talking?" — which an adaptive energy
/// threshold answers well enough at the gate. Whisper's own no-speech detection remains
/// behind it as the second line.
nonisolated struct EnergyVoiceGate: Sendable {
    /// Analysis frame length. 30 ms is the conventional VAD frame: short enough to
    /// catch word onsets, long enough for a stable RMS.
    let frameDuration: TimeInterval = 0.03

    /// Speech kept on each side of a detected region, so onsets and trailing
    /// consonants — which sit near the noise floor — survive the gate.
    let paddingDuration: TimeInterval = 0.24

    /// Pauses longer than this are compressed to this length, keeping sentence rhythm
    /// (Whisper uses pauses for punctuation) without leaving room to hallucinate in.
    let maximumPauseDuration: TimeInterval = 0.5

    /// The quietest RMS ever considered speech, whatever the adaptive floor says.
    let absoluteThreshold: Float = 0.004

    /// Result of gating: the audio to transcribe, and what was measured on the way.
    struct GatedAudio: Sendable {
        /// The kept samples — speech regions with padding, pauses compressed.
        let samples: [Float]

        /// Seconds of speech detected (before padding).
        let speechDuration: TimeInterval

        /// Whether anything worth transcribing was found.
        var containsSpeech: Bool { speechDuration >= 0.3 }
    }

    /// Filters `samples`, returning only the regions that contain speech.
    func gate(_ samples: [Float], sampleRate: Double) -> GatedAudio {
        let frameLength = max(1, Int(frameDuration * sampleRate))
        guard samples.count >= frameLength else {
            return GatedAudio(samples: [], speechDuration: 0)
        }

        // 1. Per-frame RMS.
        let frameCount = samples.count / frameLength
        var rms = [Float](repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            var sum: Float = 0
            let start = frame * frameLength
            for i in start..<(start + frameLength) {
                sum += samples[i] * samples[i]
            }
            rms[frame] = (sum / Float(frameLength)).squareRoot()
        }

        // 2. Adaptive threshold. The noise floor is the 20th-percentile frame — quiet
        // rooms and noisy cafés land in different places — and speech must clear a
        // multiple of it. The 90th-percentile cap handles the degenerate case that
        // breaks naïve adaptive gates: in a recording that is *all* speech, the "noise
        // floor" is itself loud, and floor × multiplier would reject everything. The
        // cap ties the threshold under the loud frames, so all-speech audio passes
        // whole. The absolute minimum stays under everything as the final floor.
        let sorted = rms.sorted()
        let noiseFloor = sorted[sorted.count / 5]
        let loudFrames = sorted[min(sorted.count - 1, sorted.count * 9 / 10)]
        let threshold = max(absoluteThreshold, min(noiseFloor * 2.5, loudFrames * 0.5))

        var isSpeech = rms.map { $0 >= threshold }
        let speechFrames = isSpeech.lazy.filter { $0 }.count
        let speechDuration = TimeInterval(speechFrames) * frameDuration

        // 3. Dilate: pad speech regions so word edges survive.
        let paddingFrames = Int(paddingDuration / frameDuration)
        isSpeech = Self.dilated(isSpeech, by: paddingFrames)

        // 4. Assemble, compressing long pauses instead of keeping them.
        let maximumPauseFrames = Int(maximumPauseDuration / frameDuration)
        var kept: [Float] = []
        kept.reserveCapacity(samples.count)
        var pendingPause = 0

        for frame in 0..<frameCount {
            let range = (frame * frameLength)..<((frame + 1) * frameLength)
            if isSpeech[frame] {
                if pendingPause > 0 {
                    // Insert the compressed pause as silence: cheap, and Whisper only
                    // needs the gap's existence, not its noise.
                    let pauseFrames = min(pendingPause, maximumPauseFrames)
                    kept.append(contentsOf: [Float](repeating: 0, count: pauseFrames * frameLength))
                    pendingPause = 0
                }
                kept.append(contentsOf: samples[range])
            } else if !kept.isEmpty {
                pendingPause += 1
            }
        }

        return GatedAudio(samples: kept, speechDuration: speechDuration)
    }

    /// Widens every `true` run by `radius` on both sides.
    private static func dilated(_ mask: [Bool], by radius: Int) -> [Bool] {
        guard radius > 0 else { return mask }
        var result = mask
        for index in mask.indices where mask[index] {
            let lower = max(0, index - radius)
            let upper = min(mask.count - 1, index + radius)
            for j in lower...upper { result[j] = true }
        }
        return result
    }
}
