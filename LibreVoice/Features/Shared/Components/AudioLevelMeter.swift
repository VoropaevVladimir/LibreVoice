//
//  AudioLevelMeter.swift
//  LibreVoice
//

import SwiftUI

/// A row of bars that rises and falls with the microphone level.
///
/// Its real job is trust: it is the only way to tell "LibreVoice is hearing me" from
/// "LibreVoice is frozen", and it makes the microphone's state visible at a glance.
struct AudioLevelMeter: View {
    let level: AudioLevel

    /// Whether the meter is live. When false it rests at zero rather than freezing at
    /// the last value, which would look like a hang.
    var isActive: Bool

    private let barCount = 5

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(fill(for: index))
                    .frame(width: 3, height: height(for: index))
            }
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone level")
        .accessibilityValue(accessibilityValue)
        .accessibilityHidden(!isActive)
    }

    /// The level this bar responds to: bar 0 lights at the faintest sound, bar 4 only
    /// when the input is nearly clipping.
    private func threshold(for index: Int) -> Float {
        Float(index + 1) / Float(barCount)
    }

    private func height(for index: Int) -> CGFloat {
        let base: CGFloat = 6
        let maximum: CGFloat = 24
        guard isActive else { return base }

        // RMS rather than peak: it tracks perceived loudness, so the meter moves the way
        // the sound feels rather than spiking on every transient.
        let normalized = CGFloat(min(level.rms * 2.5, 1))
        let barShare = CGFloat(threshold(for: index))
        let filled = max(0, min(1, (normalized - barShare + 0.2) / 0.2))
        return base + (maximum - base) * filled
    }

    private func fill(for index: Int) -> Color {
        guard isActive else { return .secondary.opacity(0.3) }
        if level.isClipping && threshold(for: index) > 0.8 { return .orange }
        return level.rms * 2.5 >= threshold(for: index) - 0.2 ? .accentColor : .secondary.opacity(0.3)
    }

    private var accessibilityValue: String {
        if level.isClipping { return "Too loud" }
        return "\(Int(level.rms * 100)) percent"
    }
}

#Preview("Levels") {
    VStack(spacing: 16) {
        AudioLevelMeter(level: .silent, isActive: false)
        AudioLevelMeter(level: AudioLevel(peak: 0.2, rms: 0.1), isActive: true)
        AudioLevelMeter(level: AudioLevel(peak: 0.6, rms: 0.35), isActive: true)
        AudioLevelMeter(level: AudioLevel(peak: 1.0, rms: 0.8), isActive: true)
    }
    .padding()
}
