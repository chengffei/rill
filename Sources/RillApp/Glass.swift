import SwiftUI

extension View {
    /// A Liquid Glass tile, the surface every card in Rill sits on.
    func glassCard(_ radius: CGFloat = 18) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: radius))
    }
}
