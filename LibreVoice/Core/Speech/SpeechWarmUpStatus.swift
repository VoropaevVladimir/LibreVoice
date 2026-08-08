//
//  SpeechWarmUpStatus.swift
//  LibreVoice
//

import Foundation
import Observation

/// What the background engine warm-up is doing, in a form the interface can show.
///
/// Warm-up is otherwise invisible, and invisible work that takes a minute and a half is
/// indistinguishable from a stuck app. Parakeet's first load compiles the conformer
/// encoder for the Neural Engine — roughly 85 seconds on an M-series Mac, once, cached to
/// disk afterwards. The user is entitled to see that happening and to know it ends.
///
/// Deliberately a separate type from ``SpeechEngineWarmUp``. That one is an actor doing
/// slow work off the main thread; this is main-actor observable state a `View` can read
/// directly. Merging them would force every reader to `await` an actor mid-render.
@Observable
@MainActor
final class SpeechWarmUpStatus {
    /// The engine currently being compiled, or `nil` when nothing is in flight.
    private(set) var preparingEngineID: SpeechEngineID?

    /// Engines whose first-load cost has already been paid this launch.
    private(set) var readyEngineIDs: Set<SpeechEngineID> = []

    /// Whether `engineID` is being compiled right now.
    func isPreparing(_ engineID: SpeechEngineID?) -> Bool {
        guard let engineID else { return false }
        return preparingEngineID == engineID
    }

    func beganPreparing(_ engineID: SpeechEngineID) {
        preparingEngineID = engineID
    }

    func finishedPreparing(_ engineID: SpeechEngineID, succeeded: Bool) {
        if preparingEngineID == engineID {
            preparingEngineID = nil
        }
        if succeeded {
            readyEngineIDs.insert(engineID)
        }
    }
}
