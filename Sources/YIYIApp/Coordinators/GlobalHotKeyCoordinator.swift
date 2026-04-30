import Combine
import Foundation

@MainActor
final class GlobalHotKeyCoordinator {
    private let viewModel: SettingsViewModel
    private let onTrigger: () -> Void
    private let onConflict: (AppShortcut) -> Void

    private var registrar: GlobalHotKeyRegistrar?
    private var settingsCancellable: AnyCancellable?

    init(
        viewModel: SettingsViewModel,
        onTrigger: @escaping () -> Void,
        onConflict: @escaping (AppShortcut) -> Void
    ) {
        self.viewModel = viewModel
        self.onTrigger = onTrigger
        self.onConflict = onConflict
    }

    func start() {
        bindShortcutPreference()
        register(currentShortcut)
    }

    private var currentShortcut: AppShortcut {
        viewModel.settings.globalHotKeyShortcut
    }

    private func bindShortcutPreference() {
        settingsCancellable = viewModel.$settings
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
        viewModel.updateShortcut(previousRegistrar.shortcut)
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
