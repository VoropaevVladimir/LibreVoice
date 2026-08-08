# LibreVoice Architecture

Every decision below is written as *what was chosen*, *what it was chosen over*, and
*what it costs*. A decision without a stated cost is usually a decision nobody actually
made.

---

## 1. Layers

```
App/        Composition roots and scenes. The only place that names concrete types.
  Previews/   The fake container. A composition root too, so it lives here.
Core/       Contracts, domain models, framework-free domain logic.
Services/   Concrete adapters to system frameworks (AVFoundation, os.log, Carbon, AX).
Features/   UI. One folder per screen: View + ViewModel.
Tests/      Unit tests, built against Core with fakes.
```

The rule that keeps this honest is a single sentence:

> **`Core` may import Foundation and Observation. Nothing else.**

Verify it at any time:

```bash
grep -rh "^import" LibreVoice/Core --include="*.swift" | sort -u
# import Foundation
# import Observation
```

`Observation` earns its place because `AppSettings` and `DictationCoordinator` are
observable domain objects; it is a pure Swift framework, not a UI one. `SwiftUI` does
not: `ServiceContainerEnvironment.swift` lives in `Features/Shared/Environment/` for
exactly this reason, even though it is "about" the container.

`Core` does not know that AVFoundation, Carbon, Whisper, or the App Sandbox exist. Every
one of those lives behind a protocol in `Core` and is implemented in `Services`. The
payoff is not architectural tidiness — it is that the entire dictation pipeline can be
tested in 0.02 seconds with no microphone, no model, and no TCC prompt. `Tests/` is the
proof: 112 tests, none of which touch hardware.

**Dependency direction:** `App → Features → Core ← Services`.
`Core` depends on nothing. `Services` depends only on `Core`. `Features` never imports a
`Services` type. If a concrete type's name appears outside `App/AppEnvironment.swift` or
its own folder, a dependency has leaked.

### Why folders rather than Swift packages

The spec asked for modular architecture, and local SPM packages would enforce these
boundaries at compile time rather than by convention. Folders were chosen because the
project uses Xcode 16+ **file-system synchronized groups**: files on disk are compiled
automatically, so the structure is real without any `project.pbxproj` bookkeeping.

The cost is honest: the layering is currently a convention, not a compiler rule. Nothing
stops someone importing AVFoundation into `Core` tomorrow. The mitigation is that the
protocol boundaries already exist, so extracting `Core` into a package later is a move
operation rather than a redesign — the hard part is already done.

---

## 2. Dependency injection: a typed container, not a registry

`Core/DependencyInjection/ServiceContainer.swift` is a protocol with typed properties,
not the conventional bag of closures:

```swift
// What LibreVoice does NOT do:
container.register(Logger.self) { OSLogLogger() }
let logger = container.resolve(Logger.self)   // optional, or a trap

// What it does:
@MainActor protocol ServiceContainer {
    var logger: any Logger { get }
    var dictation: DictationCoordinator { get }
    // ...
}
```

Three reasons:

1. **A forgotten dependency should not compile.** With `resolve`, it compiles and crashes
   at launch — or worse, in a branch nobody exercised until a user did.
2. **No force unwraps, no `fatalError`.** A type-erased registry must do one or the other
   when a lookup misses. Typed properties cannot miss.
3. **The graph is readable.** That one file *is* the list of what LibreVoice is made of.

**The cost:** no run-time registration. A dictation app does not need it — the roster is
known at compile time. The one thing that genuinely varies is the set of speech engines,
and that has its own registry, because that variation is real.

Two conformances exist: `AppEnvironment` (real) and `PreviewServiceContainer` (fakes,
every dependency overridable). Every `#Preview` in the project uses the latter, which is
why no preview can touch the real microphone.

Both live in `App/`, and that placement is the rule doing its job rather than a filing
preference. `PreviewServiceContainer` composes, composing means naming concrete types,
and `Core` may not name any — so a container cannot live in `Core` however much it feels
like infrastructure. Only the `ServiceContainer` *protocol* belongs there.

The invariant is greppable:

```bash
grep -rn 'OSLogLogger()\|CarbonHotkeyService\|AVAudioEngineCaptureService' LibreVoice/Core --include='*.swift'
# (doc comments only — no code)
```

---

## 3. The speech engine plug-in system

**Roster (Sprint 2).** Three engines are declared: **NVIDIA Parakeet** (recommended,
shipping — Core ML on the Neural Engine), **Whisper** via whisper.cpp (shipping), and
**Moonshine** (declared, no runtime yet — registers as `PlannedSpeechEngineFactory`:
visible in the picker, disabled, with the reason stated). Apple's `Speech` framework is
deliberately **not** an option — LibreVoice ships its own engines rather than delegating to
macOS Dictation.

### Parakeet

Inference comes from **FluidAudio** (Apache-2.0), which supplies the Core ML conversions
and the RNN-T decode loop. Writing that decoder by hand was the alternative and was
rejected: it is the kind of code that fails quietly and produces plausible-but-wrong text,
the worst failure mode a dictation app has.

What LibreVoice keeps is the part its promises rest on: **models come through LibreVoice's
own catalog**, every file verified against a SHA-256 pinned to a specific Hugging Face
revision, installed into LibreVoice's own folder. `ParakeetEngine` hands FluidAudio a
directory; FluidAudio never reaches the network. The catalog entry is the v3 set the
`.v3` / `.int8` loader expects — `Preprocessor`, `Encoder`, `Decoder`, `JointDecisionv3`
and `parakeet_vocab.json`, 21 files, 483 MB — and its **model id is the repository's folder
name**, because the loader resolves the vocabulary by that name beside the models.

