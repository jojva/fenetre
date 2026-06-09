import AppKit
import ApplicationServices
import CoreGraphics
import Darwin

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
    /// Dock notification badge for the app (e.g. Slack's unread count), or nil.
    /// App-level, so all of an app's windows share it.
    let badge: String?
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
        let badges = DockBadges.read()
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
                let rawTitle = stringAttribute(window, kAXTitleAttribute) ?? ""
                let label = labels(for: app, rawTitle: rawTitle)
                result.append(
                    WindowInfo(
                        pid: app.processIdentifier,
                        app: app,
                        appName: label.app,
                        icon: app.icon,
                        title: label.window,
                        badge: badges.badge(for: app),
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

    // MARK: - App display name (Firefox per-profile labelling)

    /// App label and window name, disambiguated where a bare app name hides
    /// useful context:
    /// - Firefox runs one process per profile (`-P algolia`) → append profile.
    /// - VS Code is one process with many windows → move the workspace/folder
    ///   from the window title up into the app label (so it isn't shown twice).
    private func labels(for app: NSRunningApplication, rawTitle: String) -> (app: String, window: String) {
        let base = app.localizedName ?? "Unknown"
        let bundleID = app.bundleIdentifier ?? ""

        if bundleID.hasPrefix("org.mozilla."), let profile = launchProfile(pid: app.processIdentifier) {
            return ("\(base) \(profile)", rawTitle)
        }

        if bundleID.hasPrefix("com.microsoft.VSCode"), let parsed = parseVSCodeTitle(rawTitle) {
            return ("\(base) — \(parsed.folder)", parsed.window)
        }

        return (base, rawTitle)
    }

    /// Split a VS Code window title ("Accessibility.swift - fenetre") into its
    /// trailing workspace/folder and the remaining window name. Handles " - "
    /// and " — " separators and a trailing app-name segment. Returns nil if no
    /// folder segment is present. When the folder is the only segment (no file
    /// open), it's kept as the window name rather than leaving it blank.
    private func parseVSCodeTitle(_ title: String) -> (folder: String, window: String)? {
        let normalized = title.replacingOccurrences(of: " — ", with: " - ")
        var segments = normalized.components(separatedBy: " - ").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if let last = segments.last, last == "Visual Studio Code" || last == "Code" {
            segments.removeLast()
        }
        guard let folder = segments.last, !folder.isEmpty else { return nil }
        segments.removeLast()
        let window = segments.joined(separator: " - ")
        return (folder, window.isEmpty ? folder : window)
    }

    /// Extract the Firefox profile from a process's launch arguments
    /// (`-P <name>`, or `--profile <path>` → the dir's readable suffix).
    private func launchProfile(pid: pid_t) -> String? {
        guard let args = processArguments(pid: pid) else { return nil }
        var i = 0
        while i < args.count {
            switch args[i] {
            case "-P", "-p":
                if i + 1 < args.count { return args[i + 1] }
            case "--profile", "-profile":
                if i + 1 < args.count {
                    let name = (args[i + 1] as NSString).lastPathComponent
                    if let dot = name.firstIndex(of: ".") {
                        return String(name[name.index(after: dot)...])
                    }
                    return name
                }
            default:
                break
            }
            i += 1
        }
        return nil
    }

    /// Read a process's launch arguments via `KERN_PROCARGS2` (allowed for
    /// same-user processes). Layout: [argc: Int32][exec path][padding][argv…].
    private func processArguments(pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &data, &size, nil, 0) == 0 else { return nil }
        guard size >= 4 else { return nil }

        let argc = data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var index = 4
        while index < size && data[index] != 0 { index += 1 }   // skip exec path
        while index < size && data[index] == 0 { index += 1 }    // skip padding

        var args: [String] = []
        var current = [UInt8]()
        while index < size && args.count < Int(argc) {
            let byte = data[index]
            if byte == 0 {
                args.append(String(decoding: current, as: UTF8.self))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(byte)
            }
            index += 1
        }
        return args
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
