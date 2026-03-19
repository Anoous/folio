import SwiftUI

/// Button style that scales down on press (0.85) and settles back on release.
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .animation(configuration.isPressed ? Motion.quick : Motion.settle, value: configuration.isPressed)
    }
}
