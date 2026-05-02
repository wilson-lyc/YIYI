import Foundation

protocol AppSettingsRepository: Sendable {
    func load() -> AppSettings?
    func save(_ settings: AppSettings)
}

struct DefaultAppSettingsRepository: AppSettingsRepository {
    func load() -> AppSettings? {
        AppSettingsStore.load()
    }

    func save(_ settings: AppSettings) {
        AppSettingsStore.save(settings.normalized())
    }
}

extension AppSettingsRepository {
    func loadSettings() -> AppSettings {
        if let storedSettings = load() {
            let settings = storedSettings.normalized()
            save(settings)
            return settings
        }

        if let legacySettings = LegacyUserDefaultsSettingsStore.load() {
            let settings = legacySettings.normalized()
            save(settings)
            return settings
        }

        guard let config = AppConfigFile.load() else {
            let settings = AppSettings()
            save(settings)
            return settings
        }

        let model = ModelVersion(
            name: "默认模型",
            baseURL: config.baseURL ?? ModelVersion.defaultDeepSeek.baseURL,
            apiKey: config.apiKey ?? "",
            modelName: config.model ?? ModelVersion.defaultDeepSeek.modelName,
            extraBodyJSON: ModelVersion.defaultDeepSeek.extraBodyJSON
        )
        let settings = AppSettings(
            sourceLanguage: config.sourceLanguage ?? "自动识别",
            targetLanguage: config.targetLanguage ?? "简体中文",
            modelVersions: [model],
            activeModelVersionID: model.id
        ).normalized()
        save(settings)
        return settings
    }
}

private enum LegacyUserDefaultsSettingsStore {
    private static let userDefaultsKey = "YIYI.AppSettings"

    static func load() -> AppSettings? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return nil
        }

        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }
}

enum AppSettingsStore {
    private static let directoryName = ".yiyi"
    private static let configFileName = "config.toml"
    private static let promptsDirectoryName = "prompts"

    static func load() -> AppSettings? {
        let configURL = configURL
        guard
            FileManager.default.fileExists(atPath: configURL.path),
            let content = try? String(contentsOf: configURL, encoding: .utf8)
        else {
            return nil
        }

        let document = SimpleTOMLDocument(content)
        let models = loadModels(from: document)
        let prompts = loadPrompts()
        let activeModelID = UUID(uuidString: document.string("models", "active_id") ?? "")
            ?? models.first?.id
            ?? ModelVersion.defaultOpenAI.id
        let activePromptID = UUID(uuidString: document.string("prompts", "active_id") ?? "")
            ?? prompts.first?.id
            ?? PromptVersion.defaultTranslation.id

        return AppSettings(
            sourceLanguage: document.string("translation", "source_language") ?? "自动识别",
            targetLanguage: document.string("translation", "target_language") ?? "简体中文",
            shortcutDisplay: document.string(nil, "shortcut") ?? "⌥D",
            shortcutKeyCode: UInt32(document.int(nil, "shortcut_key_code") ?? Int(AppShortcut.defaultTranslation.keyCode)),
            shortcutModifiers: UInt32(document.int(nil, "shortcut_modifiers") ?? Int(AppShortcut.defaultTranslation.modifiers)),
            appearancePreference: AppearancePreference(rawValue: document.string(nil, "appearance") ?? "") ?? .system,
            launchAtLogin: document.bool(nil, "launch_at_login") ?? false,
            requestTimeoutSeconds: document.int(nil, "request_timeout_seconds") ?? AppSettings.defaultRequestTimeoutSeconds,
            translationPanelWidth: document.int("window", "translation_panel_width") ?? AppSettings.defaultTranslationPanelWidth,
            translationPanelHeight: document.int("window", "translation_panel_height") ?? AppSettings.defaultTranslationPanelHeight,
            modelVersions: models.isEmpty ? [.defaultDeepSeek] : models,
            activeModelVersionID: activeModelID,
            promptVersions: prompts.isEmpty ? [.defaultTranslation] : prompts,
            activePromptVersionID: activePromptID
        )
    }

