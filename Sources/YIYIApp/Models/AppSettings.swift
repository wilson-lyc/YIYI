import Foundation

struct PromptVersion: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var content: String
}

struct AppSettings: Codable, Equatable {
    var baseURL = "https://api.deepseek.com"
    var apiKey = ""
    var model = "deepseek-v4-flash"
    var sourceLanguage = "自动识别"
    var targetLanguage = "简体中文"
    var shortcutDisplay = "⌥D"
    var launchAtLogin = false
    var promptVersions = [PromptVersion.defaultTranslation]
    var activePromptVersionID = PromptVersion.defaultTranslation.id

    static func load() -> AppSettings {
        if let savedSettings = loadSavedSettings() {
            return savedSettings.normalized()
        }

        guard let config = AppConfigFile.load() else {
            return AppSettings()
        }

        return AppSettings(
            baseURL: config.baseURL ?? "https://api.deepseek.com",
            apiKey: config.apiKey ?? "",
            model: config.model ?? "deepseek-v4-flash",
            sourceLanguage: config.sourceLanguage ?? "自动识别",
            targetLanguage: config.targetLanguage ?? "简体中文"
        ).normalized()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(normalized()) else {
            return
        }

        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    var activePromptVersion: PromptVersion {
        normalized().promptVersions.first { $0.id == activePromptVersionID } ?? .defaultTranslation
    }

    func renderedPrompt(for selectedText: String) -> String {
        let template = activePromptVersion.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = template.replacingOccurrences(of: "{{selectedText}}", with: selectedText)
        guard !prompt.contains("{{selectedText}}") else {
            return prompt
        }

        if template.contains("{{selectedText}}") {
            return prompt
        }

        return "\(prompt)\n\n\(selectedText)"
    }

    private func normalized() -> AppSettings {
        var settings = self
        if settings.promptVersions.isEmpty {
            settings.promptVersions = [.defaultTranslation]
        }

        if !settings.promptVersions.contains(where: { $0.id == settings.activePromptVersionID }) {
            settings.activePromptVersionID = settings.promptVersions[0].id
        }

        return settings
    }

    private static let userDefaultsKey = "YIYI.AppSettings"

    private static func loadSavedSettings() -> AppSettings? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return nil
        }

        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }
}

extension PromptVersion {
    static let defaultTranslation = PromptVersion(
        id: UUID(uuidString: "8C6B9B59-0B38-47B9-9A55-8240E1F5B6D4")!,
        name: "默认翻译",
        content: """
        You are a professional translation engine. Translate the following selected text into the target language.
        Return only the translated text. Preserve the original meaning, formatting, line breaks, technical terms, numbers, and URLs.
        Do not add explanations, quotes, markdown fences, or extra commentary.

        Selected text:
        {{selectedText}}
        """
    )
}

private struct AppConfigFile: Decodable {
    let baseURL: String?
    let apiKey: String?
    let model: String?
    let sourceLanguage: String?
    let targetLanguage: String?

    static func load() -> AppConfigFile? {
        let fileManager = FileManager.default

        for directory in candidateDirectories() {
            let url = directory.appendingPathComponent(".yiyi.config.json")
            guard fileManager.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url)
            else {
                continue
            }

            return try? JSONDecoder().decode(AppConfigFile.self, from: data)
        }

        return nil
    }

    private static func candidateDirectories() -> [URL] {
        var directories = [URL]()
        var current = URL(fileURLWithPath: fileManagerCurrentDirectory())

        for _ in 0..<5 {
            directories.append(current)
            current.deleteLastPathComponent()
        }

        if let resourceURL = Bundle.main.resourceURL {
            directories.append(resourceURL)
        }

        return directories
    }

    private static func fileManagerCurrentDirectory() -> String {
        FileManager.default.currentDirectoryPath
    }
}
