//
//  ShaderLoader.swift
//  LibreVoice
//

import Metal
import MetalKit

/// Builds the capsule's render pipeline from the app's compiled shader library.
///
/// Failure here is survivable by design: if Metal is unavailable or the library is
/// missing, the caller renders nothing and the capsule falls back to its material
/// background — dictation itself never depends on graphics.
nonisolated enum ShaderLoader {
    /// Creates the pipeline state for the capsule shader pair.
    static func makeCapsulePipeline(device: any MTLDevice) -> (any MTLRenderPipelineState)? {
        guard let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "capsule_vertex"),
              let fragment = library.makeFunction(name: "capsule_fragment") else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Premultiplied-alpha blending over the transparent capsule background.
        let attachment = descriptor.colorAttachments[0]
        attachment?.isBlendingEnabled = true
        attachment?.sourceRGBBlendFactor = .one
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
}
