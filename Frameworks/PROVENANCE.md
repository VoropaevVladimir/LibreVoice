# llama.xcframework

- Source: https://github.com/ggml-org/llama.cpp/releases/download/b10092/llama-b10092-xcframework.zip
- Version: b10092 (official release artifact)
- SHA-256 of the downloaded zip: aebdf1191c9e53f29ab04d9f4d73bcd91f8ac9a8de72abefa18c4e1f8bb59e88
- License: MIT (llama.cpp, ggml)
- Used by: Precision mode's local language model stage (`LlamaCppProvider`)
- Location: `Packages/LlamaRuntime/llama.xcframework` — inside the local Swift package,
  not this folder, because llama's bundled ggml must never share a Swift module with
  whisper's (see `Packages/LlamaRuntime/Package.swift`)

To update: download the new release's xcframework zip, verify its checksum against the
release page, replace this folder, and update this file.

# whisper.xcframework

- Source: https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.1/whisper-v1.9.1-xcframework.zip
- Version: v1.9.1 (official release artifact)
- SHA-256 of the downloaded zip: 8c3ecbe73f48b0cb9318fc3058264f951ab336fd530e82c4ccdd2298d1311a4c
- License: MIT (whisper.cpp, ggml)
- Location: `Packages/WhisperRuntime/whisper.xcframework` — inside its own local Swift
  package, for the same reason llama has one. Both runtimes carry incompatible copies of
  ggml, so neither may be visible from the app's Swift module (see
  `Packages/WhisperRuntime/Package.swift`).

To update: download the new release's xcframework zip, verify its checksum against the
release page, replace that folder, and update this file.

## Signing note

The app enables the Hardened Runtime with `disable-library-validation`, because ad-hoc
builds (no Team ID) cannot pass library validation against the embedded
whisper.framework. When release signing moves to a real Developer ID, sign the app AND
the framework with the same identity and remove
`RUNTIME_EXCEPTION_DISABLE_LIBRARY_VALIDATION` — validation then passes properly and the
exception is no longer needed.
