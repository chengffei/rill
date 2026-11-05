import SwiftUI

/// A Liquid Glass scroll thumb for the Dashboard. Appears while scrolling or
/// when the pointer is near the right edge, fades out after a moment, and
/// can be dragged. Its state is an @Observable object read only here, so a
/// scroll frame redraws the thumb, not the whole Dashboard.
struct GlassScroller: View {
    struct Metrics: Equatable {
        var offset: CGFloat = 0, content: CGFloat = 0, visible: CGFloat = 0, topInset: CGFloat = 0
        init() {}
        init(_ g: ScrollGeometry) {
            offset = g.contentOffset.y + g.contentInsets.top
            content = g.contentSize.height
            visible = g.containerSize.height
            topInset = g.contentInsets.top
        }
    }

    @Observable @MainActor
    final class State {
        var metrics = Metrics()
        var active = false
        var hovering = false
        var dragging = false
        private var hide: Task<Void, Never>?

        func update(_ m: Metrics) {
            let scrolled = abs(m.offset - metrics.offset) > 0.5
            metrics = m
            if scrolled { flash() }
        }

        func flash() {
            active = true
            hide?.cancel()
            hide = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled, let self, !self.hovering, !self.dragging else { return }
                self.active = false
            }
        }
    }

    let state: State
    @Binding var position: ScrollPosition
    @SwiftUI.State private var dragStart: CGFloat?

    private let margin: CGFloat = 6

    var body: some View {
        let m = state.metrics
        let scrollable = m.content - m.visible
        GeometryReader { _ in
            if scrollable > 1 {
                let top = m.topInset + margin
                let track = max(m.visible - m.topInset - margin * 2, 1)
                let thumb = max(40, track * m.visible / m.content)
                let progress = min(max(m.offset / scrollable, 0), 1)
                let wide = state.hovering || state.dragging
                Capsule()
                    .fill(Color.clear)
                    .frame(width: wide ? 10 : 7, height: thumb)
                    .glassEffect(.regular.tint(Color.black.opacity(wide ? 0.32 : 0.22)).interactive(), in: Capsule())
                    .offset(x: wide ? -4 : -5, y: top + (track - thumb) * progress)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .opacity(state.active || wide ? 1 : 0)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                state.dragging = true
                                let start = dragStart ?? m.offset
                                dragStart = start
                                let y = start + g.translation.height * scrollable / max(track - thumb, 1)
                                position.scrollTo(y: min(max(y, 0), scrollable))
                            }
                            .onEnded { _ in
                                dragStart = nil
                                state.dragging = false
                                state.flash()
                            }
                    )
                    .animation(.easeOut(duration: 0.2), value: state.active)
                    .animation(.easeOut(duration: 0.15), value: wide)
            }
        }
        .frame(width: 18)
        .contentShape(Rectangle())
        .onHover { inside in
            state.hovering = inside
            if inside { state.active = true } else { state.flash() }
        }
    }
}
