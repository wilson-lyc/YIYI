import AppKit
import Carbon.HIToolbox
import Combine
import Foundation
import SwiftUI

final class GlobalHotKeyRegistrar {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

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

        guard registerHotKey() else {
            return false
        }

        guard installPressedEventHandler() else {
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

    private func registerHotKey() -> Bool {
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            CarbonHotKey.registrationID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            NSLog("YIYI failed to register global hot key: keyCode=\(keyCode), modifiers=\(modifiers), status=\(status)")
            hotKeyRef = nil
            return false
        }

        return true
    }

    private func installPressedEventHandler() -> Bool {
        var eventType = CarbonHotKey.pressedEventType
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handlePressedEvent,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard status == noErr else {
            NSLog("YIYI failed to install global hot key handler: status=\(status)")
            return false
        }

        return true
    }

    private static let handlePressedEvent: EventHandlerUPP = { _, _, userData in
        guard let userData else {
            return noErr
        }

        let registrar = Unmanaged<GlobalHotKeyRegistrar>
            .fromOpaque(userData)
            .takeUnretainedValue()
        registrar.action()
        return noErr
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
        bindShortcutPreference()
        register(currentShortcut)
    }

    static func canRegister(_ shortcut: AppShortcut) -> Bool {
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            CarbonHotKey.availabilityProbeID,
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
        appState.settings.globalHotKeyShortcut
    }

    private func bindShortcutPreference() {
        settingsCancellable = appState.$settings
            .map(\.globalHotKeyShortcut)
            .map(RegisteredShortcut.init)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] registeredShortcut in
                self?.register(registeredShortcut.shortcut)
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
        // Keep the last working shortcut active when the user's new shortcut is unavailable.
        guard let previousRegistrar else {
            onConflict(failedShortcut)
            return
        }

        _ = previousRegistrar.register()
        registrar = previousRegistrar
        appState.updateShortcut(previousRegistrar.shortcut)
    }
}

private enum CarbonHotKey {
    static let registrationID = EventHotKeyID(signature: OSType(0x59495949), id: 1)
    static let availabilityProbeID = EventHotKeyID(signature: OSType(0x59495954), id: 1)

    static var pressedEventType: EventTypeSpec {
        EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
    }
}

/// Compares the actual registered keys only; display text changes should not force re-registration.
private struct RegisteredShortcut: Equatable {
    let shortcut: AppShortcut

    static func == (lhs: RegisteredShortcut, rhs: RegisteredShortcut) -> Bool {
        lhs.shortcut.keyCode == rhs.shortcut.keyCode
            && lhs.shortcut.modifiers == rhs.shortcut.modifiers
    }
}

private extension GlobalHotKeyRegistrar {
    var shortcut: AppShortcut {
        AppShortcut(keyCode: keyCode, modifiers: modifiers, display: display)
    }

    func matches(_ shortcut: AppShortcut) -> Bool {
        keyCode == shortcut.keyCode && modifiers == shortcut.modifiers
    }
}

private extension AppSettings {
    var globalHotKeyShortcut: AppShortcut {
        AppShortcut(
            keyCode: shortcutKeyCode,
            modifiers: shortcutModifiers,
            display: shortcutDisplay
        )
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
        appState.settings.globalHotKeyShortcut
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
                // The local monitor captures one keyDown and returns nil so it does not leak into the UI.
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
