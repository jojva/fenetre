import AppKit
import Carbon.HIToolbox

/// Registers the global ⌥-Tab / ⇧⌥-Tab hotkeys (Carbon) and watches for the
/// ⌥ key being released (AppKit global monitor) to commit the selection.
///
/// Interaction model: hold ⌥, tap Tab to cycle forward (⇧⌥-Tab to go back),
/// release ⌥ to commit.
final class HotKeyManager {
    /// Called on each Tab press while ⌥ is held. `reverse` is true for ⇧⌥-Tab.
    var onCycle: ((_ reverse: Bool) -> Void)?
    /// Called when ⌥ is released.
    var onCommit: (() -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var flagsMonitor: Any?

    private static let signature = OSType(0x464E5452) // 'FNTR'
    private static let forwardID: UInt32 = 1
    private static let reverseID: UInt32 = 2

    func register() {
        installCarbonHandler()
        registerHotKey(id: Self.forwardID, keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey))
        registerHotKey(id: Self.reverseID, keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey | shiftKey))

        // ⌥ release → commit. Global monitor only fires while another app is
        // focused, which is always our case (we never activate).
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if !event.modifierFlags.contains(.option) {
                self?.onCommit?()
            }
        }
    }

    // Called by the C handler below (we're on the main thread during dispatch).
    fileprivate func handleHotKey(id: UInt32) {
        onCycle?(id == Self.reverseID)
    }

    private func installCarbonHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func registerHotKey(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        hotKeyRefs.append(ref)
    }
}

/// C-compatible Carbon callback. Recovers the manager from `userData` and
/// forwards the fired hotkey id.
private func hotKeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handleHotKey(id: hotKeyID.id)
    return noErr
}
