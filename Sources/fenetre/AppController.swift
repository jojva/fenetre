import AppKit

/// Wires together permissions, the menu-bar item, window enumeration, the
/// overlay, and the hotkeys.
final class AppController: NSObject, NSApplicationDelegate {
    private let enumerator = WindowEnumerator()
    private let overlay = OverlayController()
    private let hotKeys = HotKeyManager()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        if Accessibility.ensureTrusted(prompt: true) {
            Log.info("fenêtre: ready. Hold ⌥ and tap Tab to switch windows (⇧⌥-Tab to go back).")
        } else {
            Log.info("""
            fenêtre: Accessibility permission needed.
            Grant it in System Settings → Privacy & Security → Accessibility,
            then quit (menu-bar icon) and relaunch.
            """)
        }

        hotKeys.onCycle = { [weak self] reverse in self?.cycle(reverse: reverse) }
        hotKeys.onCommit = { [weak self] in self?.commit() }
        hotKeys.register()
    }

    private func cycle(reverse: Bool) {
        Log.info("fenêtre: cycle reverse=\(reverse) visible=\(overlay.isVisible)")
        if overlay.isVisible {
            overlay.move(by: reverse ? -1 : 1)
            return
        }
        let windows = enumerator.windows()
        guard !windows.isEmpty else { return }
        // Start on the previous window so a quick ⌥-Tab + release flips back to
        // it; ⇧⌥-Tab opens on the last entry instead.
        let start = reverse ? windows.count - 1 : min(1, windows.count - 1)
        overlay.show(windows: windows, selected: start)
    }

    private func commit() {
        guard overlay.isVisible else { return }
        let window = overlay.selectedWindow()
        Log.info("fenêtre: commit selected=\(overlay.model.selected) -> \(window?.appName ?? "nil") / \(window?.title ?? "")")
        if let window {
            enumerator.commit(window)
        }
        overlay.hide()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.on.rectangle",
            accessibilityDescription: "fenêtre"
        )
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Quit fenêtre",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        item.menu = menu
        statusItem = item
    }
}
