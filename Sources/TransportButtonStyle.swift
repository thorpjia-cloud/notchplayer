import SwiftUI

struct TransportButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = isEnabled && configuration.isPressed

        configuration.label
            .scaleEffect(pressed && !reduceMotion ? 0.88 : 1)
            .opacity(isEnabled ? (pressed ? 0.58 : 1) : 0.4)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(pressed ? 0.10 : 0))
            }
            // Keep the full hit area steady while only the symbol compresses.
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .easeOut(duration: pressed ? 0.06 : 0.16), value: pressed)
    }
}
