// swift-tools-version: 6.0

// LlamaRuntime — the llama.cpp runtime, walled off in its own module.
//
// This package exists for one reason: whisper.framework and llama.framework each embed
// their own generation of ggml, and the two sets of C types disagree. Imported into the
// same Swift module they collide ("ggml_type has different definitions in different
// modules"). Kept in separate modules — the app imports whisper, this package imports
// llama — and with no llama types in this package's public API, the two never meet.
import PackageDescription

let package = Package(
    name: "LlamaRuntime",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LlamaRuntime", targets: ["LlamaRuntime"])
    ],
    targets: [
        .binaryTarget(name: "llama", path: "llama.xcframework"),
        .target(name: "LlamaRuntime", dependencies: ["llama"]),
        // A tiny harness for exercising the real runtime against a downloaded model from
        // the command line — `swift run llama-smoke <model.gguf>`. Not part of the app;
        // it exists so a live generation can be verified without the app's UI or a
        // xcodebuild test host.
        .executableTarget(name: "llama-smoke", dependencies: ["LlamaRuntime"]),
    ]
)
