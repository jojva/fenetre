import AppKit
import SwiftUI
import Combine

/// Observable state the SwiftUI content view renders from.
final class OverlayModel: ObservableObject {
    @Published var windows: [WindowInfo] = []
    @Published var selected: Int = 0
}

/// A borderless, non-activating floating panel. Crucially it never becomes key
/// or main, so showing it does not steal focus from the app you're switching
/// away from — that app stays frontmost until we commit.
final class OverlayPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the panel + model and translates show/cycle/commit into UI updates.
final class OverlayController {
    let model = OverlayModel()
    private let panel: OverlayPanel

    private let rowHeight: CGFloat = 52
    private let verticalPadding: CGFloat = 14
    private let panelWidth: CGFloat = 560
    /// Grow to fit all windows, but never taller than this fraction of the
    /// screen — beyond that the list scrolls (selection auto-scrolls into view).
    private let maxHeightFraction: CGFloat = 0.85

    init() {
        // Frosted-glass background, clipped to rounded corners with a mask image.
        // (A layer cornerRadius + masksToBounds leaves a faint square fringe at
        // the corners because NSVisualEffectView's backdrop isn't clipped by the
        // layer mask; a mask image clips the material cleanly.)
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.maskImage = Self.roundedMaskImage(radius: 18)

        let host = NSHostingView(rootView: OverlayContentView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            host.topAnchor.constraint(equalTo: blur.topAnchor),
            host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])

        panel = OverlayPanel(contentView: blur)
    }

    var isVisible: Bool { panel.isVisible }

    func show(windows: [WindowInfo], selected: Int) {
        Log.info("fenêtre: show count=\(windows.count) selected=\(selected)")
        model.windows = windows
        model.selected = selected

        let screen = targetScreen()
        let frame = screen.visibleFrame
        let contentHeight = CGFloat(windows.count) * rowHeight + verticalPadding
        let height = min(contentHeight, frame.height * maxHeightFraction)
        let origin = NSPoint(
            x: frame.midX - panelWidth / 2,
            y: frame.midY - height / 2
        )
        panel.setFrame(NSRect(origin: origin, size: CGSize(width: panelWidth, height: height)), display: true)
        panel.orderFrontRegardless()
        panel.invalidateShadow()
    }

    func move(by delta: Int) {
        let count = model.windows.count
        guard count > 0 else { return }
        model.selected = ((model.selected + delta) % count + count) % count
        Log.info("fenêtre: move by \(delta) -> selected=\(model.selected)")
    }

    func selectedWindow() -> WindowInfo? {
        guard model.windows.indices.contains(model.selected) else { return nil }
        return model.windows[model.selected]
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func targetScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    /// A 9-slice rounded-rect mask used to clip the visual-effect material to
    /// rounded corners. The cap insets keep the corners crisp at any panel size.
    private static func roundedMaskImage(radius: CGFloat) -> NSImage {
        let length = radius * 2 + 1
        let image = NSImage(size: NSSize(width: length, height: length), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