A Core ML model is a *directory*, which is why `FileSystemModelRepository` learned safe
nested paths (§ below). Parakeet batches the utterance like Whisper rather than streaming:
streaming would change the experience arc, not just one file, so it is separate work.

**Nested model paths.** File paths in the catalog may now contain `/`. The guard moved
from "reject any separator" to validating *every component* — no empty parts (so absolute
paths and `a//b` are refused), no `.` or `..`, a conservative character set, and a depth
limit. The worst a hostile catalog can do is create a nested folder inside the directory it
was already allowed to write. Pinned by tests that install a bundle and refuse five spellings
of traversal.

This is the part the spec cared about most, so it is worth being precise about what makes
the claim true rather than aspirational.

```
SpeechRecognitionEngine   audio in → text out. Names no technology.
SpeechEngineDescriptor    metadata readable WITHOUT building the engine.
SpeechEngineFactory       builds one engine; answers "can this run here?" cheaply.
SpeechEngineRegistry      an actor holding the roster. Populated once, at launch.
SpeechEngineProviding     read-only view. What everyone else depends on.
```

Four properties make an engine pluggable without touching the rest of the app:

- **`Core` never learns an engine's name.** `SpeechEngineID` is a `String` wrapper, not an
  `enum`. An `enum` would have to list every engine, putting the roster in shared code and
  making "add an engine" a change to `Core`. Engines name themselves.
- **Audio arrives as an `AsyncStream`.** A streaming engine consumes it as it arrives; a
  batch engine (whisper.cpp wants a whole utterance) collects and transcribes at the end.
  The caller cannot tell which it got.
- **Descriptors are readable without instantiating.** The settings picker lists engines
  that need multi-gigabyte models without loading any of them.
- **Registration is a composition-root privilege.** `SpeechEngineProviding` has no
  `register`. Only `AppEnvironment` can add an engine.

`SpeechEngineSettingsView` is built entirely from descriptors. It has no idea Whisper
exists. Adding an engine makes a row appear there with no change to that file.

### ProcessingLocation is a type, not a Bool

```swift
enum ProcessingLocation {
    case onDevice
    case remote(host: String)
}
```

Where audio goes is the single most important thing a privacy-first app can state about a
backend, and the remote case has to name a host. An `isOnDevice: Bool` could not, and the
UI would need a special case for "the cloud one". Instead every row renders its own badge
from the descriptor: 🔒 *On device*, or ⚠️ *Sends audio to api.openai.com*.

### One engine is registered, and it is real

`AppEnvironment.registerSpeechEngines()` registers exactly one factory:
`WhisperCppEngineFactory`. Recognition is genuinely implemented — there is no stub emitting
canned text, because a fake that makes the app look finished lies to anyone who tries it.

The other backends in `PlannedSpeechEngines` are **descriptors only**. They are not
registered, so they never appear in the picker and can never be selected; the type exists
so the roadmap is written down somewhere the compiler can see it. Adding one for real is
still a single `register` call — see §9.

---

## 4. Concurrency

The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and
`SWIFT_APPROACHABLE_CONCURRENCY = YES` (Xcode 26 defaults), under Swift 6 language mode.
**Everything is `@MainActor` unless it says otherwise.**

This is right for a UI app and has one consequence worth internalising: `nonisolated` in
this codebase is load-bearing, never decoration. An unannotated `extension Logger` would
be main-actor isolated, and a logger that can only be called from the main actor is
useless to an audio tap. That exact mistake was caught by the compiler during the build.

| Type | Isolation | Why |
|---|---|---|
| `Logger`, and all value types in `Core` | `nonisolated` | Callable from audio callbacks and actors |
| `AVAudioEngineCaptureService` | `actor` | Owns engine state; taps arrive on a real-time thread |
| `SpeechEngineRegistry` | `actor` | Written at launch, read from sessions |
| `AccessibilityTextInsertionService` | `nonisolated` | AX calls block on other apps — must stay off the main thread |
| `CarbonHotkeyService` | `nonisolated` shell → `@MainActor` core | Carbon's event target *is* the main run loop |
| ViewModels, `AppSettings`, `DictationCoordinator` | `@MainActor` | Bound to UI |

### The one forced cast

The house rule is no force unwraps, and the codebase has exactly one exception:
`focused as! AXUIElement` in `AccessibilityTextInsertionService`. It stays because Swift
leaves no alternative — `as?` on a CoreFoundation type is a *compile error*
("will always succeed"), not a warning. The value's type is checked with `CFGetTypeID`
immediately before, which makes the cast provably safe rather than hopeful.

### Escapes from the checker

Three, each with a stated justification at the declaration:

- **`TapState: @unchecked Sendable`** — `AVAudioEngine` calls a tap block serially on one
  thread. The compiler cannot see that; the invariant is documented at the declaration.
- **`nonisolated(unsafe) let defaults: UserDefaults`** — documented thread-safe since
  before `Sendable` existed, never annotated. A gap in the annotation, not the guarantee.
- **`MainActor.assumeIsolated` in the Carbon C callback** — Carbon delivers on the main
  run loop; the compiler cannot know that across a `@convention(c)` function pointer.

The Carbon callback also holds an **unretained** pointer to the registry (retaining would
cycle). That makes `CarbonHotkeyRegistry`'s `isolated deinit` a memory-safety contract,
not a courtesy: it *must* `RemoveEventHandler` and `UnregisterEventHotKey`, or a later
keypress would call through a dangling pointer into freed memory. `isolated deinit`
(SE-0371) is what lets the deinitialiser touch that main-actor state to do it.

