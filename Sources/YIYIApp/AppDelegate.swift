import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private var statusItem: NSStatusItem?
    private var floatingPanel: NSPanel?
    private var settingsWindow: NSWindow?
    private var didPositionFloatingPanel = false
    private var hotKeyRegistrar: GlobalHotKeyRegistrar?
    private var settingsCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        observeAppearancePreference()
        configureStatusBar()
        configureGlobalHotKey()
        SelectedTextReader.requestAccessibilityPermissionIfNeeded()
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出易译", action: #selector(quit), keyEquivalent: "q"))
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
        item.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "易译")
        item.button?.imagePosition = .imageLeading
        item.button?.title = " 易译"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "退出易译", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu

        statusItem = item
    }

    private func configureGlobalHotKey() {
        let registrar = GlobalHotKeyRegistrar { [weak self] in
            DispatchQueue.main.async {
                self?.startSelectedTextCaptureFlow()
            }
        }
        registrar.register()
        hotKeyRegistrar = registrar
    }

    @objc private func openFloatingPanel() {
        showFloatingPanel(activate: true)
    }

    @objc private func openSettings() {
        showSettingsWindow()
    }

    @objc private func refreshTranslation() {
        showFloatingPanel(activate: true)
        appState.refreshTranslation()
    }

    @objc private func captureSelectedText() {
        startSelectedTextCaptureFlow()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func startSelectedTextCaptureFlow() {
        appState.beginTranslation()
        showFloatingPanel(activate: false)

        Task { @MainActor in
            await appState.captureSelectedText()
            resizeFloatingPanelToFitContent()
        }
    }

    private func showFloatingPanel(activate: Bool) {
        if floatingPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 1),
                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = "易译"
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.isOpaque = false
            panel.backgroundColor = .clear

            let visualEffectView = NSVisualEffectView()
            visualEffectView.material = .popover
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.state = .active

            let hostingView = NSHostingView(
                rootView: TranslationPanelView(
                    appState: appState,
                    onRefreshTranslation: { [weak self] in self?.appState.refreshTranslation() }
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
            floatingPanel = panel
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
            window.title = "易译设置"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isOpaque = false
            window.backgroundColor = .clear
            window.minSize = NSSize(width: 840, height: 660)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(appState: appState))
            settingsWindow = window
        }

        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func observeAppearancePreference() {
        settingsCancellable = appState.$settings
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
