import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics

enum SelectedTextReader {
    enum ReadError: LocalizedError {
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

    static func requestAccessibilityPermissionIfNeeded() {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func readSelectedText(timeout: Duration = .seconds(3)) async throws -> String {
        let readTask = Task.detached(priority: .userInitiated) {
            try await readSelectedTextWithoutTimeout()
        }

        let timeoutTask = Task<String, Error> {
            try await Task.sleep(for: timeout)
            throw ReadError.selectionReadTimedOut
        }

        do {
            let text = try await race(readTask, against: timeoutTask)
            timeoutTask.cancel()
            return text
        } catch {
            readTask.cancel()
            timeoutTask.cancel()
            throw error
        }
    }

    private static func readSelectedTextWithoutTimeout() async throws -> String {
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

    private static func race(
        _ readTask: Task<String, Error>,
        against timeoutTask: Task<String, Error>
    ) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let raceState = SelectionReadRaceState()

            Task {
                do {
                    raceState.resume(continuation, with: .success(try await readTask.value))
                } catch {
                    raceState.resume(continuation, with: .failure(error))
                }
            }

            Task {
                do {
                    raceState.resume(continuation, with: .success(try await timeoutTask.value))
                } catch {
                    raceState.resume(continuation, with: .failure(error))
                }
            }
        }
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

private final class SelectionReadRaceState: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(_ continuation: CheckedContinuation<String, Error>, with result: Result<String, Error>) {
        lock.lock()
        defer { lock.unlock() }

        guard !didResume else {
            return
        }

        didResume = true
        continuation.resume(with: result)
    }
}
