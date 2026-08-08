//
//  ServiceContainerEnvironment.swift
//  LibreVoice
//

import SwiftUI

extension EnvironmentValues {
    /// The services available to the view tree.
    ///
    /// Injected once, at the root of each scene, so views build their view models from
    /// it rather than reaching for a singleton. The default is a container of fakes,
    /// which is what lets every `#Preview` in the project work with no setup — and, more
    /// importantly, means a preview can never touch the real microphone.
    @Entry var services: any ServiceContainer = PreviewServiceContainer()
}
