import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var originalText: String
    @Published var translatedText: String
    @Published var status: TranslationStatus
    @Published var settings: AppSettings {
        didSet {
            guard persistsSettings else {
                return
            }

            settings.save()
        }
    }

    private let persistsSettings: Bool

    init(
        originalText: String = "Select text anywhere on macOS, press Option + D, and YIYI will translate it in place without breaking your reading flow.",
        translatedText: String = "在 macOS 任意位置选中文本，按下 Option + D，易译会在不打断阅读流程的情况下就地完成翻译。",
        status: TranslationStatus = .ready,
        settings: AppSettings = AppSettings.load(),
        persistsSettings: Bool = true
    ) {
        self.originalText = originalText
        self.translatedText = translatedText
        self.status = status
        self.settings = settings
        self.persistsSettings = persistsSettings
    }

    func beginTranslation() {
        status = .loading
        translatedText = ""
    }

    func captureSelectedText() async {
        beginTranslation()

        do {
            originalText = try await SelectedTextReader.readSelectedText()
            settings.sourceLanguage = "自动识别"
            settings.targetLanguage = TranslationLanguageDetector.defaultTargetLanguage(for: originalText)
            try await translateCurrentText()
        } catch {
            translatedText = ""
            status = .error(error.localizedDescription)
        }
    }

    func translateCurrentText() async throws {
        let text = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw SelectedTextReader.ReadError.emptySelection
        }

        status = .loading
        translatedText = try await DeepSeekTranslationClient(settings: settings).translate(text)
        status = .translated
    }

    func refreshTranslation() {
        status = .loading
        translatedText = ""

        Task { @MainActor in
            do {
                try await translateCurrentText()
            } catch {
                translatedText = ""
                status = .error(error.localizedDescription)
            }
        }
    }

    func showEmptySelectionHint() {
        status = .error("未检测到选中文本。请先在任意应用中选中文本，再按 \(settings.shortcutDisplay)。")
    }

    func addPromptVersion() -> UUID {
        let nextIndex = settings.promptVersions.count + 1
        let version = PromptVersion(
            name: "提示词 \(nextIndex)",
            systemPrompt: PromptVersion.defaultSystemPrompt,
            prompt: """
            Translate the selected text into \(settings.targetLanguage).
            Return only the result.

            {{selectedText}}
            """
        )
        settings.promptVersions.append(version)
        settings.activePromptVersionID = version.id
        return version.id
    }

    func deletePromptVersion(id: UUID) {
        guard settings.promptVersions.count > 1 else {
            return
        }

        settings.promptVersions.removeAll { $0.id == id }
        if !settings.promptVersions.contains(where: { $0.id == settings.activePromptVersionID }) {
            settings.activePromptVersionID = settings.promptVersions[0].id
        }
    }

    func activatePromptVersion(id: UUID) {
        guard settings.promptVersions.contains(where: { $0.id == id }) else {
            return
        }

        settings.activePromptVersionID = id
    }

    func addModelVersion() -> UUID {
        let version = ModelVersion(
            name: "新模型",
            baseURL: "",
            apiKey: "",
            modelName: ""
        )
        settings.modelVersions.append(version)
        return version.id
    }

    func deleteModelVersion(id: UUID) {
        guard settings.modelVersions.count > 1 else {
            return
        }

        settings.modelVersions.removeAll { $0.id == id }
        if !settings.modelVersions.contains(where: { $0.id == settings.activeModelVersionID }) {
            settings.activeModelVersionID = settings.modelVersions[0].id
        }
    }

    func activateModelVersion(id: UUID) {
        guard settings.modelVersions.contains(where: { $0.id == id }) else {
            return
        }

        settings.activeModelVersionID = id
    }
}

enum TranslationStatus: Equatable {
    case ready
    case loading
    case translated
    case error(String)
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
            status: .loading,
            settings: .previewConfigured,
            persistsSettings: false
        )
    }

    static var errorPreview: AppState {
        AppState(
            originalText: "This text failed to translate.",
            translatedText: "",
            status: .error("请求失败：请检查 API Key、Base URL 或网络连接。"),
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
        let deepSeekModel = ModelVersion(
            name: "DeepSeek",
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
                deepSeekModel
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
