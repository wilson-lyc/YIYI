import AppKit
import Combine
import SwiftUI

@MainActor
final class AppCoordinator: NSObject, NSWindowDelegate {
    private let settingsState: AppSettingsState
    private let translationPanelViewModel: TranslationPanelViewModel
    private let settingsViewModel: SettingsViewModel
    private var statusItem: NSStatusItem?
    private var floatingPanel: NSPanel?
    private var settingsWindow: NSWindow?
    private var didPositionFloatingPanel = false
    private var settingsCancellable: AnyCancellable?
    private var hotKeyCoordinator: GlobalHotKeyCoordinator?
    private var selectedTextCaptureTask: Task<Void, Never>?
    private var selectedTextCaptureTaskID: UUID?
    private var permissionCheckTimer: Timer?
    private var didShowPermissionAlert = false
    private var didShowPermissionGrantedRestartAlert = false

    init(
        settingsState: AppSettingsState = AppSettingsState(),
        translationService: TranslationServicing = TranslationService()
    ) {
        self.settingsState = settingsState
        self.translationPanelViewModel = TranslationPanelViewModel(
            settingsState: settingsState,
            translationService: translationService
        )
        self.settingsViewModel = SettingsViewModel(
            settingsState: settingsState,
            translationService: translationService
        )
        super.init()
    }

    func start() {
        configureMainMenu()
        observeAppearancePreference()
        configureStatusBar()
        startIfRequiredPermissionsAreGranted()
    }

    @objc private func openSettings() {
        showSettingsWindow()
    }

