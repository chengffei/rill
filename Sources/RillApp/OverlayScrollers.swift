import AppKit
import ObjectiveC

/// Thin scrollers that appear only while scrolling, whatever the system's
/// "Show scroll bars" setting. With "Always" (this Mac's setting) every
/// SwiftUI Form and Table gets the wide legacy scroller with a track, which
/// looks heavy in a small utility window. New scroll views take their style
/// from `NSScroller.preferredScrollerStyle`, so answering `.overlay` for this
/// process covers the main window, Settings and the panel at once; scroll
/// views that already exist are updated too.
enum OverlayScrollers {
    static func install() {
        let cls: AnyClass = object_getClass(NSScroller.self)!   // metaclass: it's a class property
        guard let original = class_getInstanceMethod(cls, #selector(getter: NSScroller.preferredScrollerStyle)),
              let replacement = class_getInstanceMethod(cls, #selector(NSScroller.rill_preferredScrollerStyle))
        else { return }
        method_exchangeImplementations(original, replacement)
        // Turning the system setting back and forth reapplies its style to
        // live scroll views; put ours back afterwards.
        NotificationCenter.default.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                                               object: nil, queue: .main) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for window in NSApp.windows { apply(in: window.contentView) }
                }
            }
        }
    }

    @MainActor
    private static func apply(in view: NSView?) {
        guard let view else { return }
        if let scroll = view as? NSScrollView, scroll.scrollerStyle != .overlay { scroll.scrollerStyle = .overlay }
        view.subviews.forEach { apply(in: $0) }
    }
}

extension NSScroller {
    @objc class func rill_preferredScrollerStyle() -> NSScroller.Style { .overlay }
}
