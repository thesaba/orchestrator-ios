import AppKit
import Carbon.HIToolbox

/// A key plus modifiers, stored as the hardware key code so it survives layout changes.
struct KeyCombo: Codable, Hashable {
    var keyCode: UInt32
    /// `NSEvent.ModifierFlags` raw value, device-independent part only.
    var modifiers: UInt

    static let optionSpace = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: NSEvent.ModifierFlags.option.rawValue)

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// Carbon modifier mask for `RegisterEventHotKey`.
    var carbonModifiers: UInt32 {
        var mask: UInt32 = 0
        let flags = modifierFlags
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        return mask
    }

    /// Needs ⌘, ⌥ or ⌃ — a plain letter would swallow typing in every app.
    var isValidGlobalShortcut: Bool {
        !modifierFlags.intersection([.command, .option, .control]).isEmpty
    }

    /// "⌥ Space", "⌃⌘ K".
    var displayString: String {
        let flags = modifierFlags
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        return symbols.isEmpty ? keyName : "\(symbols) \(keyName)"
    }

    var accessibilityName: String {
        let flags = modifierFlags
        var words: [String] = []
        if flags.contains(.control) { words.append("Control") }
        if flags.contains(.option) { words.append("Option") }
        if flags.contains(.shift) { words.append("Shift") }
        if flags.contains(.command) { words.append("Command") }
        words.append(keyName)
        return words.joined(separator: "-")
    }

    private var keyName: String {
        switch Int(keyCode) {
        case kVK_Space:         return "Space"
        case kVK_Return:        return "Return"
        case kVK_Tab:           return "Tab"
        case kVK_Escape:        return "Esc"
        case kVK_Delete:        return "Delete"
        case kVK_UpArrow:       return "↑"
        case kVK_DownArrow:     return "↓"
        case kVK_LeftArrow:     return "←"
        case kVK_RightArrow:    return "→"
        default:
            // Function key codes are not contiguous, so look them up rather than match a range.
            return Self.functionKeys[Int(keyCode)] ?? Self.character(for: keyCode) ?? "Key \(keyCode)"
        }
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
    ]

    /// The character the key produces on the current keyboard layout.
    private static func character(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
