import Combine
import Foundation

@MainActor
final class GlobalHotKeyCoordinator {
    private let viewModel: SettingsViewModel
    private let onTrigger: () -> Void
    private let onConflict: (AppShortcut) -> Void

    private var registrar: GlobalHotKeyRegistrar?
    private var settingsCancellable: AnyCancellable?
    private var isSuspended = false

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

    func setSuspended(_ isSuspended: Bool) {
        guard self.isSuspended != isSuspended else {
            return
        }

        self.isSuspended = isSuspended

        if isSuspended {
            registrar?.unregister()
        } else {
            register(currentShortcut)
        }
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
        guard !isSuspended else {
            return
        }

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

        guard nextRegistrar.isRegistered else {
            restore(previousRegistrar, failedShortcut: shortcut)
            return
        }

        registrar = nextRegistrar
    }

    private func restore(_ previousRegistrar: GlobalHotKeyRegistrar?, failedShortcut: AppShortcut) {
        onConflict(failedShortcut)

        // Keep the last working shortcut active when the user's new shortcut is unavailable.
        guard let previousRegistrar else {
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
