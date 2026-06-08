import AppKit
import ApplicationServices

/// A single switchable window: one row in the overlay.
struct WindowInfo: Identifiable {
    let id = UUID()
    let pid: pid_t
    let app: NSRunningApplication
    let appName: String
    let icon: NSImage?
    let title: String
    let axWindow: AXUIElement
}

/// Enumerates windows across all regular apps via the Accessibility API, and
/// keeps a lightweight most-recently-used ordering at the app level so the
/// overlay's second entry is usually your previous window (classic alt-tab).
final class WindowEnumerator {
    /// App pids, most-recently-activated first.
    private var appMRU: [pid_t] = []

    init() {
        // Seed MRU with the currently-frontmost app, then track activations.
        if let front = NSWorkspace.shared.frontmostApplication {
            appMRU = [front.processIdentifier]
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        let pid = app.processIdentifier
        appMRU.removeAll { $0 == pid }
        appMRU.insert(pid, at: 0)
    }

    /// Snapshot of all standard windows, ordered by app MRU.
    func windows() -> [WindowInfo] {
        let regularApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }

        let ordered = regularApps.sorted { a, b in
            let ia = appMRU.firstIndex(of: a.processIdentifier) ?? Int.max
            let ib = appMRU.firstIndex(of: b.processIdentifier) ?? Int.max
            return ia < ib
        }

        var result: [WindowInfo] = []
        for app in ordered {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
                  let axWindows = value as? [AXUIElement] else {
                continue
            }
            for window in axWindows where isStandardWindow(window) {
                let title = stringAttribute(window, kAXTitleAttribute) ?? ""
                result.append(
                    WindowInfo(
                        pid: app.processIdentifier,
                        app: app,
                        appName: app.localizedName ?? "Unknown",
                        icon: app.icon,
                        title: title,
                        axWindow: window
                    )
                )
            }
        }
        return result
    }

    /// Bring a window to the front: un-minimize, raise it, and activate its app.
    func commit(_ window: WindowInfo) {
        AXUIElementSetAttributeValue(window.axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementSetAttributeValue(window.axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window.axWindow, kAXRaiseAction as CFString)
        window.app.activate()
    }

    // MARK: - AX helpers

    /// A "standard" window is the kind you'd alt-tab to (excludes palettes,
    /// sheets, popovers, etc.).
    private func isStandardWindow(_ window: AXUIElement) -> Bool {
        stringAttribute(window, kAXSubroleAttribute) == (kAXStandardWindowSubrole as String)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
