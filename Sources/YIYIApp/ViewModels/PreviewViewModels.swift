import Foundation

#if DEBUG
extension TranslationPanelViewModel {
    static var translatedPreview: TranslationPanelViewModel {
        TranslationPanelViewModel(
            settingsState: AppSettingsState(settings: .previewConfigured, persistsSettings: false),
            originalText: "The menu bar translator should feel lightweight, fast, and stay out of the reader's way.",
            translatedText: "菜单栏翻译工具应该轻量、快速，并且不打断读者的阅读流程。",
            totalTokens: 42,
            status: .translated
        )
    }

    static var loadingPreview: TranslationPanelViewModel {
        TranslationPanelViewModel(
            settingsState: AppSettingsState(settings: .previewConfigured, persistsSettings: false),
            originalText: "Preview the loading state without making a network request.",
            translatedText: "",
            status: .loading("正在等待结果……")
        )
    }

    static var errorPreview: TranslationPanelViewModel {
        TranslationPanelViewModel(
            settingsState: AppSettingsState(settings: .previewConfigured, persistsSettings: false),
            originalText: "This text failed to translate.",
            translatedText: "",
            status: .error("翻译失败，请检查模型设置或网络连接。")
        )
    }
}

extension SettingsViewModel {
    static var settingsPreview: SettingsViewModel {
        SettingsViewModel(
            settingsState: AppSettingsState(settings: .previewConfigured, persistsSettings: false)
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