---

## 5. App Sandbox is off

**The decision that shapes the product.** Under the sandbox:

- ✅ Microphone works.
- ❌ Accessibility — typing into *other* apps — is blocked.
- ❌ `CGEvent`-based global hotkeys are blocked.

A dictation app that cannot type into the app you are working in is not a dictation app.
So: sandbox off, `TextInsertionService` uses the Accessibility API, distribution is
Developer ID + notarization via GitHub/Homebrew.

**The cost, stated plainly:** the Mac App Store is closed to this build. That is the same
trade Superwhisper and its peers make, and it was chosen deliberately rather than
discovered later.

`TextInsertionService` is still a protocol with no mention of *how* text arrives, so a
future sandboxed App Store build supplying a clipboard-based conformance would change
nothing else.

### Asking for less

LibreVoice requests exactly two permissions, one of them optional:

| Permission | Required | Why |
|---|---|---|
| Microphone | Yes | There is nothing to transcribe otherwise |
| Accessibility | **No** | Without it, text stays in LibreVoice instead of being typed |

**Input Monitoring is never requested.** Global hotkeys use Carbon's
`RegisterEventHotKey`, which needs no permission and only ever hears the exact combination
registered. The modern-looking `CGEventTap` would need Input Monitoring, would hand
LibreVoice every keystroke the user types, and would put the app on the critical path of
the entire input system. For an app whose pitch is "your data stays yours", an old API
that asks for nothing beats a new one that asks for everything.

### Hardened Runtime — the counterweight to no sandbox

`ENABLE_HARDENED_RUNTIME = YES`. This is not optional for LibreVoice, it is the mitigation
that makes "no sandbox" survivable:

- LibreVoice holds Microphone **and** Accessibility grants. Without the Hardened Runtime,
  any local process could inject a dylib into it (`DYLD_INSERT_LIBRARIES`) or attach a
  debugger and read its memory — and inherit those TCC grants. The permissions *you* gave
  the app would become someone else's capability. The Hardened Runtime closes library
  injection, unsigned-code execution, and task-port access by default.
- Notarization — the chosen distribution path — flatly requires it. A build without it
  cannot be notarized, so this and the Developer ID decision are the same decision.

The microphone still works because `ENABLE_RESOURCE_ACCESS_AUDIO_INPUT = YES` emits the
`com.apple.security.device.audio-input` entitlement the runtime then honours. Verify the
whole picture on any build:

```bash
codesign -dvvv --entitlements - LibreVoice.app
# Flags=...(runtime)              ← Hardened Runtime on
# com.apple.security.device.audio-input => true
```

(`com.apple.security.get-task-allow` also appears in local signed builds — Xcode injects
it for debugging. The Release *export* with a real Developer ID strips it; it never ships.)

---

## 6. Privacy, as structure rather than promise

Claims are cheap. These are load-bearing in the code:

- **Your voice never leaves the device.** Audio is captured, transcribed and discarded
  on-device. There is no code path that uploads audio or a transcript — the network is
  used *only* to download models (§6a), and that path carries neither.
- **Log records never contain speech.** Stated on `LogEntry`, enforced by review. Even
  `AccessibilityTextInsertionService` logs `"Inserted 42 characters"`, never the text.
- **Your speech is never written to disk.** `InMemoryLogStore` is a bounded ring buffer;
  there is no log file. `Transcript` lives in memory and dies with the session — the
  *absence* of a history feature is the feature. The only thing written to disk is a model
  the user chose to download.
- **The Activity screen shows every record**, with buttons to copy and to erase. "No
  telemetry" is unverifiable as a claim; a screen showing the entire log is checkable.

### The one honest caveat

An earlier version of this document claimed "no network code exists, verifiable with
`nm`." Adding model downloads made that false, and a false privacy claim is worse than a
weaker true one. The accurate statement is narrower and stronger: **no user data ever
leaves the Mac.** The single networking type, `URLSessionModelDownloader`, fetches model
files and nothing else — you can read it in one sitting and confirm it sends only a URL.
Everything the app links is inbound-only model fetching; there is no analytics SDK, no
crash reporter, no server to talk to.

### What an audit found (and what it did not)

A deliberate pass over the security surface, rather than a claim that one happened:

- **`com.apple.security.get-task-allow` was in release builds.** The debug entitlement
  that lets any process running as this user attach to LibreVoice and read its memory —
  microphone audio, transcripts, the personal prompt. It was there because `sign.sh` read
  entitlements back out of whatever Xcode had produced and re-applied them, which means
  never seeing what is being copied. Entitlements now come from
  `Scripts/release.entitlements`, a reviewable file, and the key is gone. This also
  unblocks notarisation, which it made impossible.
- **`disable-library-validation` stays, under protest.** Removing it was tried and
  measured: the app fails to launch, because library validation matches on Team ID and a
  self-signed certificate has none. It goes when release signing moves to a real
  Developer ID — the entitlements file records the test to re-run.
- **Downloads now have a ceiling** (`DownloadSizeLimit`). The checksum is the real
  integrity check, but it runs only once bytes are on disk; a hostile mirror could have
  filled the volume first. Anything past the catalog's declared size plus 1 MB is refused
  and reported as such, not as a cancellation.
