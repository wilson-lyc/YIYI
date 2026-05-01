import Combine
import Foundation

@MainActor
final class TranslationPanelViewModel: ObservableObject {
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
            originalText = try await selectedTextProvider.selectedText()
            try Task.checkCancellation()
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
            status = .error("未选中需要翻译的文本")
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

    private func showToast(_ message: String) {
        toast = ToastMessage(message: message)
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

        do {
            let translation = try await translationService.translate(text: originalText, settings: settings)
            try Task.checkCancellation()
            translatedText = translation.text
            totalTokens = translation.totalTokens
            status = .translated
        } catch {
            if let translationError = error as? TranslationError, translationError.isTimeout {
                showToast(error.localizedDescription)
            }
            throw error
        }
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
