import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics

enum SelectedTextReader {
    enum ReadError: LocalizedError {
        case accessibilityPermissionMissing
        case emptySelection

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionMissing:
                return "易译需要辅助功能权限才能读取其他应用中的选中文本。请在系统设置中为易译开启 Accessibility。"
            case .emptySelection:
                return "未检测到选中文本。请先在任意应用中选中文本，再按快捷键。"
            }
        }
    }

    static func requestAccessibilityPermissionIfNeeded() {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func readSelectedText() async throws -> String {
        requestAccessibilityPermissionIfNeeded()

        guard AXIsProcessTrusted() else {
            throw ReadError.accessibilityPermissionMissing
        }

        if let text = readViaAccessibility(), !text.isEmpty {
            return text
        }

        if let text = await readViaCopyShortcut(), !text.isEmpty {
            return text
        }

        throw ReadError.emptySelection
    }

    private static func readViaAccessibility() -> String? {
        let systemWideElement = AXUIElementCreateSystemWide()
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
    private static func readViaCopyShortcut() async -> String? {
        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems ?? []

        pasteboard.clearContents()
        sendCopyShortcut()

        try? await Task.sleep(for: .milliseconds(140))
        let copiedText = normalize(pasteboard.string(forType: .string))

        pasteboard.clearContents()
        if !previousItems.isEmpty {
            pasteboard.writeObjects(previousItems)
        }

        return copiedText
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