- **The personal prompt is written `0600`**, its folder `0700`. `~/Library` is already
  `0700`, so this changes nothing today; it matters the moment the folder is backed up,
  synced or copied to a shared volume, where the mode is all that survives.
- **Nothing was found in the network path.** HTTPS enforced, HTTP redirects refused,
  ephemeral session, no cookies or cache, every one of the 31 catalog files pinned to a
  SHA-256. Path validation against a hostile catalog was already sound.
- **Nothing was found in logging.** Every call site logs counts and app names, never
  content.

---

## 6a. Downloading models

Whisper models are hundreds of megabytes to gigabytes, so they cannot be bundled — the app
downloads them. The product goal is that **the user never hunts for a model**: the catalog
names them in plain language and one button does the rest. The security work is what earns
the right to do that automatically.

```
Core/ModelManagement/     ModelDescriptor (a model = a set of ModelFiles), ModelChecksum,
                          ModelInstallState, ModelCatalog / ModelRepository / downloader protocols
Services/ModelManagement/ JSONModelCatalog (the trust anchor), URLSessionModelDownloader
                          (the only networking), FileChecksum (streaming SHA-256),
                          FileSystemModelRepository (the pipeline)
Resources/model-catalog.json   the shipped catalog: 6 MLX Whisper models, real HF URLs,
                               real pinned SHA-256 for every file
```

**A model is a set of files, not one file.** An MLX Whisper model is a Hugging Face repo —
`config.json` plus a multi-gigabyte `weights.npz`/`.safetensors` — so `ModelDescriptor`
holds a `[ModelFile]`, each with its own URL, size and required checksum. whisper.cpp's
single `.bin` is just the one-file case. The abstraction cost nothing and covers both.

**The trust model, chosen deliberately** (LibreVoice hosts the catalog, files come from
Hugging Face): the SHA-256 in *our* catalog is the anchor. Files can be served by anyone —
a swapped or corrupted file from a CDN is caught because it will not match the checksum the
distributor pinned. So even downloading from a third party, integrity rests on a value we
control.

The security properties, each tested (`Tests/ModelRepositoryTests.swift`) and, for the
happy path, verified against real Hugging Face downloads:

1. **HTTPS only** — a non-HTTPS URL is refused before a request; a redirect that downgrades
   to HTTP is refused mid-flight (Hugging Face legitimately redirects to a CDN, but only
   over HTTPS).
2. **Checksum verification** — every file is streamed through SHA-256 and compared,
   constant-time, to the catalog. One mismatch fails the whole model and deletes it. A
   model is loaded only if every byte is what the distributor published.
3. **Path-traversal safety** — the model id and every file path come from a catalog that
   may be hosted remotely, so both are validated to be plain names before touching disk. A
   catalog entry named `../../etc/…` is refused, not written.
4. **Atomic install** — files download into a staging directory and are moved into place
   only once all have verified. A cancelled or failed download never leaves a half-written
   model that looks installed.
5. **Ephemeral, data-free requests** — the download session has no cookies, cache or
   credentials, sends no identifying headers, and carries no audio or transcript.

The `FileSystemModelRepository` is an `actor`, and one bug worth recording came out of
testing it: progress updates arrive via detached tasks and could land *after* a terminal
state, resurrecting a finished install into a spinner. `reportProgress` now only refines an
existing `.downloading` state — a real race the fake-downloader tests would have shipped
past if they only checked the happy path.

---

## 7. UI

- **`Window`, not `WindowGroup`.** One dictation session means one main window. `WindowGroup`
  would let ⌘N spawn a second window onto the same session.
- **`MenuBarExtra` is the real interface.** Dictation happens *while working in another app*;
  the main window is somewhere you visit occasionally.
- **No `Settings` scene.** The Mac convention is a separate preferences window, but with
  this few screens it split a small interface across two windows and hid half of it behind
  a keystroke. Every screen lives in the one window's sidebar; ⌘, selects the settings
  section instead of opening anything.
- **Closing the window does not quit.** `AppDelegate.applicationShouldTerminate​AfterLastWindowClosed`
  returns `false`. The app is driven by a global shortcut from inside other apps, so the
  window is somewhere you visit — without this, SwiftUI would end the process with the last
  window and the shortcut would go quiet with no indication why. Quitting is deliberate,
  via the menu bar item. A consequence: the window — and the `.task` that calls
  `AppEnvironment.start()` — can be created more than once per launch, so `start()` guards
  itself with `hasStarted`. Without that guard a reopened window would bind a *second*
  listener to the shortcut stream, and one keypress would start then immediately stop
  dictation.
- **`menuBarOnly` drives the activation policy.** On by default: `NSApp.setActivationPolicy(.accessory)`
  drops the Dock tile and the app menu, leaving the menu bar item — the shape of a utility
  used from inside other apps. Turning it on force-enables the menu bar icon, because
  otherwise the two settings combine into an app that is running with no way to reach it.
- **The menu bar mark is the LV wordmark**, matching the app icon, not a microphone glyph a
  dozen other utilities also use. State moves to a small badge beside it (`menuBarBadgeSymbol`)
  and stays a *shape*: the menu bar is monochrome, so a colour-only status is no status.
- **The coordinator owns dictation state, not the view models.** The menu bar, the global
  hotkey and the main window all drive one session. A second copy of that state would
  eventually disagree with the first.
- **`DictationState` has no audio level payload.** Attaching it would republish the state
  sixty times a second and redraw every observing view, when only the meter cares. The
  level lives beside the state.
- **Banners, not alerts.** These are conditions ("the microphone is *still* not granted"),
  not events. A modal alert would demand dismissal every time the screen appeared.