    static func save(_ settings: AppSettings) {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: appDirectoryURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: promptsDirectoryURL, withIntermediateDirectories: true)
            try configTOML(for: settings).write(to: configURL, atomically: true, encoding: .utf8)
            try savePrompts(settings.promptVersions)
        } catch {
            NSLog("YIYI failed to save settings: \(error.localizedDescription)")
        }
    }

    private static func loadModels(from document: SimpleTOMLDocument) -> [ModelVersion] {
        let models = document.sections(prefix: "models.")
            .compactMap { section -> ModelVersion? in
                let fileID = String(section.dropFirst("models.".count))
                guard
                    let id = UUID(uuidString: document.string(section, "id") ?? fileID),
                    let name = document.string(section, "name"),
                    let baseURL = document.string(section, "base_url"),
                    let modelName = document.string(section, "model")
                else {
                    return nil
                }

                return ModelVersion(
                    id: id,
                    name: name,
                    baseURL: baseURL,
                    apiKey: document.string(section, "api_key") ?? "",
                    modelName: modelName,
                    extraBodyJSON: document.string(section, "extra_body_json") ?? ""
                )
            }

        if !models.isEmpty {
            return models
        }

        guard
            let baseURL = document.string("llm", "base_url"),
            let modelName = document.string("llm", "model")
        else {
            return []
        }

        return [
            ModelVersion(
                name: "默认模型",
                baseURL: baseURL,
                apiKey: document.string("llm", "api_key") ?? "",
                modelName: modelName,
                extraBodyJSON: document.string("llm", "extra_body_json") ?? ""
            )
        ]
    }

    private static func loadPrompts() -> [PromptVersion] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: promptsDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension == "toml" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate < rhsDate
            }
            .compactMap(loadPrompt)
    }

    private static func loadPrompt(from url: URL) -> PromptVersion? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        let document = SimpleTOMLDocument(content)
        let fileID = url.deletingPathExtension().lastPathComponent
        guard
            let id = UUID(uuidString: document.string(nil, "id") ?? fileID),
            let name = document.string(nil, "name")
        else {
            return nil
        }

        return PromptVersion(
            id: id,
            name: name,
            systemPrompt: document.string(nil, "system_prompt") ?? PromptVersion.defaultSystemPrompt,
            prompt: document.string(nil, "prompt") ?? document.string(nil, "content") ?? PromptVersion.defaultPrompt
        )
    }

    private static func savePrompts(_ prompts: [PromptVersion]) throws {
        let fileManager = FileManager.default
        let expectedFileNames = Set(prompts.map { promptFileName(for: $0.id) })

        if let existingURLs = try? fileManager.contentsOfDirectory(
            at: promptsDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for url in existingURLs where url.pathExtension == "toml" && !expectedFileNames.contains(url.lastPathComponent) {
                try? fileManager.removeItem(at: url)
            }
        }

        for prompt in prompts {
            try promptTOML(for: prompt).write(
                to: promptsDirectoryURL.appendingPathComponent(promptFileName(for: prompt.id)),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private static func configTOML(for settings: AppSettings) -> String {
        var lines = [
            "appearance = \(tomlString(settings.appearancePreference.rawValue))",
            "shortcut = \(tomlString(settings.shortcutDisplay))",
            "shortcut_key_code = \(settings.shortcutKeyCode)",
            "shortcut_modifiers = \(settings.shortcutModifiers)",
            "launch_at_login = \(settings.launchAtLogin ? "true" : "false")",
            "request_timeout_seconds = \(settings.requestTimeoutSeconds)",
            "",
            "[window]",
            "translation_panel_width = \(settings.translationPanelWidth)",
            "translation_panel_height = \(settings.translationPanelHeight)",
            "",
            "[translation]",
            "source_language = \(tomlString(settings.sourceLanguage))",
            "target_language = \(tomlString(settings.targetLanguage))",
        ]

        if !settings.modelVersions.isEmpty {
            lines.append("")
            lines.append("[models]")
            lines.append("active_id = \(tomlString(settings.activeModelVersionID.uuidString))")

            for model in settings.modelVersions {
                lines.append("")
                lines.append("[models.\(model.id.uuidString)]")
                lines.append("id = \(tomlString(model.id.uuidString))")
                lines.append("name = \(tomlString(model.name))")
                lines.append("protocol = \(tomlString("openai"))")
                lines.append("base_url = \(tomlString(model.baseURL))")
                lines.append("api_key = \(tomlString(model.apiKey))")
                lines.append("model = \(tomlString(model.modelName))")
                lines.append("extra_body_json = \(tomlString(model.extraBodyJSON))")
            }
        }

        lines.append("")
        lines.append("[prompts]")
        lines.append("active_id = \(tomlString(settings.activePromptVersionID.uuidString))")
        return lines.joined(separator: "\n")
    }

    private static func promptTOML(for prompt: PromptVersion) -> String {
        """
        id = \(tomlString(prompt.id.uuidString))
        name = \(tomlString(prompt.name))
        system_prompt = \(tomlString(prompt.systemPrompt))
        prompt = \(tomlString(prompt.prompt))
        """
    }

    private static func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private static func promptFileName(for id: UUID) -> String {
        "\(id.uuidString).toml"
    }

    private static var appDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static var configURL: URL {
        appDirectoryURL.appendingPathComponent(configFileName)
    }

    private static var promptsDirectoryURL: URL {
        appDirectoryURL.appendingPathComponent(promptsDirectoryName, isDirectory: true)
    }
}

private struct SimpleTOMLDocument {
    private var values: [String: [String: String]] = [:]

    init(_ content: String) {
        parse(content)
    }

    func string(_ section: String?, _ key: String) -> String? {
        values[sectionName(section)]?[key]
    }

    func bool(_ section: String?, _ key: String) -> Bool? {
        guard let value = string(section, key)?.lowercased() else {
            return nil
        }

        switch value {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    func int(_ section: String?, _ key: String) -> Int? {
        guard let value = string(section, key) else {
            return nil
        }

        return Int(value)
    }

    func sections(prefix: String) -> [String] {
        values.keys
            .filter { $0.hasPrefix(prefix) }
            .sorted()
    }

    private mutating func parse(_ content: String) {
        var currentSection = Self.rootSection

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else {
                continue
            }

            if line.hasPrefix("["), line.hasSuffix("]") {
                currentSection = String(line.dropFirst().dropLast())
                continue
            }

            guard let separatorIndex = line.firstIndex(of: "=") else {
                continue
            }

            let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            values[currentSection, default: [:]][key] = Self.parseValue(rawValue)
        }
    }

    private static func parseValue(_ rawValue: String) -> String {
        guard rawValue.hasPrefix("\""), rawValue.hasSuffix("\""), rawValue.count >= 2 else {
            return rawValue
        }

        let quoted = rawValue.dropFirst().dropLast()
        var result = ""
        var isEscaping = false

        for character in quoted {
            if isEscaping {
                switch character {
                case "n":
                    result.append("\n")
                case "r":
                    result.append("\r")
                case "t":
                    result.append("\t")
                case "\"":
                    result.append("\"")
                case "\\":
                    result.append("\\")
                default:
                    result.append(character)
                }
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else {
                result.append(character)
            }
        }

        if isEscaping {
            result.append("\\")
        }

        return result
    }

    private func sectionName(_ section: String?) -> String {
        section ?? Self.rootSection
    }

    private static let rootSection = "__root__"
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
