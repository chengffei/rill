import SwiftUI

extension View {
    /// A Liquid Glass tile, the surface every card in Rill sits on.
    func glassCard(_ radius: CGFloat = 18) -> some View {
        modifier(GlassCard(radius: radius))
    }
}

private struct GlassCard: ViewModifier {
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        // In light mode a white tint keeps cards bright over dark wallpapers;
        // plain .regular stacked on the popover's own glass read as grey
        // (2026-11-05). In dark mode plain glass is the right surface.
        let glass: Glass = scheme == .dark ? .regular : .regular.tint(Color.white.opacity(0.55))
        content.glassEffect(glass, in: .rect(cornerRadius: radius))
    }
}
