// swift-tools-version: 6.0

// WhisperRuntime — the whisper.cpp runtime, walled off in its own module.
//
// The twin of LlamaRuntime, and it exists for the same reason. whisper.framework and
// llama.framework each embed their own generation of ggml, and the two sets of C types
// disagree: `enum ggml_type` has members in one that the other has never heard of. Any
// Swift module that can load both fails to compile.
//
// Walling off llama alone was not enough. The app module still imported `whisper`
// directly while linking LlamaRuntime, so a clean Debug build could — depending on the
// order the compiler happened to load modules in — pull both into one compilation and
// fail. It did so about half the time, which is worse than failing always: it looks like
// a flaky toolchain rather than a structural problem.
//
// With both runtimes behind Swift packages that expose no C types, the app module imports
// neither, and the collision is impossible rather than unlikely.
import PackageDescription

let package = Package(
    name: "WhisperRuntime",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WhisperRuntime", targets: ["WhisperRuntime"])
    ],
    targets: [
        .binaryTarget(name: "whisper", path: "whisper.xcframework"),
        .target(name: "WhisperRuntime", dependencies: ["whisper"]),
    ]
)
