import AppKit
import Carbon.HIToolbox
import Combine
import Foundation
import SwiftUI

final class GlobalHotKeyRegistrar {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var eventType = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
    )

    private(set) var keyCode: UInt32
    private(set) var modifiers: UInt32
    private(set) var display: String
    private let action: () -> Void

    init(
        keyCode: UInt32 = UInt32(kVK_ANSI_D),
        modifiers: UInt32 = UInt32(optionKey),
        display: String = "⌥D",
        action: @escaping () -> Void
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
        self.action = action
    }

    convenience init(shortcut: AppShortcut, action: @escaping () -> Void) {
        self.init(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, display: shortcut.display, action: action)
    }

    deinit {
        unregister()
    }

    @discardableResult
    func register() -> Bool {
        unregister()

        let hotKeyID = EventHotKeyID(signature: OSType(0x59495949), id: UInt32(1))
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            NSLog("YIYI failed to register global hot key: keyCode=\(keyCode), modifiers=\(modifiers), status=\(registerStatus)")
            hotKeyRef = nil
            return false
        }

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else {
                    return noErr
                }

                let registrar = Unmanaged<GlobalHotKeyRegistrar>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                registrar.action()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard handlerStatus == noErr else {
            NSLog("YIYI failed to install global hot key handler: status=\(handlerStatus)")
            unregister()
            return false
        }

        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}

@MainActor
final class GlobalHotKeyController {
    private let appState: AppState
    private let onTrigger: () -> Void
    private let onConflict: (AppShortcut) -> Void

    private var registrar: GlobalHotKeyRegistrar?
    private var settingsCancellable: AnyCancellable?

    init(
        appState: AppState,
        onTrigger: @escaping () -> Void,
        onConflict: @escaping (AppShortcut) -> Void
    ) {
        self.appState = appState
        self.onTrigger = onTrigger
        self.onConflict = onConflict
    }

    func start() {
        observeShortcutPreference()
        register(currentShortcut)
    }

    static func canRegister(_ shortcut: AppShortcut) -> Bool {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x59495954), id: UInt32(1))
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        return status == noErr
    }

    private var currentShortcut: AppShortcut {
        AppShortcut(
            keyCode: appState.settings.shortcutKeyCode,
            modifiers: appState.settings.shortcutModifiers,
            display: appState.settings.shortcutDisplay
        )
    }

    private func observeShortcutPreference() {
        settingsCancellable = appState.$settings
            .map { settings in
                HotKeyPreference(
                    shortcut: AppShortcut(
                        keyCode: settings.shortcutKeyCode,
                        modifiers: settings.shortcutModifiers,
                        display: settings.shortcutDisplay
                    )
                )
            }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] preference in
                self?.register(preference.shortcut)
            }
    }

    private func register(_ shortcut: AppShortcut) {
        if registrar?.matches(shortcut) == true {
            return
        }

        let previousRegistrar = registrar
        let nextRegistrar = GlobalHotKeyRegistrar(shortcut: shortcut) { [weak self] in
            DispatchQueue.main.async {
                self?.onTrigger()
            }
        }

        previousRegistrar?.unregister()
        guard nextRegistrar.register() else {
            restore(previousRegistrar, failedShortcut: shortcut)
            return
        }

        registrar = nextRegistrar
    }

    private func restore(_ previousRegistrar: GlobalHotKeyRegistrar?, failedShortcut: AppShortcut) {
        guard let previousRegistrar else {
            onConflict(failedShortcut)
            return
        }

        _ = previousRegistrar.register()
        registrar = previousRegistrar
        appState.updateShortcut(
            AppShortcut(
                keyCode: previousRegistrar.keyCode,
                modifiers: previousRegistrar.modifiers,
                display: previousRegistrar.display
            )
        )
    }
}

private struct HotKeyPreference: Equatable {
    let shortcut: AppShortcut

    static func == (lhs: HotKeyPreference, rhs: HotKeyPreference) -> Bool {
        lhs.shortcut.keyCode == rhs.shortcut.keyCode
            && lhs.shortcut.modifiers == rhs.shortcut.modifiers
    }
}

private extension GlobalHotKeyRegistrar {
    func matches(_ shortcut: AppShortcut) -> Bool {
        keyCode == shortcut.keyCode && modifiers == shortcut.modifiers
    }
}

struct GlobalHotKeySettingControl: View {
    @ObservedObject var appState: AppState

    @State private var isRecording = false
    @State private var conflictMessage: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                Text(isRecording ? "请按下快捷键" : appState.settings.shortcutDisplay)
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
        AppShortcut(
            keyCode: appState.settings.shortcutKeyCode,
            modifiers: appState.settings.shortcutModifiers,
            display: appState.settings.shortcutDisplay
        )
    }

    private func handleRecordedShortcut(_ shortcut: AppShortcut) -> Bool {
        guard shortcut != currentShortcut else {
            conflictMessage = nil
            return true
        }

        guard GlobalHotKeyController.canRegister(shortcut) else {
            conflictMessage = "\(shortcut.display) 已被占用，请换一个快捷键。"
            NSSound.beep()
            return false
        }

        conflictMessage = nil
        appState.updateShortcut(shortcut)
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
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 {
            parts.append("⌃")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("⌥")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("⇧")
        }
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("⌘")
        }
        parts.append(key)
        return parts.joined()
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        return modifiers
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