- **Colour is never the only signal.** Every state carries a distinct SF Symbol, text, and
  an accessibility value.

---

## 8. What is real and what is not

Being explicit, because a skeleton that overstates itself wastes the next person's day.

**Real and working (updated for Sprint 2 — speech recognition ships):**
**Full offline dictation through whisper.cpp** (v1.9.1 official xcframework, Metal-
accelerated, mic → VAD → whisper → post-processing → insertion, verified live in
Russian) · energy VAD with silence compression (`EnergyVoiceGate` — born from a live
hallucination bug, see its doc comment) · per-segment no-speech filtering · three
dictation modes (Fast/Smart/Precision → `TranscriptProcessing` pipeline) · **Experience
Engine** (`ExperienceState` machine in Core + `ExperienceCoordinator`), floating
non-activating capsule that slides out from under the menu bar, Metal liquid wave /
particle / morph / glow renderers at 120 fps · **procedural sound engine** (§12) ·
microphone permission flow · audio capture with 48 kHz → 16 kHz mono conversion · global
hotkey (Carbon, push-to-talk) · Accessibility text insertion · model download with
checksum verification (GGML catalog, models stored in
`~/Library/Application Support/LibreVoice/Models/`) · **Precision architecture** (§15):
personal profile store, runtime context builder, language-model catalog (GGUF) and the
batch-enhance-insert pipeline, all live and tested behind the provider seam ·
default-model selection · settings
persistence · logging with in-app viewer · DI container · engine registry · menu-bar-only
mode · Liquid Glass app icon (§13) · English + Russian localisation · **112 tests**.

The capsule shows **no text**. Earlier builds revealed the transcript as it arrived
(`TypingRevealModel`, since removed): it turned a calm indicator into something you read
instead of the app you were dictating into. The wave says "heard you"; the words belong in
the destination, not in an overlay.

**Deliberately not implemented:**

| Gap | Why | Where |
|---|---|---|
| Streaming (live words while speaking) | whisper.cpp is batch; the Listening → Thinking → Typing arc is designed around that. The engine protocol already supports streaming for a future engine | `SpeechRecognitionEngine` |
| Learned VAD, custom terminology UI | Energy VAD and a seeded dictionary ship; both have seams for heavier replacements | `EnergyVoiceGate`, `TerminologyDictionary` |
| Whisper engines beyond whisper.cpp | v1 is deliberately single-engine; the registry stays ready for more | `AppEnvironment.registerSpeechEngines()` |
| Input device *selection* | Needs a CoreAudio UID → `AudioDeviceID` translation. Enumeration works; selection logs a warning instead of silently ignoring the setting | `AVAudioEngineCaptureService.start` |
| Shortcut recording | Needs a custom `NSView` intercepting key equivalents. Shown read-only and says so, rather than looking editable and not being | `ShortcutSettingsView` |
| Launch at login | `SMAppService`, not yet wired | — |
| Per-appearance icon backgrounds | `fill-specializations` is silently ignored by the icon renderer; macOS substitutes its own dark material and only the glass layers keep their colour. Not fought | `AppIcon.icon` |
| Cancelling a running generation | A Precision enhancement runs to completion once started; the reply-length budget bounds how long that can be. Wiring `Task` cancellation through the inference queue is the known refinement | `LlamaEngine` |
| Stopping the audio engine when idle | `AVAudioEngine` starts on the first sound and stays up so the start chime never lags. Costs ~0.8% CPU at rest; a debounce-then-stop is the obvious refinement | `SoundPlayer` |

**Signing note:** the Hardened Runtime carries
`com.apple.security.cs.disable-library-validation` so ad-hoc builds can load the embedded
`whisper.framework` (no Team ID → validation would reject it). With a real Developer ID,
sign app and framework with one identity and drop the exception — see
`Frameworks/PROVENANCE.md`.

---

## 9. Adding a speech engine

The whole architecture exists to make this short.

1. Create `Services/Speech/<Engine>/` with a `SpeechRecognitionEngine` and a
   `SpeechEngineFactory`.
2. Register it in `AppEnvironment.registerSpeechEngines()`.

That is all. The picker, the coordinator, the settings and the UI need no changes — they
only ever knew about protocols.

### Why the first load can be slow, and what we do about it

Parakeet runs through Core ML. The first time its conformer encoder is loaded, Core ML
compiles it for the Neural Engine and caches the result on disk. Measured on this machine
with the standalone harness in `scratchpad/pktest`:

| encoder placement | first load | later loads | recognition (3 s of audio) |
|---|---|---|---|
| Neural Engine (`.cpuAndNeuralEngine`, default) | **84.7 s** | 0.42 s | **0.09 s** |
| GPU (`.cpuAndGPU`) | 11.1 s | 3.32 s | 0.48 s |

The GPU route looks tempting because it makes the one-time cost eight times smaller. It was
rejected: in the steady state — which is every dictation after the first — the Neural Engine
loads eight times faster, recognises five times faster, and draws far less power, which
matters for an app that lives in the menu bar of a laptop. Trading permanent slowness for a
better first minute is the wrong trade.

So the 85 seconds are real and are kept. What changes is *when* they are spent, which is
`SpeechEngineWarmUp`: it builds the engine, calls `prepare()`, and shuts it down again at
once. Nothing stays resident; what survives is Core ML's on-disk cache, the expensive part.
It runs at three moments, in order of preference:

