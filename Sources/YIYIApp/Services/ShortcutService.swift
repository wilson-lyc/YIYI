import Foundation

protocol ShortcutAvailabilityChecking: Sendable {
    @MainActor func canRegister(_ shortcut: AppShortcut) -> Bool
}

struct ShortcutAvailabilityService: ShortcutAvailabilityChecking {
    @MainActor
    func canRegister(_ shortcut: AppShortcut) -> Bool {
        GlobalHotKeyRegistrar.canRegister(shortcut)
    }
}
