import Foundation

struct AppShortcut: Codable, Equatable, Sendable {
    static let defaultTranslation = AppShortcut(keyCode: 2, modifiers: 2048, display: "⌥D")

    var keyCode: UInt32
    var modifiers: UInt32
    var display: String
}

struct AppSettings: Decodable, Equatable, Sendable {
    static let defaultRequestTimeoutSeconds = 45
    static let requestTimeoutRange = 5...300

    var sourceLanguage = "自动识别"
    var targetLanguage = "简体中文"
    var shortcutDisplay = "⌥D"
    var shortcutKeyCode = AppShortcut.defaultTranslation.keyCode
    var shortcutModifiers = AppShortcut.defaultTranslation.modifiers
    var appearancePreference = AppearancePreference.system
    var launchAtLogin = false
    var requestTimeoutSeconds = Self.defaultRequestTimeoutSeconds
    var modelVersions = [ModelVersion.defaultOpenAI]
    var activeModelVersionID = ModelVersion.defaultOpenAI.id
    var promptVersions = [PromptVersion.defaultTranslation]
    var activePromptVersionID = PromptVersion.defaultTranslation.id

    init(
        sourceLanguage: String = "自动识别",
        targetLanguage: String = "简体中文",
        shortcutDisplay: String = "⌥D",
        shortcutKeyCode: UInt32 = AppShortcut.defaultTranslation.keyCode,
        shortcutModifiers: UInt32 = AppShortcut.defaultTranslation.modifiers,
        appearancePreference: AppearancePreference = .system,
        launchAtLogin: Bool = false,
        requestTimeoutSeconds: Int = AppSettings.defaultRequestTimeoutSeconds,
        modelVersions: [ModelVersion] = [ModelVersion.defaultOpenAI],
        activeModelVersionID: UUID = ModelVersion.defaultOpenAI.id,
        promptVersions: [PromptVersion] = [PromptVersion.defaultTranslation],
        activePromptVersionID: UUID = PromptVersion.defaultTranslation.id
    ) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.shortcutDisplay = shortcutDisplay
        self.shortcutKeyCode = shortcutKeyCode
        self.shortcutModifiers = shortcutModifiers
        self.appearancePreference = appearancePreference
        self.launchAtLogin = launchAtLogin
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.modelVersions = modelVersions
        self.activeModelVersionID = activeModelVersionID
        self.promptVersions = promptVersions
        self.activePromptVersionID = activePromptVersionID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceLanguage = try container.decodeIfPresent(String.self, forKey: .sourceLanguage) ?? "自动识别"
        targetLanguage = try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "简体中文"
        shortcutDisplay = try container.decodeIfPresent(String.self, forKey: .shortcutDisplay) ?? "⌥D"
        shortcutKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .shortcutKeyCode) ?? AppShortcut.defaultTranslation.keyCode
        shortcutModifiers = try container.decodeIfPresent(UInt32.self, forKey: .shortcutModifiers) ?? AppShortcut.defaultTranslation.modifiers
        appearancePreference = try container.decodeIfPresent(AppearancePreference.self, forKey: .appearancePreference) ?? .system
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        requestTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .requestTimeoutSeconds) ?? Self.defaultRequestTimeoutSeconds
        modelVersions = try container.decodeIfPresent([ModelVersion].self, forKey: .modelVersions) ?? []
        activeModelVersionID = try container.decodeIfPresent(UUID.self, forKey: .activeModelVersionID) ?? ModelVersion.defaultOpenAI.id
        promptVersions = try container.decodeIfPresent([PromptVersion].self, forKey: .promptVersions) ?? [.defaultTranslation]
        activePromptVersionID = try container.decodeIfPresent(UUID.self, forKey: .activePromptVersionID) ?? PromptVersion.defaultTranslation.id

        if modelVersions.isEmpty {
            let legacyModel = ModelVersion(
                name: "默认模型",
                baseURL: try container.decodeIfPresent(String.self, forKey: .baseURL) ?? "https://api.openai.com/v1",
                apiKey: try container.decodeIfPresent(String.self, forKey: .apiKey) ?? "",
                modelName: try container.decodeIfPresent(String.self, forKey: .model) ?? "gpt-4o-mini"
            )
            modelVersions = [legacyModel]
            activeModelVersionID = legacyModel.id
        }
    }

    func normalized() -> AppSettings {
        var settings = self
        if settings.modelVersions.isEmpty {
            settings.modelVersions = [.defaultOpenAI]
        }

        if !settings.modelVersions.contains(where: { $0.id == settings.activeModelVersionID }) {
            settings.activeModelVersionID = settings.modelVersions[0].id
        }

        if settings.promptVersions.isEmpty {
            settings.promptVersions = [.defaultTranslation]
        }

        if !settings.promptVersions.contains(where: { $0.id == settings.activePromptVersionID }) {
            settings.activePromptVersionID = settings.promptVersions[0].id
        }

        settings.requestTimeoutSeconds = Self.clampedRequestTimeoutSeconds(settings.requestTimeoutSeconds)
        if settings.shortcutDisplay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.shortcutDisplay = AppShortcut.defaultTranslation.display
        }

        if settings.shortcutKeyCode == 0 || settings.shortcutModifiers == 0 {
            settings.shortcutKeyCode = AppShortcut.defaultTranslation.keyCode
            settings.shortcutModifiers = AppShortcut.defaultTranslation.modifiers
            settings.shortcutDisplay = AppShortcut.defaultTranslation.display
        }

        return settings
    }

    static func clampedRequestTimeoutSeconds(_ seconds: Int) -> Int {
        min(max(seconds, requestTimeoutRange.lowerBound), requestTimeoutRange.upperBound)
    }

    private enum CodingKeys: String, CodingKey {
        case baseURL
        case apiKey
        case model
        case sourceLanguage
        case targetLanguage
        case shortcutDisplay
        case shortcutKeyCode
        case shortcutModifiers
        case appearancePreference
        case launchAtLogin
        case requestTimeoutSeconds
        case modelVersions
        case activeModelVersionID
        case promptVersions
        case activePromptVersionID
    }
}

extension AppSettings {
    var globalHotKeyShortcut: AppShortcut {
        AppShortcut(
            keyCode: shortcutKeyCode,
            modifiers: shortcutModifiers,
            display: shortcutDisplay
        )
    }
}

enum AppearancePreference: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system:
            return "自动"
        case .light:
            return "日间"
        case .dark:
            return "夜间"
        }
    }
}
