import ApplicationServices

/// Thin wrapper around the Accessibility (AX) trust check. fenêtre needs this
/// permission to read other apps' window lists and to observe modifier-key
/// releases globally.
enum Accessibility {
    /// Whether this process is currently trusted for Accessibility.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Check trust, optionally showing the system prompt that deep-links into
    /// System Settings → Privacy & Security → Accessibility.
    @discardableResult
    static func ensureTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
