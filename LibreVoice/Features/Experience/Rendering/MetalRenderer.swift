//
//  MetalRenderer.swift
//  LibreVoice
//

import Foundation
import MetalKit
import simd
import SwiftUI

/// Drives the capsule's Metal view: composes the wave, particle, glow and morph
/// renderers into one uniforms struct and one draw call per frame.
///
/// SwiftUI hosts this and nothing else — the view layer's whole involvement is an
/// `MTKView` in a representable. Rendering never blocks recognition: everything here is
/// a read of the coordinator's published visual state, and the heavy lifting is one
/// fragment shader on the GPU.
@MainActor
final class MetalRenderer: NSObject, MTKViewDelegate {
    private let coordinator: ExperienceCoordinator
    private let commandQueue: (any MTLCommandQueue)?
    private let pipeline: (any MTLRenderPipelineState)?

    private var wave = WaveRenderer()
    private var startTime = CACurrentMediaTime()
    private var lastFrameTime = CACurrentMediaTime()

    init(device: (any MTLDevice)?, coordinator: ExperienceCoordinator) {
        self.coordinator = coordinator
        self.commandQueue = device?.makeCommandQueue()
        self.pipeline = device.flatMap { ShaderLoader.makeCapsulePipeline(device: $0) }
        super.init()
    }

    // MARK: - MTKViewDelegate

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        // MTKView draws on the main run loop in its default configuration, so hopping
        // back onto the main actor here is an assertion of fact, not a wish.
        MainActor.assumeIsolated {
            drawFrame(in: view)
        }
    }

    private func drawFrame(in view: MTKView) {
        guard let pipeline,
              let commandQueue,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        let now = CACurrentMediaTime()
        let dt = Float(min(0.1, now - lastFrameTime))
        lastFrameTime = now

        wave.advance(rawLevel: coordinator.rawAudioLevel, dt: dt)

        let (recipeA, recipeB, morph) = coordinator.morph.recipes(at: now)
        let age = now - coordinator.stateEnteredAt
        let state = coordinator.state
        let glowPulse = GlowRenderer.modulation(for: state, age: age)

        var uniforms = CapsuleUniforms()
        uniforms.time = Float(now - startTime)
        uniforms.level = wave.level
        uniforms.energy = wave.energy
        uniforms.recipeA = recipeA * SIMD4(1, 1, glowPulse, 1)
        uniforms.recipeB = recipeB * SIMD4(1, 1, glowPulse, 1)
        uniforms.morph = morph
        uniforms.stateAge = Float(age)
        uniforms.contraction = GlowRenderer.contraction(for: state, age: age)
        uniforms.errorAccent = GlowRenderer.errorAccent(for: state, age: age)
        uniforms.tint = coordinator.tint
        uniforms.size = SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CapsuleUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

/// The SwiftUI face of the Metal renderer: hosts an `MTKView`, nothing more.
struct MetalWaveView: NSViewRepresentable {
    let coordinator: ExperienceCoordinator

    /// Whether the capsule is currently on screen.
    ///
    /// Passed as a *value* rather than read off the coordinator inside `updateNSView`,
    /// because only a changed property makes SwiftUI re-run the update — reading the
    /// observable there would register no dependency and the view would never be told.
    let isRendering: Bool

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        guard let device = MTLCreateSystemDefaultDevice() else {
            // No Metal, no animation — the capsule still shows text over its material.
            return view
        }
        view.device = device
        view.framebufferOnly = true
        view.layer?.isOpaque = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.preferredFramesPerSecond = 120
        view.delegate = context.coordinator
        view.isPaused = !isRendering
        return view
    }

    /// Stops the render loop whenever the capsule is not showing.
    ///
    /// `MTKView` keeps its display link running even after its window is ordered off
    /// screen, so without this the app draws 120 frames a second, for ever, of a capsule
    /// nobody can see — measured at ~6-7% CPU while completely idle. Dictation is a
    /// utility that sits in the menu bar all day; that is the difference between costing
    /// the battery nothing and costing it a core.
    func updateNSView(_ view: MTKView, context: Context) {
        view.isPaused = !isRendering
    }

    func makeCoordinator() -> MetalRenderer {
        MetalRenderer(device: MTLCreateSystemDefaultDevice(), coordinator: coordinator)
    }
}
