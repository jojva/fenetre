import AppKit
import ApplicationServices

/// Reads the red notification badges (unread counts) shown on Dock icons.
///
/// There's no public API to read another app's badge directly, but the Dock
/// publishes every icon through its own Accessibility tree, and the badge text
/// is exposed on each dock item as the non-standard `AXStatusLabel` attribute.
/// We already hold the Accessibility grant for window enumeration, so this is
/// free — no extra entitlement, no per-app API (this is how AltTab does it).
///
/// The value is whatever the app put on its Dock icon: for Slack that's the
/// mentions/DM count (governed by Slack's own "show a badge" setting), so this
/// mirrors exactly what you'd see on the Dock — not a generic "any unread".
struct DockBadges {
    /// Custom AX attribute the Dock sets to the badge text (e.g. "5", "•").
    /// Not an Apple constant — it's a plain attribute string.
    private static let statusLabelAttribute = "AXStatusLabel"

    private let byPath: [String: String]
    private let byTitle: [String: String]

    /// The badge text for an app, or nil if its Dock icon isn't badged.
    /// Matches by bundle path first (robust), then by display name.
    func badge(for app: NSRunningApplication) -> String? {
        if let path = app.bundleURL?.standardizedFileURL.path, let badge = byPath[path] {
            return badge
        }
        if let name = app.localizedName, let badge = byTitle[name] {
            return badge
        }
        return nil
    }

    /// Snapshot the Dock's current badges. Cheap enough to call each time the
    /// overlay opens; returns empty maps if the Dock can't be read.
    static func read() -> DockBadges {
        var byPath: [String: String] = [:]
        var byTitle: [String: String] = [:]

        for item in dockItems() {
            guard let badge = string(item, statusLabelAttribute), !badge.isEmpty else { continue }
            if let path = url(item)?.standardizedFileURL.path {
                byPath[path] = badge
            }
            if let title = string(item, kAXTitleAttribute as String) {
                byTitle[title] = badge
            }
        }

        if !byTitle.isEmpty {
            Log.info("fenêtre: dock badges = \(byTitle)")
        }
        return DockBadges(byPath: byPath, byTitle: byTitle)
    }

    // MARK: - Dock AX traversal

    /// The dock-item elements. Structure is Dock app → list(s) → items, so we
    /// flatten one level of children below the app's top children.
    private static func dockItems() -> [AXUIElement] {
        guard let dock = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.dock" }) else {
            return []
        }
        let dockApp = AXUIElementCreateApplication(dock.processIdentifier)
        var items: [AXUIElement] = []
        for list in children(dockApp) {
            items.append(contentsOf: children(list))
        }
        return items
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else {
            return []
        }
        return children
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func url(_ element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? URL
    }
}
