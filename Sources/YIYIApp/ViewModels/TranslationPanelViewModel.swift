import Combine
import Foundation

@MainActor
final class TranslationPanelViewModel: ObservableObject {
    private static let selectionCaptureTimeout: Duration = .seconds(4)

    @Published var originalText: String
    @Published var translatedText: String
    @Published var status: TranslationStatus
    @Published var toast: ToastMessage?
    @Published private(set) var totalTokens: Int?
    @Published private(set) var settings: AppSettings

    private let settingsState: AppSettingsState
    private let translationService: TranslationServicing
    private let selectedTextProvider: SelectedTextProviding
    private let clipboardService: ClipboardServicing
    private var activeTranslationTask: Task<Void, Never>?
    private var activeTranslationTaskID: UUID?
    private var settingsCancellable: AnyCancellable?

    init(
        settingsState: AppSettingsState,
        originalText: String = "Select text anywhere on macOS, press Option + D, and YIYI will translate it in place without breaking your reading flow.",
        translatedText: String = "在 macOS 任意位置选中文本，按下 Option + D，YIYI 会在不打断阅读流程的情况下就地完成翻译。",
        totalTokens: Int? = nil,
        status: TranslationStatus = .ready,
        translationService: TranslationServicing = TranslationService(),
        selectedTextProvider: SelectedTextProviding = SelectedTextService(),
        clipboardService: ClipboardServicing = ClipboardService()
    ) {
        self.settingsState = settingsState
        self.originalText = originalText
        self.translatedText = translatedText
        self.totalTokens = totalTokens
        self.status = status
        self.settings = settingsState.settings
        self.translationService = translationService
        self.selectedTextProvider = selectedTextProvider
        self.clipboardService = clipboardService

        settingsCancellable = settingsState.$settings
            .removeDuplicates()
            .sink { [weak self] settings in
                self?.settings = settings
            }
    }

    var tokenCountText: String {
        guard let totalTokens else {
            return "— tokens"
        }

        return "\(totalTokens) tokens"
    }

    func beginSelectionCapture() {
        cancelActiveTranslation()
        status = .loading("读取选中文本……")
        originalText = ""
        translatedText = ""
        totalTokens = nil
    }

    func cancelCurrentWork() {
        cancelActiveTranslation()
        if status.isLoading {
            status = .ready
        }
    }

    func captureSelectedTextForTranslation() async -> Bool {
        do {
            let capturedText = try await selectedTextWithTimeout()
            try Task.checkCancellation()
            originalText = capturedText
            updateSettings { settings in
                settings.sourceLanguage = "自动识别"
                settings.targetLanguage = TranslationLanguageDetectionService.defaultTargetLanguage(for: originalText)
            }
            status = .loading("翻译中……")
            return true
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else {
                return false
            }

            originalText = ""
            translatedText = ""
            totalTokens = nil
            status = .error(selectionCaptureErrorMessage(for: error))
            return false
        }
    }

    func translateCapturedText() {
        guard !originalText.isEmpty else {
            translatedText = ""
            totalTokens = nil
            status = .error("未选中需要翻译的文本")
            return
        }

        startTranslation(statusMessage: "翻译中……")
    }

    func refreshTranslation() {
        guard !originalText.isEmpty else {
            translatedText = ""
            totalTokens = nil
            status = .error("未选中需要翻译的文本")
            return
        }

        startTranslation(statusMessage: "翻译中……")
    }

    func updateSourceLanguage(_ language: String) {
        updateSettings { settings in
            settings.sourceLanguage = language
        }
    }

    func updateTargetLanguage(_ language: String) {
        guard settings.targetLanguage != language else {
            return
        }

        updateSettings { settings in
            settings.targetLanguage = language
        }
        startTranslation(statusMessage: "翻译中……")
    }

    func copyTranslation() {
        guard !translatedText.isEmpty else {
            return
        }

        clipboardService.copy(translatedText)
    }

    func dismissToast(id: UUID) {
        guard toast?.id == id else {
            return
        }

        toast = nil
    }

    private func selectionCaptureErrorMessage(for error: Error) -> String {
        if case SelectedTextService.ProviderError.accessibilityPermissionMissing = error {
            return error.localizedDescription
        }

        if case SelectedTextService.ProviderError.selectionReadTimedOut = error {
            return error.localizedDescription
        }

        return "未选中需要翻译的文本"
    }

    private func selectedTextWithTimeout() async throws -> String {
        let selectedTextProvider = selectedTextProvider
        let captureTask = Task.detached(priority: .userInitiated) {
            try await selectedTextProvider.selectedText()
        }

        let timeoutTask = Task<String, Error>.detached(priority: .userInitiated) {
            try await Task.sleep(for: Self.selectionCaptureTimeout)
            throw SelectedTextService.ProviderError.selectionReadTimedOut
        }

        do {
            let text = try await race(captureTask, against: timeoutTask)
            captureTask.cancel()
            timeoutTask.cancel()
            return text
        } catch {
            captureTask.cancel()
            timeoutTask.cancel()
            throw error
        }
    }

    private func race(
        _ firstTask: Task<String, Error>,
        against secondTask: Task<String, Error>
    ) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let raceState = TranslationPanelTaskRaceState()

            Task.detached(priority: .userInitiated) {
                do {
                    raceState.resume(continuation, with: .success(try await firstTask.value))
                } catch {
                    raceState.resume(continuation, with: .failure(error))
                }
            }

            Task.detached(priority: .userInitiated) {
                do {
                    raceState.resume(continuation, with: .success(try await secondTask.value))
                } catch {
                    raceState.resume(continuation, with: .failure(error))
                }
            }
        }
    }

    private func updateSettings(_ update: (inout AppSettings) -> Void) {
        var nextSettings = settingsState.settings
        update(&nextSettings)
        settingsState.settings = nextSettings
    }

    private func cancelActiveTranslation() {
        activeTranslationTask?.cancel()
        activeTranslationTask = nil
        activeTranslationTaskID = nil
    }

    private func translateCurrentText() async throws {
        status = .loading("翻译中……")

        let translation = try await translationService.translate(text: originalText, settings: settings)
        try Task.checkCancellation()
        translatedText = translation.text
        totalTokens = translation.totalTokens
        status = .translated
    }

    private func startTranslation(statusMessage: String) {
        activeTranslationTask?.cancel()
        let taskID = UUID()
        activeTranslationTaskID = taskID
        status = .loading(statusMessage)
        translatedText = ""
        totalTokens = nil

        activeTranslationTask = Task { @MainActor in
            defer {
                if activeTranslationTaskID == taskID {
                    activeTranslationTask = nil
                    activeTranslationTaskID = nil
                }
            }

            do {
                try await translateCurrentText()
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                translatedText = ""
                totalTokens = nil
                status = .error(error.localizedDescription)
            }
        }
    }

}

private final class TranslationPanelTaskRaceState: @unchecked Sendable {
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
