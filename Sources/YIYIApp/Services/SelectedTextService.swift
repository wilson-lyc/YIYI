import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

protocol SelectedTextProviding: Sendable {
    func selectedText() async throws -> String
}

struct SelectedTextService: SelectedTextProviding {
    private static let selectionReadTimeout: Duration = .seconds(3)
    private static let accessibilityMessagingTimeout: Float = 0.7

    enum ProviderError: LocalizedError {
        case accessibilityPermissionMissing
        case emptySelection
        case selectionReadTimedOut

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionMissing:
                return "YIYI 需要辅助功能权限才能读取其他应用中的选中文本。请在系统设置中为 YIYI 开启 Accessibility。"
            case .emptySelection:
                return "未检测到选中文本。请先在任意应用中选中文本，再按快捷键。"
            case .selectionReadTimedOut:
                return "读取选中文本超时。请确认已为 YIYI 开启辅助功能权限，然后重试。"
            }
        }
    }

    func selectedText() async throws -> String {
        return try await selectedText(timeout: Self.selectionReadTimeout)
    }

    private func selectedText(timeout: Duration) async throws -> String {
        try await Self.withTimeout(timeout) {
            try await Self.provideSelectedText()
        }
    }

    private static func provideSelectedText() async throws -> String {
        try Task.checkCancellation()

        if let text = selectedTextFromAccessibility(), !text.isEmpty {
            return text
        }

        try Task.checkCancellation()

        if let text = try await selectedTextFromCopyShortcut(), !text.isEmpty {
            return text
        }

        throw ProviderError.emptySelection
    }

    private static func selectedTextFromAccessibility() -> String? {
        let systemWideElement = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWideElement, accessibilityMessagingTimeout)

        var focusedValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        guard focusedResult == .success, let focusedValue else {
            return nil
        }

        let focusedElement = focusedValue as! AXUIElement
        AXUIElementSetMessagingTimeout(focusedElement, accessibilityMessagingTimeout)

        var selectedValue: CFTypeRef?
        let selectedResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )

        guard selectedResult == .success else {
            return nil
        }

        return normalize(selectedValue as? String)
    }

    @MainActor
    private static func selectedTextFromCopyShortcut() async throws -> String? {
        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems ?? []
        let previousChangeCount = pasteboard.changeCount

        pasteboard.clearContents()
        sendCopyShortcut()

        do {
            let copiedText = try await copiedTextFromPasteboard(
                pasteboard,
                previousChangeCount: previousChangeCount,
                timeout: .milliseconds(900)
            )

            restorePasteboard(pasteboard, items: previousItems)
            return copiedText
        } catch {
            restorePasteboard(pasteboard, items: previousItems)
            throw error
        }
    }

    @MainActor
    private static func copiedTextFromPasteboard(
        _ pasteboard: NSPasteboard,
        previousChangeCount: Int,
        timeout: Duration
    ) async throws -> String? {
        let deadline = ContinuousClock.now.advanced(by: timeout)

        repeat {
            try Task.checkCancellation()

            if pasteboard.changeCount != previousChangeCount,
               let copiedText = normalize(pasteboard.string(forType: .string)) {
                return copiedText
            }

            try await Task.sleep(for: .milliseconds(40))
        } while ContinuousClock.now < deadline

        return normalize(pasteboard.string(forType: .string))
    }

    @MainActor
    private static func restorePasteboard(_ pasteboard: NSPasteboard, items: [NSPasteboardItem]) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private static func withTimeout<T: Sendable>(
        _ timeout: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let operationTask = Task.detached(priority: .userInitiated) {
            try await operation()
        }

        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(priority: .userInitiated) {
                try await operationTask.value
            }

            group.addTask(priority: .userInitiated) {
                try await Task.sleep(for: timeout)
                throw ProviderError.selectionReadTimedOut
            }

            do {
                guard let result = try await group.next() else {
                    throw CancellationError()
                }

                group.cancelAll()
                operationTask.cancel()
                return result
            } catch {
                group.cancelAll()
                operationTask.cancel()
                throw error
            }
        }
    }

    private static func sendCopyShortcut() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_C)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

        keyDown?.flags = CGEventFlags.maskCommand
        keyUp?.flags = CGEventFlags.maskCommand
        keyDown?.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp?.post(tap: CGEventTapLocation.cghidEventTap)
    }

    private static func normalize(_ text: String?) -> String? {
        let normalized = text?
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let normalized, !normalized.isEmpty else {
            return nil
        }

        return normalized
    }
}
