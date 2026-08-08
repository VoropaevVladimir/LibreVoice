//
//  CarbonHotkeyService.swift
//  LibreVoice
//

import Carbon.HIToolbox
import Foundation

/// Registers system-wide shortcuts with Carbon's `RegisterEventHotKey`.
///
/// Carbon is ancient and, for this one job, still correct. The modern-looking
/// alternative — a `CGEventTap` — would require Input Monitoring permission, hand
/// LibreVoice every keystroke the user types, and put the app on the critical path of
/// the entire input system. `RegisterEventHotKey` needs no permission at all and only
/// ever hears the exact combination it registered. For an app whose pitch is "your data
/// stays yours", asking for less access is worth using an old API.
///
/// ## Why this is split in two
///
/// Carbon's event target *is* the main run loop, so every call here must happen on the
/// main actor. But ``HotkeyService`` is a `nonisolated` protocol, and a main-actor type
/// cannot witness nonisolated requirements. So the service is a `nonisolated` shell that
/// hops to ``CarbonHotkeyRegistry``, which is main-actor isolated and owns all the state
/// and every Carbon call. The hop is explicit and stated once, rather than assumed in
/// twelve places.
nonisolated final class CarbonHotkeyService: HotkeyService {
    /// Fires when a registered shortcut is pressed or released.
    ///
    /// - Important: A single consumer only. Two `for await` loops over one `AsyncStream`
    ///   split the events between them rather than each seeing all of them.
    let events: AsyncStream<HotkeyEvent>

    private let registry: CarbonHotkeyRegistry

    /// Main-actor isolated because the registry it builds is, and because the app is
    /// assembled on the main actor anyway.
    @MainActor
    init(logger: any Logger = NullLogger()) {
        let (stream, continuation) = AsyncStream.makeStream(of: HotkeyEvent.self)
        self.events = stream
        self.registry = CarbonHotkeyRegistry(continuation: continuation, logger: logger)
    }

    func register(_ shortcut: HotkeyShortcut, for id: HotkeyID) async throws {
        try await MainActor.run {
            try registry.register(shortcut, for: id)
        }
    }

    func unregister(_ id: HotkeyID) async {
        await MainActor.run {
            registry.unregister(id)
        }
    }

    func unregisterAll() async {
        await MainActor.run {
            registry.unregisterAll()
        }
    }
}

/// Owns every Carbon registration, on the main actor.
///
/// `EventHotKeyRef` is an opaque pointer and emphatically not `Sendable`. Confining it
/// here means it never crosses an isolation boundary, which is what makes the whole
/// service safe under strict concurrency rather than merely quiet about it.
@MainActor
private final class CarbonHotkeyRegistry {
    /// A live Carbon registration.
    ///
    /// `nonisolated` so that `deinit` — which is not main-actor isolated — can still read
    /// `ref` in order to unregister it. Without this the cleanup below would not compile.
    private nonisolated struct Registration {
        let ref: EventHotKeyRef
        let shortcut: HotkeyShortcut
    }

    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    private let logger: any Logger

    private var registrations: [HotkeyID: Registration] = [:]

    /// Maps the numeric id Carbon reports back to our identifier.
    private var idsByCarbonID: [UInt32: HotkeyID] = [:]

    private var nextCarbonID: UInt32 = 1
    private var handler: EventHandlerRef?

    init(continuation: AsyncStream<HotkeyEvent>.Continuation, logger: any Logger) {
        self.continuation = continuation
        self.logger = logger
    }

    // `isolated deinit` (SE-0371) so the cleanup below can touch main-actor state. A
    // plain `deinit` is nonisolated and cannot read `registrations` or `handler`, both of
    // which wrap non-Sendable Carbon pointers — and this cleanup is not optional.
    isolated deinit {
        // This is a memory-safety requirement, not tidiness. The installed event handler
        // holds an *unretained* pointer to `self` (see `installHandlerIfNeeded`). If this
        // object were freed with the handler still installed, the next press of a
        // registered shortcut would resurrect that dangling pointer and use freed memory.
        //
        // Every hotkey is unregistered too: a Carbon registration is process-wide and
        // outlives the object that made it, so leaving one behind would keep ⌥⌘D claimed
        // by a service that no longer exists.
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        if let handler {
            RemoveEventHandler(handler)
        }
        continuation.finish()
    }

