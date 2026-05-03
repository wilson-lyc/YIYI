import AppKit
import Combine
import SwiftUI

@MainActor
final class AppCoordinator: NSObject, NSWindowDelegate {
    private let settingsState: AppSettingsState
    private let translationPanelViewModel: TranslationPanelViewModel
    private let translationPanelPinState = TranslationPanelPinState()
    private let settingsViewModel: SettingsViewModel
    private let permissionService: AppPermissionService
    private var statusItem: NSStatusItem?
    private var floatingPanel: NSPanel?
    private var settingsWindow: NSWindow?
    private var permissionWindow: NSWindow?
    private var didPositionFloatingPanel = false
    private var settingsCancellable: AnyCancellable?
    private var floatingPanelSizeCancellable: AnyCancellable?
    private var hotKeyCoordinator: GlobalHotKeyCoordinator?
    private var selectedTextCaptureTask: Task<Void, Never>?
    private var selectedTextCaptureTaskID: UUID?
    private var isApplyingFloatingPanelSize = false

    init(
        settingsState: AppSettingsState = AppSettingsState(),
        permissionService: AppPermissionService = AppPermissionService(),
        translationService: TranslationServicing = TranslationService()
    ) {
        self.settingsState = settingsState
        self.permissionService = permissionService
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
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "translate", accessibilityDescription: "YIYI")
        item.button?.imagePosition = .imageOnly
        item.button?.title = ""
        statusItem = item
        refreshStatusMenu()
    }

    private func refreshStatusMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ""))

        if !AppPermissionService.hasFullPermission {
            menu.addItem(NSMenuItem(title: "授权辅助功能权限", action: #selector(openAccessibilitySettings), keyEquivalent: ""))
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem?.menu = menu
    }

    private func startIfRequiredPermissionsAreGranted() {
        permissionService.refresh()
        guard permissionService.hasFullPermission else {
            showPermissionGuideWindow()
            permissionService.startMonitoring { [weak self] in
                self?.startIfRequiredPermissionsAreGranted()
            }
            return
        }

        refreshStatusMenu()
        permissionService.stopMonitoring()
        configureGlobalHotKeyController()
    }

    private func configureGlobalHotKeyController() {
        guard hotKeyCoordinator == nil else {
            return
        }

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

    private func showPermissionGuideWindow() {
        if permissionWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 230),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "权限引导"
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.isMovableByWindowBackground = true
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.hasShadow = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: PermissionsGuideView(
                    permissionService: permissionService,
                    onReject: { NSApplication.shared.terminate(nil) },
                    onOpenSettings: { [weak self] in self?.permissionService.requestRequiredPermissions() },
                    onFinish: { [weak self] in self?.finishPermissionGuide() }
                )
            )
            permissionWindow = window
        }

        permissionWindow?.center()
        permissionWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finishPermissionGuide() {
        permissionService.refresh()
        guard permissionService.hasFullPermission else {
            return
        }

        permissionWindow?.close()
        permissionWindow = nil
        startIfRequiredPermissionsAreGranted()
    }

    private func startSelectedTextCaptureFlow() {
        selectedTextCaptureTask?.cancel()
        let taskID = UUID()
        selectedTextCaptureTaskID = taskID
        translationPanelViewModel.beginSelectionCapture()
        showFloatingPanel(activate: false)

        selectedTextCaptureTask = Task { @MainActor in
            defer {
                if selectedTextCaptureTaskID == taskID {
                    selectedTextCaptureTask = nil
                    selectedTextCaptureTaskID = nil
                }
            }

            let didCaptureSelectedText = await translationPanelViewModel.captureSelectedTextForTranslation()
            guard !Task.isCancelled else {
                return
            }

            showFloatingPanel(activate: true)

            guard didCaptureSelectedText else {
                return
            }

            translationPanelViewModel.translateCapturedText()
        }
    }

    private func showFloatingPanel(activate: Bool = true) {
        if floatingPanel == nil {
            floatingPanel = makeFloatingPanel()
        }

        applyFloatingPanelSize(settingsState.settings, animate: false)
        if !didPositionFloatingPanel {
            floatingPanel?.center()
            didPositionFloatingPanel = true
        }

        if activate {
            NSApp.activate(ignoringOtherApps: true)
            floatingPanel?.makeKeyAndOrderFront(nil)
        } else {
            floatingPanel?.orderFrontRegardless()
        }
    }

    private func makeFloatingPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: settingsState.settings.translationPanelWidth,
                height: settingsState.settings.translationPanelHeight
            ),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isEnabled = true
        panel.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        panel.standardWindowButton(.zoomButton)?.isEnabled = false
        panel.contentMinSize = NSSize(
            width: AppSettings.translationPanelWidthRange.lowerBound,
            height: AppSettings.translationPanelHeightRange.lowerBound
        )
        panel.contentMaxSize = NSSize(
            width: AppSettings.translationPanelWidthRange.upperBound,
            height: AppSettings.translationPanelHeightRange.upperBound
        )
        panel.delegate = self

        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .popover
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active

        let hostingView = NSHostingView(
            rootView: TranslationPanelView(
                viewModel: translationPanelViewModel,
                pinState: translationPanelPinState,
                onRefreshTranslation: { [weak self] in self?.translationPanelViewModel.refreshTranslation() },
                onTogglePinned: { [weak self] in self?.toggleTranslationPanelPinned() }
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
        applyFloatingPanelSize(settingsState.settings, to: panel, animate: false)
        return panel
    }

    func windowDidResize(_ notification: Notification) {
        guard
            !isApplyingFloatingPanelSize,
            let resizedPanel = notification.object as? NSPanel,
            resizedPanel === floatingPanel
        else {
            return
        }

        let contentSize = resizedPanel.contentView?.bounds.size ?? resizedPanel.contentRect(forFrameRect: resizedPanel.frame).size
        let width = AppSettings.clampedTranslationPanelWidth(Int(contentSize.width.rounded()))
        let height = AppSettings.clampedTranslationPanelHeight(Int(contentSize.height.rounded()))

        guard
            settingsState.settings.translationPanelWidth != width ||
                settingsState.settings.translationPanelHeight != height
        else {
            return
        }

        var settings = settingsState.settings
        settings.translationPanelWidth = width
        settings.translationPanelHeight = height
        settingsState.settings = settings
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingPanel = notification.object as? NSPanel, closingPanel === floatingPanel else {
            return
        }

        translationPanelPinState.isPinned = false
        cancelTranslationPanelWork()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard
            let resigningPanel = notification.object as? NSPanel,
            resigningPanel === floatingPanel,
            !translationPanelPinState.isPinned
        else {
            return
        }

        dismissFloatingPanel(cancelWork: true)
    }

    private func toggleTranslationPanelPinned() {
        let nextPinnedState = !translationPanelPinState.isPinned
        translationPanelPinState.isPinned = nextPinnedState

        guard !nextPinnedState else {
            return
        }

        dismissFloatingPanel(cancelWork: true)
    }

    private func dismissFloatingPanel(cancelWork: Bool) {
        floatingPanel?.orderOut(nil)

        guard cancelWork else {
            return
        }

        cancelTranslationPanelWork()
    }

    private func cancelTranslationPanelWork() {
        selectedTextCaptureTask?.cancel()
        selectedTextCaptureTask = nil
        selectedTextCaptureTaskID = nil
        translationPanelViewModel.cancelCurrentWork()
    }

    private func applyFloatingPanelSize(_ settings: AppSettings, animate: Bool) {
        guard let floatingPanel else {
            return
        }

        applyFloatingPanelSize(settings, to: floatingPanel, animate: animate)
    }

    private func applyFloatingPanelSize(_ settings: AppSettings, to panel: NSPanel, animate: Bool) {
        let contentSize = NSSize(
            width: AppSettings.clampedTranslationPanelWidth(settings.translationPanelWidth),
            height: AppSettings.clampedTranslationPanelHeight(settings.translationPanelHeight)
        )

        guard panel.contentRect(forFrameRect: panel.frame).size != contentSize else {
            return
        }

        isApplyingFloatingPanelSize = true
        panel.setContentSize(contentSize)
        isApplyingFloatingPanelSize = false
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
            window.contentView = NSHostingView(
                rootView: SettingsView(
                    viewModel: settingsViewModel,
                    onShortcutRecordingChanged: { [weak self] isRecording in
                        self?.hotKeyCoordinator?.setSuspended(isRecording)
                    }
                )
            )
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

        floatingPanelSizeCancellable = settingsState.$settings
            .map { settings in
                FloatingPanelSize(width: settings.translationPanelWidth, height: settings.translationPanelHeight)
            }
            .removeDuplicates()
            .sink { [weak self] size in
                guard let self else {
                    return
                }

                var settings = settingsState.settings
                settings.translationPanelWidth = size.width
                settings.translationPanelHeight = size.height
                applyFloatingPanelSize(settings, animate: true)
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

private struct FloatingPanelSize: Equatable {
    let width: Int
    let height: Int
}