    @objc private func openAccessibilitySettings() {
        AppPermissionService.openAccessibilitySettings()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        appMenu.items.forEach { $0.target = self }
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "撤销", action: NSSelectorFromString("undo:"), keyEquivalent: "z"))

        let redoItem = NSMenuItem(title: "重做", action: NSSelectorFromString("redo:"), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)

        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))

        let pasteAndMatchStyleItem = NSMenuItem(
            title: "粘贴并匹配样式",
            action: #selector(NSTextView.pasteAsPlainText(_:)),
            keyEquivalent: "V"
        )
        pasteAndMatchStyleItem.keyEquivalentModifierMask = [.command, .option, .shift]
        editMenu.addItem(pasteAndMatchStyleItem)

        editMenu.addItem(NSMenuItem(title: "删除", action: #selector(NSText.delete(_:)), keyEquivalent: ""))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenu.items.forEach { $0.target = nil }
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func configureStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: "YIYI")
        item.button?.imagePosition = .imageOnly
        item.button?.title = ""
        statusItem = item
        refreshStatusMenu()
    }

    private func refreshStatusMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ""))

        if !AppPermissionService.hasAccessibilityPermission {
            menu.addItem(NSMenuItem(title: "授权辅助功能权限", action: #selector(openAccessibilitySettings), keyEquivalent: ""))
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem?.menu = menu
    }

    private func startIfRequiredPermissionsAreGranted() {
        guard AppPermissionService.hasAccessibilityPermission else {
            pauseForMissingPermissions()
            return
        }

        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
        statusItem?.button?.title = ""
        refreshStatusMenu()

        guard !didShowPermissionAlert else {
            showPermissionGrantedRestartAlertIfNeeded()
            return
        }

        guard hotKeyCoordinator == nil else {
            return
        }

        configureGlobalHotKeyController()
    }

    private func pauseForMissingPermissions() {
        statusItem?.button?.title = ""
        refreshStatusMenu()
        AppPermissionService.requestAccessibilityPermissionIfNeeded()
        startPermissionPolling()
        showMissingPermissionsAlertIfNeeded()
    }

    private func startPermissionPolling() {
        guard permissionCheckTimer == nil else {
            return
        }

        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.startIfRequiredPermissionsAreGranted()
            }
        }
    }

    private func showMissingPermissionsAlertIfNeeded() {
        guard !didShowPermissionAlert else {
            return
        }

        didShowPermissionAlert = true
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "YIYI 需要辅助功能权限"
        alert.informativeText = "YIYI 需要辅助功能权限来获取你选中的文本，并监听划词翻译快捷键。请在系统设置中为 YIYI 开启 Accessibility，授权后即可使用划词翻译。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")

        if alert.runModal() == .alertFirstButtonReturn {
            AppPermissionService.openAccessibilitySettings()
        }
    }

    private func showPermissionGrantedRestartAlertIfNeeded() {
        guard !didShowPermissionGrantedRestartAlert else {
            return
        }

        didShowPermissionGrantedRestartAlert = true
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "辅助功能权限已开启"
        alert.informativeText = "YIYI 已获得辅助功能权限。请重启 YIYI，重启后即可正常使用划词翻译快捷键。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "退出 YIYI")
        alert.addButton(withTitle: "稍后")

        if alert.runModal() == .alertFirstButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }

    private func configureGlobalHotKeyController() {
        let coordinator = GlobalHotKeyCoordinator(
            viewModel: settingsViewModel,
            onTrigger: { [weak self] in
                self?.startSelectedTextCaptureFlow()
            },
            onConflict: { [weak self] shortcut in
                self?.showShortcutConflictAlert(for: shortcut)
            }
        )
        coordinator.start()
        hotKeyCoordinator = coordinator
    }

    private func startSelectedTextCaptureFlow() {
        selectedTextCaptureTask?.cancel()
        let taskID = UUID()
        selectedTextCaptureTaskID = taskID
        translationPanelViewModel.beginTranslation()
        showFloatingPanel(activate: false)

        selectedTextCaptureTask = Task { @MainActor in
            defer {
                if selectedTextCaptureTaskID == taskID {
                    selectedTextCaptureTask = nil
                    selectedTextCaptureTaskID = nil
                }
            }

            await translationPanelViewModel.captureSelectedText()
            guard !Task.isCancelled else {
                return
            }

            resizeFloatingPanelToFitContent()
        }
    }

    private func showFloatingPanel(activate: Bool) {
        if floatingPanel == nil {
            floatingPanel = makeFloatingPanel()
        }

        resizeFloatingPanelToFitContent()
        if !didPositionFloatingPanel {
            floatingPanel?.center()
            didPositionFloatingPanel = true
        }

        if activate {
            floatingPanel?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            floatingPanel?.orderFrontRegardless()
        }
    }

    private func makeFloatingPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 1),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.delegate = self

        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .popover
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active

        let hostingView = NSHostingView(
            rootView: TranslationPanelView(
                viewModel: translationPanelViewModel,
                onRefreshTranslation: { [weak self] in self?.translationPanelViewModel.refreshTranslation() }
            )
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        visualEffectView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
        ])

        panel.contentView = visualEffectView
        panel.setContentSize(hostingView.fittingSize)
        return panel
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingPanel = notification.object as? NSPanel, closingPanel === floatingPanel else {
            return
        }

        selectedTextCaptureTask?.cancel()
        selectedTextCaptureTask = nil
        selectedTextCaptureTaskID = nil
        translationPanelViewModel.cancelCurrentWork()
    }

    private func resizeFloatingPanelToFitContent() {
        guard
            let floatingPanel,
            let hostingView = floatingPanel.contentView?.subviews.first
        else {
            return
        }

        floatingPanel.setContentSize(hostingView.fittingSize)
    }

    private func showSettingsWindow() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "YIYI 设置"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isOpaque = false
            window.backgroundColor = .clear
            window.minSize = NSSize(width: 840, height: 660)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(viewModel: settingsViewModel))
            settingsWindow = window
        }

        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showShortcutConflictAlert(for shortcut: AppShortcut) {
        Task { @MainActor in
            showSettingsWindow()

            let alert = NSAlert()
            alert.messageText = "快捷键 \(shortcut.display) 已被占用"
            alert.informativeText = "YIYI 无法注册当前划词翻译快捷键。请在设置中换绑一个未被其他应用或系统占用的快捷键。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "去换绑")
            alert.runModal()
        }
    }

    private func observeAppearancePreference() {
        settingsCancellable = settingsState.$settings
            .map(\.appearancePreference)
            .removeDuplicates()
            .sink { [weak self] preference in
                self?.applyAppearance(preference)
            }
    }

    private func applyAppearance(_ preference: AppearancePreference) {
        NSApp.appearance = preference.nsAppearance
    }
}

private extension AppearancePreference {
    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}