1. **When a download finishes** (`ModelManagementViewModel.apply`). The best moment there
   is: the user has already accepted that this model takes time to become usable, and is
   looking at the screen where it happens.
2. **When a model is selected**, for a model installed by an earlier version.
3. **At launch**, for whatever engine is selected.

Warm-up used to be entirely silent, which was its own bug: a minute and a half of invisible
work is indistinguishable from a hang, and a user who quits in the middle throws away the
compile they were waiting for. `SpeechWarmUpStatus` is the main-actor half of the pair, so
the model row can say "preparing" instead of showing a checkmark that promises instant
dictation it cannot yet deliver.

Whisper needs none of this — a GGML file loads in about a second — but the warm-up asks the
registry for whatever engine is selected rather than naming Parakeet, so a future engine
with a heavy first load is covered for free.

For comparison: Handy avoids the problem by not using Core ML at all — it runs Parakeet on
the CPU through `transcribe-rs`. That starts instantly and stays slower and hungrier forever.
A different trade, deliberately not ours.

---

## 10. Localization

The interface follows the Mac's system language. It ships in **English (base) and
Russian**; a system set to either shows that language, anything else falls back to English.

The mechanism is a **String Catalog** (`Resources/Localizable.xcstrings`), plus
`InfoPlist.xcstrings` for the microphone-permission dialog. `SwiftUI` `Text("…")` literals
localize themselves against it. The one thing to watch — and the source of every "why is
this still English?" — is the difference between `LocalizedStringKey` and `String`:

- `Text("Ready")`, `Label("Download", …)` take a `LocalizedStringKey` and localize.
- `Text(someString)`, and any custom view with a `let title: String`, render **verbatim**.

So text that reaches the UI as a `String` — enum `displayName`s, `LocalizedError`
descriptions, `Permission.rationale`, view-model titles — is localized *at the source*
with `String(localized:)`, and custom components that take titles (`MenuBarRow`,
`PrivacyClaim`) declare them as `LocalizedStringKey`, not `String`.

**Deliberately not localized:** the model catalog's content (model names like "Whisper
Small", and their one-line summaries). That is *data* from `model-catalog.json`, not app
chrome — names are proper nouns, and a distributor who hosts their own catalog localizes
its prose there. Localized numbers and sizes (`74,4 МБ`) come for free from
`ByteCountFormatter`.

Adding a language is now purely data: add its translations to the two `.xcstrings` files
and register the code in `knownRegions`. No code changes.

To re-extract keys after adding UI strings:

```bash
xcodebuild … build          # emits .stringsdata with the exact keys (incl. %@ formats)
xcrun xcstringstool sync Localizable.xcstrings --stringsdata <files> --skip-marking-strings-stale
```

---

## 11. Build

Requires Xcode 26+, macOS 15+.

```bash
xcodebuild -project LibreVoice.xcodeproj -scheme LibreVoice -destination 'platform=macOS' build
xcodebuild -project LibreVoice.xcodeproj -scheme LibreVoice -destination 'platform=macOS' test
```

Both Debug and Release build with **zero warnings**. The scheme is shared, so a fresh
clone can build and test without opening Xcode first.

---

## 12. Sound

Every sound is **synthesised from arithmetic**. No audio files ship and none are
downloaded: an app that promises to keep to itself should not need megabytes of assets to
say "listening", and a change of character becomes a few constants rather than a re-record.

`Core/Sound` holds the contract — `DictationSound` (named for *what happened*, never for
how it sounds) and `SoundPlaying`. `Services/SoundEngine` holds the synthesis primitives:
`Oscillator`, `EnvelopeGenerator`, `Filter`, `Mixer`, `SoundTheme`, `AudioSynthesizer`, and
`SoundPlayer` (an `actor` over `AVAudioEngine`, buffers rendered once and cached).

House rules, applied to all of them: nothing starts or stops instantly (a hard edge is a
click, and a click is the opposite of calm); noise is always filtered (unfiltered noise
reads as a fault); everything is quiet, because these accompany speech rather than being
events in their own right.

Three sounds, one per real moment: **start**, **stop** (recording closes, recognition
begins) and **completion**. There is deliberately no ambience under recognition — an
earlier build had a looping "thinking" texture and it was one sound too many; processing is
shown by the capsule, not heard.

The identity **does not vary by mode**. Earlier builds tuned pitch, length and air per
dictation mode — three subtly different sound sets for what a person experiences as one
app. `SoundTheme.theme(for:)` now returns a single `standard` for every mode.

### Why the opening chime is built like the completion chime

The start sound arrives *unbidden*, the instant you begin speaking, so it must be the least
sharp thing the app does. Two ingredients made an earlier version pierce: a filtered-noise
"breath" and a triangle overtone. Both are gone from `openingChime` — it is two consonant
sine partials under a long attack, the same construction as the completion chime, differing
only in direction and register so start and end stay distinguishable.

### Judged by numbers, not by ear

Sound is normally assessed by listening, which is exactly what makes it regress unnoticed.
Synthesis is deterministic, so the qualities that matter are asserted as numbers: nothing
begins or ends on a non-zero sample (the most common flaw in synthesised UI sound),
everything peaks below 0.45, the start motif rises and the stop motif falls, and every mode
renders identically.

---

## 13. App icon

The icon is an **Icon Composer document** — `LibreVoice/AppIcon.icon`, a directory holding
`icon.json` plus the layer PNGs — not an asset-catalog `AppIcon.appiconset`. That is what
buys real Liquid Glass: the system renders light / dark / tinted / clear appearances and
applies the specular material itself, instead of the app shipping a flat picture per size.
It is also smaller by two orders of magnitude — 36 KB of layers and JSON against 3.3 MB of
pre-rendered PNGs.

