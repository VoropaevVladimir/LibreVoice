# LibreVoice

**Your voice. Your Mac. Your data.**

Offline voice dictation for macOS. Free, open source, and built so that "your audio never
leaves this Mac" is a property of the code rather than a promise in a privacy policy.

> **Status: working.** Dictation runs end to end on device — hold ⌥Space, speak, release,
> and the text is typed at your cursor in whatever app you are in. Two recognition engines
> ship (NVIDIA Parakeet on the Neural Engine, and whisper.cpp with Metal), and an optional
> Precision mode cleans the text up with a local language model that follows a prompt you
> write yourself. Every model is downloaded and checksum-verified from **Settings ›
> Models**. See
> [Documentation/Architecture.md](Documentation/Architecture.md#8-what-is-real-and-what-is-not)
> for what is and is not implemented.

---

## Using it

Hold **⌥Space** anywhere, speak, and release. A small capsule slides down from under the
menu bar while you talk, showing a live waveform; releasing the key transcribes the audio
and pastes the result at your cursor. LibreVoice lives in the menu bar — closing its
window leaves it running, and **Quit** in the menu bar item is how you stop it.

## Principles

- **Offline first.** Your voice is transcribed on-device and never uploaded. The network is
  used for one thing only — downloading the speech models you choose — and that download
  carries no audio, no transcript, and nothing that identifies you.
- **Privacy first.** No analytics, no telemetry, no accounts, no server.
- **Asks for as little as possible.** Two permissions, one of them optional.
  Input Monitoring is never requested.
- **Verifiable.** The Activity screen shows every log record the app has kept, with
  buttons to copy or erase them. The source is open, so none of this has to be taken on
  trust.

## Requirements

- macOS 15 or later
- Xcode 26 or later (to build)

## Building

```bash
git clone <repository>
cd LibreVoice
open LibreVoice.xcodeproj
```

Or from the command line:

```bash
xcodebuild -project LibreVoice.xcodeproj -scheme LibreVoice -destination 'platform=macOS' build
xcodebuild -project LibreVoice.xcodeproj -scheme LibreVoice -destination 'platform=macOS' test
```

Both configurations build with zero warnings. **174 tests**, none of which need a
microphone — the audio, engine and insertion layers are all driven through fakes.

## Project structure

```
LibreVoice/
├── App/            Composition roots and scenes — the only place naming concrete types
│   └── Previews/       The fake container used by every #Preview
├── Core/           Contracts, models, framework-free domain logic
│   ├── Audio/          Capture contracts and audio value types
│   ├── Speech/         The engine plug-in system
│   ├── Hotkeys/        Shortcut contracts
│   ├── TextInsertion/  Delivering text into other apps
│   ├── Permissions/    Authorization contracts
│   ├── Logging/        Logger protocol and pure implementations
│   ├── Settings/       Typed preferences
│   ├── Dictation/      The session state machine
│   ├── Models/         Shared domain types
│   ├── Profile/        The personal prompt and the context built from it
│   └── DependencyInjection/
├── Services/       Adapters to system frameworks (AVFoundation, os.log, Carbon, AX)
│   ├── Speech/         Parakeet and whisper.cpp engines
│   ├── Enhancement/    Precision's language-model stage
│   └── ModelManagement/  Catalog, checksums, atomic installs
├── Features/       UI — one folder per screen, View + ViewModel
├── Resources/      Assets and the pinned model catalogs
├── Packages/       Vendored local Swift packages (see below)
├── Documentation/
└── Tests/
```

`Packages/` holds `LlamaRuntime` and `WhisperRuntime` — thin wrappers around the llama.cpp
and whisper.cpp xcframeworks. They are separate modules for a load-bearing reason: each
xcframework embeds its own generation of ggml, and their C types disagree, so any Swift
module that can see both fails to compile. Neither package exposes a C type, and the app
imports neither runtime directly.

Dependency direction: `App → Features → Core ← Services`. `Core` imports Foundation and
nothing else, which is why the whole pipeline is testable with no hardware.

## Permissions

| Permission | Required | Why |
|---|---|---|
| Microphone | Yes | There is nothing to transcribe otherwise |
| Accessibility | No | Lets LibreVoice type into other apps. Without it, text stays here |

LibreVoice is **not sandboxed**, because the App Sandbox blocks the Accessibility APIs
that let it type into the app you are working in. That rules out the Mac App Store;
distribution is Developer ID + notarization. The reasoning is written up in
[Architecture.md](Documentation/Architecture.md#5-app-sandbox-is-off).

## Speech engines

LibreVoice depends on no engine. The roster is assembled at launch and everything else in
the app sees only protocols.

| Engine | Processing | Status |
|---|---|---|
| Parakeet TDT v3 (Core ML) | Neural Engine | **Shipping** — 25 languages, ~0.1 s per utterance |
| Whisper (whisper.cpp) | Metal | **Shipping** — the compatibility choice, widest model range |
| Moonshine | On device | Declared, not implemented |

There is no engine picker. Both engines appear as ordinary entries in one model list, and
choosing a model selects the engine that runs it — which engine transcribed your words is
not a decision anyone should have to make.

**Parakeet's first load takes about 85 seconds**, once. Core ML compiles the encoder for
the Neural Engine and caches it to disk; every load after that is half a second and
recognition is under a tenth. LibreVoice pays that cost in the background right after the
download finishes, and says so on screen rather than leaving you watching a spinner.

On-device only — LibreVoice does not transcribe over the network, so there is no cloud
engine, and it deliberately does not use Apple's Speech framework or macOS Dictation
either: those are Apple's pipeline, not ours. Adding an engine means creating a
`SpeechEngineFactory` and registering it in `AppEnvironment`. Nothing else changes — see
[Architecture.md](Documentation/Architecture.md#9-adding-a-speech-engine).

## Precision mode

Three modes share one pipeline. **Fast** types as you speak. **Smart** applies rules and
terminology. **Precision** additionally hands the finished text to a local language model
(Llama, Qwen or Gemma, your choice, running through llama.cpp) with a **personal prompt**
you write in **Settings › Precision** — a plain-text description of how you write.

The model corrects; it never converses. A dictated sentence that looks like a question is
still text to be fixed, not a question to answer, and three separate layers enforce that —
including a word-retention check that rejects any reply which discarded too much of what
you actually said.

Generating that prompt is a copy-paste workflow, not an integration: the button copies a
template for you to paste into whichever external AI you like. **LibreVoice never talks to
a cloud AI.**

## Downloading models

You don't hunt for model files. **Settings › Models** lists every speech model — Parakeet
and Whisper alike — by name and size; one click downloads and installs it. Precision's
language models work the same way, from **Settings › Precision**.

Every download runs over HTTPS, refuses insecure redirects, is capped at the size the
catalog declares, and is verified against a SHA-256 fingerprint pinned in that catalog
before it is used — so a tampered, oversized or corrupted file is rejected rather than
loaded. See
[Architecture.md §6a](Documentation/Architecture.md#6a-downloading-models).

## Contributing

Read [Documentation/Architecture.md](Documentation/Architecture.md) first — particularly
the layering rule and the note on `nonisolated`, which is load-bearing in this codebase
rather than decoration.

House rules: no force unwraps, protocols over concrete types, one responsibility per file,
document public types, and never log what the user said.

Comments explain *why*, not *what*. A comment restating the code earns nothing; a comment
recording the measurement, the failure, or the alternative that was rejected is the only
copy of that reasoning anyone will ever have.

## Licence

MIT.
