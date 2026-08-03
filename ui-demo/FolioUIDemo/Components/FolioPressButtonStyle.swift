import SwiftUI

struct FolioPressButtonStyle: ButtonStyle {
    var scalesOnPress = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion && scalesOnPress ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(FolioMotion.press, value: configuration.isPressed)
    }
}
