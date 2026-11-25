import Carbon.HIToolbox
import Foundation

/// A system-wide shortcut through Carbon's `RegisterEventHotKey`: works inside the sandbox
/// and needs no Accessibility permission, unlike a global key monitor.
@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (@MainActor () -> Void)?
    private static let signature: OSType = 0x4F524348 // "ORCH"

    /// Carbon calls back on the main thread; this finds the instance from the C callback.
    private static weak var current: GlobalHotKey?

    /// Registers `combo`, replacing any earlier registration. Returns false when the system
    /// refuses it (for example, another app owns the same shortcut).
    @discardableResult
    func register(_ combo: KeyCombo, action: @escaping @MainActor () -> Void) -> Bool {
        unregister()
        self.action = action
        Self.current = self
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated {
                GlobalHotKey.current?.action?()
            }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}
