import SwiftUI

extension View {
    /// A Liquid Glass tile, the surface every card in Rill sits on.
    func glassCard(_ radius: CGFloat = 18) -> some View {
        // White tint keeps cards bright over dark wallpapers; plain .regular
        // stacked on the popover's own glass read as grey (2026-11-05).
        glassEffect(.regular.tint(Color.white.opacity(0.55)), in: .rect(cornerRadius: radius))
    }
}