`actool` picks the document up automatically (the target uses
`PBXFileSystemSynchronizedRootGroup`) and still emplaces a conventional `AppIcon.icns`, so
macOS versions below 26 get a static icon and nothing regresses.

### Authoring it without the GUI

Icon Composer ships a command-line tool, which makes the document verifiable in CI rather
than only in an app:

```bash
ictool AppIcon.icon --export-image --output-file out.png \
  --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
```

`--platform` is `iOS|macOS|watchOS`; `--rendition` is
`Default|Dark|TintedLight|TintedDark|ClearLight|ClearDark`. It prints `{}` on success and a
descriptive error otherwise. Two things the format does not document: colours are strings
of the form `srgb:r,g,b,a` / `named:system-blue` (a missing `:` is rejected), and
`linear-gradient` takes a **two-element array** — the `{colors, orientation}` object form
is refused.

---

## 14. Idle cost

A menu bar utility is running whenever the Mac is, so its resting cost is a feature.

The one trap worth recording: **`MTKView` does not stop rendering when its window is
hidden.** The capsule's view kept its display link running at 120 fps around the clock,
drawing frames nobody could see — 6.7% CPU and an energy impact of 6.8, permanently. The
fix is that `MetalWaveView` takes an `isRendering` flag and sets `isPaused` in
`updateNSView`, so the renderer runs only while the capsule is on screen.

Measured after the fix, at rest: **0.0% CPU, energy impact 0.0, 40 MB**. Whichever way this
code is changed, that number is the one to re-check — a profile (`sample <pid>`) showing a
live `CVDisplayLink` thread means the trap has been re-entered.

---

## 15. Precision mode and the personal profile

The three modes are three genuinely different pipelines, and each initialises only what
it uses:

- **Fast**: recognition → trim → insert per segment. No rules, no profile, no model.
- **Smart**: recognition → `SmartTextCorrector` (punctuation, capitalisation,
  whitespace) → insert per segment. No model.
- **Precision**: recognition → rules + `TerminologyDictionary` → **batch** → personal
  profile context → local language model → single insertion. The only mode allowed to
  touch a language model.

### The seam

`DictationCoordinator` knows one protocol: ``TextEnhancing`` (`isReady`/`enhance`).
Before each session it captures an `EnhancementConfiguration` from settings; if the
enhancer reports ready, that session stops inserting per settled segment and batches the
transcript instead. After recognition shuts down — deliberately, so whisper's memory is
released before the model claims its own — the batch is enhanced and inserted **once**.
Any enhancement failure falls back to the text exactly as recognised: the promise "the
user's words survive" does not rest on a probabilistic component. The transcript is then
replaced with what was actually inserted (`Transcript.replaceCommitted`), so the preview
never shows text the user didn't receive.

When Precision has no ready model — none selected, none installed, strength at zero, or
no PROMPT.md — the session runs the classic per-segment pipeline, pinned by test.

### The provider seam

``LanguageModelProviding`` (`load`/`generate`/`unload`) is the runtime boundary. Llama,
Qwen and Gemma are *not* providers — they are interchangeable GGUF files consumed by one
runtime (llama.cpp), listed in `llm-catalog.json` and installed by a second
`FileSystemModelRepository` instance into `…/LibreVoice/LanguageModels/`. The repository,
checksums, atomic installs and the management UI are all the same machinery as speech
models (`ModelManagementViewModel` gained a `Purpose`, not a sibling). A different
runtime later is a new conformance and one line in `AppEnvironment`.

