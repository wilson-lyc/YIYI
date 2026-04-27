import AppKit
import Carbon.HIToolbox

final class GlobalHotKeyRegistrar {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var eventType = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
    )

    private let keyCode: UInt32
    private let modifiers: UInt32
    private let action: () -> Void

    init(
        keyCode: UInt32 = UInt32(kVK_ANSI_D),
        modifiers: UInt32 = UInt32(optionKey),
        action: @escaping () -> Void
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action
    }

    deinit {
        unregister()
    }

    func register() {
        unregister()

        InstallEventHandler(
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

        let hotKeyID = EventHotKeyID(signature: OSType(0x59495949), id: UInt32(1))
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
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
