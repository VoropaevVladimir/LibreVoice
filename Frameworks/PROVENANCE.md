# llama.xcframework

- Source: https://github.com/ggml-org/llama.cpp/releases/download/b10092/llama-b10092-xcframework.zip
- Version: b10092 (official release artifact)
- SHA-256 of the downloaded zip: aebdf1191c9e53f29ab04d9f4d73bcd91f8ac9a8de72abefa18c4e1f8bb59e88
- License: MIT (llama.cpp, ggml)
- Used by: Precision mode's local language model stage (`LlamaCppProvider`)
- Location: `Packages/LlamaRuntime/llama.xcframework` — inside the local Swift package,
  not this folder, because llama's bundled ggml must never share a Swift module with
  whisper's (see `Packages/LlamaRuntime/Package.swift`)
- **Trimmed**: only the `macos-arm64_x86_64` slice is committed (see below)

# whisper.xcframework

- Source: https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.1/whisper-v1.9.1-xcframework.zip
- Version: v1.9.1 (official release artifact)
- SHA-256 of the downloaded zip: 8c3ecbe73f48b0cb9318fc3058264f951ab336fd530e82c4ccdd2298d1311a4c
- License: MIT (whisper.cpp, ggml)
- Location: `Packages/WhisperRuntime/whisper.xcframework` — inside its own local Swift
  package, for the same reason llama has one. Both runtimes carry incompatible copies of
  ggml, so neither may be visible from the app's Swift module (see
  `Packages/WhisperRuntime/Package.swift`).
- **Trimmed**: only the `macos-arm64_x86_64` slice is committed (see below)

## What is committed, and how to verify it

Both xcframeworks ship seven platform slices — iOS, tvOS, visionOS, their simulators, and
macOS. LibreVoice is a macOS app: the other six never compile, never link, and never reach
the built product. Committing them cost **79 MB of the 98 MB** every clone had to download,
for files nothing in this repository can use. Only `macos-arm64_x86_64` is committed now,
and each `Info.plist` lists that one slice — a manifest advertising slices that are not on
disk is a manifest Xcode will trip over.

The checksums above are of the **official release zips**, and that is what verification
runs against — before extraction, and independently of what this repository keeps
afterwards. To re-verify from scratch:

```bash
curl -LO <the Source URL above>
shasum -a 256 <the downloaded zip>          # compare with the SHA-256 above
unzip <the downloaded zip>
```

The extracted `macos-arm64_x86_64` directory is the one committed here, byte for byte.
Nothing about trimming weakens that check: there is no published per-file manifest to
match a whole extracted folder against, so the zip's hash was always the anchor.

To update either framework: download the new release's zip, verify its checksum against
the release page, extract it, replace the committed folder with the new release's
`macos-arm64_x86_64` slice, prune the copied `Info.plist` to that slice, and update the
version and checksum here.

## Signing note

The app enables the Hardened Runtime with `disable-library-validation`, because ad-hoc
builds (no Team ID) cannot pass library validation against the embedded
whisper.framework. When release signing moves to a real Developer ID, sign the app AND
the framework with the same identity and remove
`RUNTIME_EXCEPTION_DISABLE_LIBRARY_VALIDATION` — validation then passes properly and the
exception is no longer needed.