    /// The four-character code identifying LibreVoice's hotkeys, so a press can be told
    /// apart from one belonging to another Carbon client in this process.
    private static let signature: OSType = {
        Array("LVCE".utf8).reduce(OSType(0)) { ($0 << 8) + OSType($1) }
    }()

    func register(_ shortcut: HotkeyShortcut, for id: HotkeyID) throws {
        unregister(id)
        installHandlerIfNeeded()

        let carbonID = nextCarbonID
        nextCarbonID += 1

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.modifiers.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: carbonID),
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            logger.error(
                "Couldn't register \(shortcut.displayString) (status \(status)).",
                category: .hotkeys
            )
            if status == OSStatus(eventHotKeyExistsErr) {
                throw HotkeyError.shortcutAlreadyInUse(shortcut)
            }
            throw HotkeyError.registrationFailed(status: status)
        }

        registrations[id] = Registration(ref: ref, shortcut: shortcut)
        idsByCarbonID[carbonID] = id
        logger.info("Registered \(shortcut.displayString) for “\(id.rawValue)”.", category: .hotkeys)
    }

    func unregister(_ id: HotkeyID) {
        guard let registration = registrations.removeValue(forKey: id) else { return }

        UnregisterEventHotKey(registration.ref)
        idsByCarbonID = idsByCarbonID.filter { $0.value != id }
        logger.info("Unregistered “\(id.rawValue)”.", category: .hotkeys)
    }

    func unregisterAll() {
        for id in Array(registrations.keys) {
            unregister(id)
        }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }

        // Both phases: push-to-talk needs the release as much as the press.
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        // `self` is passed unretained, because retaining would create a cycle that keeps
        // the service alive forever. The price is that this pointer dangles the moment
        // this object is freed, so `deinit` *must* remove the handler — that is a
        // correctness contract between the two, not a cleanup nicety.
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            specs.count,
            &specs,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )

        if status != noErr {
            logger.error("Couldn't install the hotkey event handler (status \(status)).", category: .hotkeys)
        }
    }

    /// Called from the Carbon event handler when one of our shortcuts fires.
    func handle(carbonID: UInt32, phase: HotkeyPhase) {
        guard let id = idsByCarbonID[carbonID] else { return }
        logger.debug("Hotkey “\(id.rawValue)” \(phase == .pressed ? "pressed" : "released").", category: .hotkeys)
        continuation.yield(HotkeyEvent(id: id, phase: phase))
    }
}

/// Carbon's C callback for a hotkey press.
///
/// Top-level and non-capturing so it converts to the `@convention(c)` function pointer
/// `InstallEventHandler` expects.
private nonisolated func hotkeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let context else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let phase: HotkeyPhase = GetEventKind(event) == UInt32(kEventHotKeyReleased) ? .released : .pressed

    // The reference is recovered outside the closure so that only it — a main-actor
    // class, and therefore `Sendable` — is captured, rather than the raw pointer.
    let registry = Unmanaged<CarbonHotkeyRegistry>.fromOpaque(context).takeUnretainedValue()
    let carbonID = hotKeyID.id

    // Carbon delivers these on the main run loop, so this is already the main actor —
    // the compiler simply cannot see that across a C function pointer.
    MainActor.assumeIsolated {
        registry.handle(carbonID: carbonID, phase: phase)
    }

    return noErr
}

private nonisolated extension HotkeyShortcut.Modifiers {
    /// The same modifiers expressed as Carbon's flags.
    ///
    /// The translation lives here, in the Carbon adapter, so ``HotkeyShortcut`` in
    /// `Core` stays a plain value that knows nothing about any framework.
    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }
}