The runtime itself is `Packages/LlamaRuntime` — a vendored local Swift package wrapping
the official llama.cpp xcframework (b10092), with `LlamaCppProvider` in the app as a thin
adapter. The package is not packaging hygiene, it is load-bearing: **whisper.framework
and llama.framework each embed their own generation of ggml, and their C types disagree**
— imported into one Swift module they fail to compile ("`ggml_type` has different
definitions in different modules"). Separate modules whose public APIs never expose the C
types are what let both runtimes coexist.

Walling off llama alone turned out to be half a fix. The app module still imported
`whisper` directly while linking `LlamaRuntime`, and a clean Debug build then failed
**about half the time**, depending on the order the compiler happened to load modules in.
Intermittent is worse than broken: it reads as a flaky toolchain rather than a structural
mistake, and Release happening to succeed hid it. `Packages/WhisperRuntime` is the missing
half — same shape, same rule, no C types in its API. The app module now imports neither
runtime, so the collision is impossible rather than unlikely.

That refactor paid for itself immediately. `WhisperCppEngine.join(_:)` — the filter that
drops segments Whisper itself flags as probably-not-speech, the last thing standing between
room tone and an invented sentence in the user's document — used to take a raw C context
pointer, so testing it needed a 1.5 GB model and a microphone, which meant it was never
tested. It is a pure function over `[WhisperSegment]` now, with six cases covering it.

Inference runs on a dedicated `DispatchQueue`,
not an actor: llama.cpp calls block for seconds, and blocking a cooperative-pool thread
is forbidden — the serial queue gives actor-grade mutual exclusion without pinning the
pool. Generation is greedy on purpose: an editor wants the single most likely correction,
reproducibly; creative variance is a defect here. Each model's chat template comes from
its own GGUF metadata, which is what keeps the three families genuinely interchangeable.

### The personal prompt

One plain-text file: `~/Library/Application Support/LibreVoice/Profile/WritingProfile.txt`
(``WritingProfile``, edited in Settings › Writing Profile).

This replaced an earlier design of six imported Markdown documents — PROMPT, STYLE,
TERMINOLOGY, VOCABULARY, FORMATTING, EXAMPLES — that the app parsed and assembled at run
time. The scheme asked the user to manage a small filesystem and asked the app to
interpret it, and neither bought anything a single prompt does not: what reaches the model
is now exactly the text the user can see and edit, in their order, unparsed. Existing
users are not stranded — `FileSystemWritingProfileStore` folds any legacy documents into
one prompt on first load and leaves the old files alone.

Editing saves itself, debounced: every keystroke writing a file would be wasteful, an
explicit Save button loses work to a closed window. `TextEditor` supplies undo, redo,
copy, paste and find because the platform's versions are better than a hand-rolled one.

LibreVoice **never writes the prompt for the user**. The Generate Personal Prompt button
copies a template (`PromptGeneratorTemplate.md`) to the clipboard; the user pastes it into
ChatGPT, Claude, Gemini or Grok with their own writing and brings the answer back. The app
contacts nothing. A prompt is *required* for the model stage — without one, Precision
falls back to rules-only rather than substitute the app's voice for the user's.

`RuntimeContextBuilder` is a pure function assembling, per run: PROMPT.md → a
style-strength directive (the 0/25/50/75/100 slider maps to four instructions; 0 disables
the stage) → the profile sections that exist → a fixed block of non-negotiable rules
(never summarise, invent, remove, restructure, or replace terminology; output the
corrected text and nothing else). Profile files are re-read on every dictation, so edits
apply immediately with no cache.

### Stopping the model from holding a conversation

Small instruct models slip into assistant mode and *answer* dictated text instead of
correcting it — reliably so when the text happens to read like a question, which dictation
often does. Three layers address it, in ascending order of how much they actually help:

1. **Explicit rules.** The block states that this is not a conversation, that the next
   message is never addressed to the model, and that text which looks like a question is
   still only text. Necessary, and on its own not sufficient.
2. **Demonstration.** EXAMPLES.md is parsed into INPUT → OUTPUT pairs and replayed as
   real user/assistant chat turns (`RuntimeContext.examples`), not pasted into the system
   prompt. A model that has just seen the assistant reply with nothing but corrected text
   does the same; the same examples described in prose are routinely ignored. Unparseable
   examples fall back to prose. This is the layer that works.
3. **Refusal.** `LocalModelTextEnhancer.accepted` strips scaffolding (code fences, a
   "Here is the corrected text:" opener, wrapping quotes) and then measures **word
   retention** — the share of the original's words that survive, compared lowercased and
   without punctuation, since punctuation and case are what an edit is *supposed* to
   change. A correction retains nearly everything; a conversational answer retains almost
   nothing. Measured on real replies: genuine correction 1.00, one word dropped 0.88, a
   chat reply 0.17. The threshold sits at 0.60 — wide margin on both sides. Anything below
   it is discarded and the text is inserted exactly as dictated.

Retention deliberately is not stricter than 0.60: a *desired* terminology substitution
("либревойс" → "LibreVoice") also removes words, and a strict threshold would refuse the
very edits TERMINOLOGY.md exists to make.

### Missing spaces were never the model's fault

Engines return each segment trimmed — whisper.cpp calls
`trimmingCharacters(in: .whitespacesAndNewlines)` on every one — and `Transcript` used to
concatenate them with a plain `joined()`. Two segments therefore met as
`"Привет.Меня зовут"`: a space missing only at boundaries, which is why it looked random
and why it survived into Precision output whenever the model did not happen to fix it.
``SegmentJoining`` now decides each boundary — one space where running text would have
one, nothing before punctuation that binds to the word ahead of it — and the separator
travels with the value `Transcript.apply` returns, because Fast and Smart type each
settled segment into the user's document as it arrives.

### Lifecycle (mandatory)

`LocalModelTextEnhancer` owns when the model may exist: loaded on demand, kept warm
between dictations, unloaded by a timer after the configurable idle timeout
(30–120 s, default 45). Using the model cancels the timer; finishing re-arms it — in a
`defer`, so even a thrown generation restarts the idle clock. Replies are also gated:
stripped of code fences, refused when empty or when their length diverges from the
original beyond punctuation-and-grammar plausibility (0.5×–2×).

All of this is pinned numerically in `PrecisionEnhancementTests` against a fake provider
— readiness rules, single-load reuse, timed unload, failure fallback, and the acceptance
guards. The *real* runtime has its own smoke test (loads the dylib, initialises the
backend, refuses a bogus file without crashing); a live generation is verified out of
band with `swift run llama-smoke <model.gguf>` in `Packages/LlamaRuntime`, which loads a
downloaded GGUF and prints a before/after — kept out of the xcodebuild suite because it
needs a multi-hundred-megabyte model the test host has no business downloading.

### What the live run shows

Verified against Qwen 2.5 0.5B (the smallest catalog model) on Metal: load ~10 s, one
generation under a second. It capitalises and punctuates cleanly and preserves every
word — *except* proper nouns, where a 0.5B model is weak (it rendered "либревойс" as
"Левривернойс"). That is not a bug to fix in code; it is exactly what `TERMINOLOGY.md`
(protected words) and the recommended larger model (Qwen 1.5B) exist for, and why the
acceptance guard refuses replies whose length diverges from the original. The smallest
model does the safest edits; strength and model size trade caution for reach.
