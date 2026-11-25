import AppKit
import SwiftUI

/// "Record Shortcut": the next key press with ⌘, ⌥ or ⌃ becomes the shortcut. Escape cancels.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo
    /// Pauses the global shortcut while recording, so pressing it does not open the palette.
    var onRecordingChange: (Bool) -> Void = { _ in }

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        HStack(spacing: 8) {
            Button(isRecording ? "Press a shortcut…" : combo.displayString) {
                isRecording ? stop() : start()
            }
            .frame(minWidth: 140)
            .accessibilityLabel(isRecording ? "Recording shortcut" : "Shortcut \(combo.accessibilityName)")
            .accessibilityHint("Click, then press the new shortcut")

            if combo != .optionSpace, !isRecording {
                Button("Reset") { combo = .optionSpace }
                    .buttonStyle(.link)
            }
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        hint = nil
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                stop()
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .intersection([.command, .option, .control, .shift])
            let candidate = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: flags.rawValue)
            if candidate.isValidGlobalShortcut {
                combo = candidate
                stop()
            } else {
                hint = "Include ⌘, ⌥ or ⌃."
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording {
            isRecording = false
            onRecordingChange(false)
        }
    }
}
