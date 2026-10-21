import Foundation

/// Who made a model, so the list can show a recognisable mark next to it.
///
/// Derived from the catalog id rather than stored in the catalog: the catalog's SHA-256
/// pins are regenerated from source, and a display-only field is not worth a schema change.
nonisolated enum ModelVendor: Sendable {
    case nvidia, openAI, meta, google, alibaba

    init?(modelID: String) {
        let id = modelID.lowercased()
        if id.hasPrefix("parakeet") { self = .nvidia }
        else if id.hasPrefix("whisper") { self = .openAI }
        else if id.hasPrefix("llama") { self = .meta }
        else if id.hasPrefix("gemma") { self = .google }
        else if id.hasPrefix("qwen") { self = .alibaba }
        else { return nil }
    }

    var assetName: String {
        switch self {
        case .nvidia: "VendorNVIDIA"
        case .openAI: "VendorOpenAI"
        case .meta: "VendorMeta"
        case .google: "VendorGoogle"
        case .alibaba: "VendorAlibaba"
        }
    }

    var displayName: String {
        switch self {
        case .nvidia: "NVIDIA"
        case .openAI: "OpenAI"
        case .meta: "Meta"
        case .google: "Google"
        case .alibaba: "Alibaba"
        }
    }
}
