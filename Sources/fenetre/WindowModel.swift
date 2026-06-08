import AppKit
import ApplicationServices
import CoreGraphics

/// Private AX→CoreGraphics bridge: maps an Accessibility window element to its
/// on-screen CGWindowID, letting us correlate AX windows with the global
/// stacking order. Undocumented but long-stable (used by AltTab and most
/// window managers).
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// A single switchable window: one row in the overlay.
struct WindowInfo: Identifiable {
    let id = UUID()
    let pid: pid_t
    let app: NSRunningApplication
    let appName: String
    let icon: NSImage?
    let title: String
    let axWindow: AXUIElement
    let windowID: CGWindowID
}

/// Enumerates windows across all regular apps via the Accessibility API,
/// ordered by on-screen z-order (front-to-back).
///
/// Z-order *is* per-window recency: focusing a window raises it, so the
/// frontmost window is the one you're in and the next is the one you used
/// before it — and this holds no matter how you switched (fenêtre, a click, or
/// ⌘-Tab). No state to track.
final class WindowEnumerator {

    /// Snapshot of all standard windows, most-recently-used first.
    func windows() -> [WindowInfo] {
        let zOrder = onScreenZOrder()
        let regularApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }

        var result: [WindowInfo] = []
        for app in regularApps {
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
                        axWindow: window,
                        windowID: cgWindowID(of: window) ?? 0
                    )
                )
            }
        }

        // Front-to-back: on-screen windows by stacking order; anything not on
        // screen (e.g. minimized) sorts to the end.
        result.sort { a, b in
            (zOrder[a.windowID] ?? Int.max) < (zOrder[b.windowID] ?? Int.max)
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

    // MARK: - Ordering

    /// Map of CGWindowID → index in the global front-to-back on-screen order.
    private func onScreenZOrder() -> [CGWindowID: Int] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var order: [CGWindowID: Int] = [:]
        var index = 0
        for info in infos {
            guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            if order[number] == nil {
                order[number] = index
                index += 1
            }
        }
        return order
    }

    // MARK: - AX helpers

    private func cgWindowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success ? id : nil
    }

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
