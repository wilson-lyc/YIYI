import Carbon.HIToolbox
import Foundation

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

    var shortcut: AppShortcut {
        AppShortcut(keyCode: keyCode, modifiers: modifiers, display: display)
    }

    func matches(_ shortcut: AppShortcut) -> Bool {
        keyCode == shortcut.keyCode && modifiers == shortcut.modifiers
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
