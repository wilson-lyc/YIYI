import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var originalText: String
    @Published var translatedText: String
    @Published var status: TranslationStatus
    @Published var toast: ToastMessage?
    @Published var settings: AppSettings {
        didSet {
            guard persistsSettings else {
                return
            }

            settings.save()
        }
    }

    private let persistsSettings: Bool
    private let translationController: TranslationController

    init(
        originalText: String = "Select text anywhere on macOS, press Option + D, and YIYI will translate it in place without breaking your reading flow.",
        translatedText: String = "在 macOS 任意位置选中文本，按下 Option + D，YIYI 会在不打断阅读流程的情况下就地完成翻译。",
        status: TranslationStatus = .ready,
        settings: AppSettings = AppSettings.load(),
        persistsSettings: Bool = true,
        translationController: TranslationController = TranslationController()
    ) {
        self.originalText = originalText
        self.translatedText = translatedText
        self.status = status
        self.settings = settings
        self.persistsSettings = persistsSettings
        self.translationController = translationController
    }

    func beginTranslation() {
        translationController.cancelActiveTranslation()
        status = .loading("准备翻译……")
        translatedText = ""
    }

    func captureSelectedText() async {
        beginTranslation()

        do {
            originalText = try await SelectedTextReader.readSelectedText()
            settings.sourceLanguage = "自动识别"
            settings.targetLanguage = TranslationLanguageDetector.defaultTargetLanguage(for: originalText)
            try await translationController.translateCurrentText(in: self)
        } catch {
            translatedText = ""
            status = .error(error.localizedDescription)
        }
    }

    func refreshTranslation() {
        translationController.startTranslation(in: self, statusMessage: "重新翻译中……")
    }

    func updateTargetLanguage(_ language: String) {
        guard settings.targetLanguage != language else {
            return
        }

        settings.targetLanguage = language
        translationController.startTranslation(in: self, statusMessage: "正在切换语言……")
    }

    func showEmptySelectionHint() {
        status = .error("未检测到选中文本。请先在任意应用中选中文本，再按 \(settings.shortcutDisplay)。")
    }

    func updateShortcut(_ shortcut: AppShortcut) {
        var updatedSettings = settings
        updatedSettings.shortcutDisplay = shortcut.display
        updatedSettings.shortcutKeyCode = shortcut.keyCode
        updatedSettings.shortcutModifiers = shortcut.modifiers
        settings = updatedSettings
    }

    func dismissToast(id: UUID) {
        guard toast?.id == id else {
            return
        }

        toast = nil
    }

    func showToast(_ message: String) {
        toast = ToastMessage(message: message)
    }
}

#if DEBUG
extension AppState {
    static var settingsPreview: AppState {
        AppState(
            settings: .previewConfigured,
            persistsSettings: false
        )
    }

    static var translatedPreview: AppState {
        AppState(
            originalText: "The menu bar translator should feel lightweight, fast, and stay out of the reader's way.",
            translatedText: "菜单栏翻译工具应该轻量、快速，并且不打断读者的阅读流程。",
            status: .translated,
            settings: .previewConfigured,
            persistsSettings: false
        )
    }

    static var loadingPreview: AppState {
        AppState(
            originalText: "Preview the loading state without making a network request.",
            translatedText: "",
            status: .loading("正在等待结果……"),
            settings: .previewConfigured,
            persistsSettings: false
        )
    }

    static var errorPreview: AppState {
        AppState(
            originalText: "This text failed to translate.",
            translatedText: "",
            status: .error("翻译失败，请检查模型设置或网络连接。"),
            settings: .previewConfigured,
            persistsSettings: false
        )
    }
}

extension AppSettings {
    static var previewConfigured: AppSettings {
        let defaultModel = ModelVersion(
            id: ModelVersion.defaultOpenAI.id,
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            apiKey: "sk-preview-key",
            modelName: "gpt-4o-mini"
        )
        let compatibleModel = ModelVersion(
            name: "兼容模型",
            baseURL: "https://api.deepseek.com/v1",
            apiKey: "sk-preview-key",
            modelName: "deepseek-chat"
        )

        return AppSettings(
            sourceLanguage: "自动识别",
            targetLanguage: "简体中文",
            shortcutDisplay: "⌥D",
            launchAtLogin: true,
            modelVersions: [
                defaultModel,
                compatibleModel
            ],
            activeModelVersionID: defaultModel.id,
            promptVersions: [
                .defaultTranslation,
                PromptVersion(
                    name: "技术文档",
                    systemPrompt: "You are a precise technical translator.",
                    prompt: """
                    Translate the selected technical text into clear Simplified Chinese.
                    Keep product names, API names, code symbols, and URLs unchanged.

                    {{selectedText}}
                    """
                )
            ],
            activePromptVersionID: PromptVersion.defaultTranslation.id
        )
    }
}
#endif
