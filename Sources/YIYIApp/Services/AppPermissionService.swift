import AppKit
import ApplicationServices
import Combine

struct AppPermissionRequirement: Identifiable, Equatable {
    enum Kind: String {
        case accessibility
    }

    let kind: Kind
    let title: String
    let description: String
    let isGranted: Bool

    var id: Kind { kind }
}

@MainActor
final class AppPermissionService: ObservableObject {
    @Published private(set) var requirements: [AppPermissionRequirement]

    private var monitorTimer: Timer?
    private var onFullPermissionGranted: (() -> Void)?

    init() {
        self.requirements = Self.currentRequirements()
    }

    var hasFullPermission: Bool {
        requirements.allSatisfy(\.isGranted)
    }

    func refresh() {
        let previousHasFullPermission = hasFullPermission
        requirements = Self.currentRequirements()

        if !previousHasFullPermission, hasFullPermission {
            onFullPermissionGranted?()
        }
    }

    func requestRequiredPermissions() {
        requestAccessibilityPermissionIfNeeded()
    }

    func startMonitoring(onFullPermissionGranted: @escaping () -> Void) {
        self.onFullPermissionGranted = onFullPermissionGranted
        refresh()

        guard monitorTimer == nil else {
            return
        }

        monitorTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        onFullPermissionGranted = nil
    }

    private var hasAccessibilityPermission: Bool {
        Self.hasAccessibilityPermission
    }

    private func requestAccessibilityPermissionIfNeeded() {
        guard !hasAccessibilityPermission else {
            return
        }

        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func openAccessibilitySettings() {
        Self.openAccessibilitySettings()
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static var hasFullPermission: Bool {
        currentRequirements().allSatisfy(\.isGranted)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private static func currentRequirements() -> [AppPermissionRequirement] {
        [
            AppPermissionRequirement(
                kind: .accessibility,
                title: "辅助功能权限",
                description: "用于读取其他应用中的选中文本，并在需要时模拟复制操作。",
                isGranted: hasAccessibilityPermission
            )
        ]
    }
}
