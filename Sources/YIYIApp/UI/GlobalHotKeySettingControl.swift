import AppKit
import Carbon.HIToolbox
import SwiftUI

struct GlobalHotKeySettingControl: View {
    @ObservedObject var viewModel: SettingsViewModel
    private let shortcutAvailability: ShortcutAvailabilityChecking = ShortcutAvailabilityService()

    @State private var isRecording = false
    @State private var conflictMessage: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                Text(isRecording ? "请按下快捷键" : viewModel.settings.shortcutDisplay)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(isRecording ? Color(nsColor: .controlAccentColor) : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(borderColor)
                    )

                Button(isRecording ? "捕捉中" : "设置") {
                    conflictMessage = nil
                    isRecording = true
                }
                .frame(width: 64)
                .disabled(isRecording)
            }

            if let conflictMessage {
                Text(conflictMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.trailing)
            }
        }
        .frame(width: 230)
        .background {
            ShortcutRecorder(
                isRecording: $isRecording,
                onRecord: handleRecordedShortcut
            )
        }
    }

    private var borderColor: Color {
        if conflictMessage != nil {
            return .red
        }

        if isRecording {
            return Color(nsColor: .controlAccentColor)
        }

        return Color(nsColor: .separatorColor).opacity(0.28)
    }

    private var currentShortcut: AppShortcut {
        viewModel.settings.globalHotKeyShortcut
    }

    private func handleRecordedShortcut(_ shortcut: AppShortcut) -> Bool {
        guard shortcut != currentShortcut else {
            conflictMessage = nil
            return true
        }

        guard shortcutAvailability.canRegister(shortcut) else {
            conflictMessage = "\(shortcut.display) 已被占用，请换一个快捷键。"
            NSSound.beep()
            return false
        }

        conflictMessage = nil
        viewModel.updateShortcut(shortcut)
        return true
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onRecord: (AppShortcut) -> Bool

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.setRecording(isRecording)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.setRecording(false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator {
        var parent: ShortcutRecorder
        private var monitor: Any?

        init(parent: ShortcutRecorder) {
            self.parent = parent
        }

        func setRecording(_ isRecording: Bool) {
            if isRecording, monitor == nil {
                // Captures one keyDown and returns nil so the shortcut does not leak into the UI.
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    self?.handle(event)
                    return nil
                }
            } else if !isRecording, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) {
            if event.keyCode == UInt16(kVK_Escape) {
                parent.isRecording = false
                return
            }

            guard let shortcut = ShortcutFormatter.shortcut(from: event) else {
                NSSound.beep()
                return
            }

            if parent.onRecord(shortcut) {
                parent.isRecording = false
            }
        }
    }
}

private enum ShortcutFormatter {
    private static let modifierDisplays: [ShortcutModifierDisplay] = [
        ShortcutModifierDisplay(flag: .control, carbonValue: UInt32(controlKey), symbol: "⌃"),
        ShortcutModifierDisplay(flag: .option, carbonValue: UInt32(optionKey), symbol: "⌥"),
        ShortcutModifierDisplay(flag: .shift, carbonValue: UInt32(shiftKey), symbol: "⇧"),
        ShortcutModifierDisplay(flag: .command, carbonValue: UInt32(cmdKey), symbol: "⌘")
    ]

    static func shortcut(from event: NSEvent) -> AppShortcut? {
        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0, let key = keyDisplay(for: event) else {
            return nil
        }

        return AppShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            display: display(modifiers: modifiers, key: key)
        )
    }

    private static func display(modifiers: UInt32, key: String) -> String {
        var parts = modifierDisplays.compactMap { modifier in
            modifiers & modifier.carbonValue != 0 ? modifier.symbol : nil
        }
        parts.append(key)
        return parts.joined()
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        modifierDisplays.reduce(UInt32(0)) { modifiers, modifier in
            flags.contains(modifier.flag) ? modifiers | modifier.carbonValue : modifiers
        }
    }

    private static func keyDisplay(for event: NSEvent) -> String? {
        if let specialKey = specialKeyDisplay(for: event.keyCode) {
            return specialKey
        }

        guard let character = event.charactersIgnoringModifiers?.first else {
            return nil
        }

        let key = String(character).uppercased()
        return key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : key
    }

    private static func specialKeyDisplay(for keyCode: UInt16) -> String? {
        switch Int(keyCode) {
        case kVK_Return:
            return "↩"
        case kVK_Tab:
            return "⇥"
        case kVK_Space:
            return "Space"
        case kVK_Delete:
            return "⌫"
        case kVK_ForwardDelete:
            return "⌦"
        case kVK_Home:
            return "Home"
        case kVK_End:
            return "End"
        case kVK_PageUp:
            return "Page Up"
        case kVK_PageDown:
            return "Page Down"
        case kVK_LeftArrow:
            return "←"
        case kVK_RightArrow:
            return "→"
        case kVK_DownArrow:
            return "↓"
        case kVK_UpArrow:
            return "↑"
        case kVK_F1:
            return "F1"
        case kVK_F2:
            return "F2"
        case kVK_F3:
            return "F3"
        case kVK_F4:
            return "F4"
        case kVK_F5:
            return "F5"
        case kVK_F6:
            return "F6"
        case kVK_F7:
            return "F7"
        case kVK_F8:
            return "F8"
        case kVK_F9:
            return "F9"
        case kVK_F10:
            return "F10"
        case kVK_F11:
            return "F11"
        case kVK_F12:
            return "F12"
        default:
            return nil
        }
    }
}

private struct ShortcutModifierDisplay {
    let flag: NSEvent.ModifierFlags
    let carbonValue: UInt32
    let symbol: String
}
