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

    private let rowHeight: CGFloat = 56
    private let verticalPadding: CGFloat = 16
    private let panelWidth: CGFloat = 560
    private let maxVisibleRows = 8

    init() {
        // Frosted-glass background with rounded corners; SwiftUI list on top.
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 18
        blur.layer?.masksToBounds = true

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

        let visibleRows = min(windows.count, maxVisibleRows)
        let height = CGFloat(visibleRows) * rowHeight + verticalPadding
        let screen = targetScreen()
        let frame = screen.visibleFrame
        let origin = NSPoint(
            x: frame.midX - panelWidth / 2,
            y: frame.midY - height / 2
        )
        panel.setFrame(NSRect(origin: origin, size: CGSize(width: panelWidth, height: height)), display: true)
        panel.orderFrontRegardless()
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
}
