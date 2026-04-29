import Foundation

struct PromptVersion: Identifiable, Decodable, Equatable {
    var id = UUID()
    var name: String
    var systemPrompt: String
    var prompt: String

    init(id: UUID = UUID(), name: String, systemPrompt: String, prompt: String) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.prompt = prompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "默认提示词"
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? Self.defaultSystemPrompt
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
            ?? container.decodeIfPresent(String.self, forKey: .content)
            ?? Self.defaultPrompt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case systemPrompt
        case prompt
        case content
    }
}

struct TranslationPrompt {
    let system: String
    let user: String
}

enum PromptManager {
    static func activePrompt(in settings: AppSettings) -> PromptVersion {
        settings.promptVersions.first { $0.id == settings.activePromptVersionID } ?? .defaultTranslation
    }

    static func translationPrompt(for selectedText: String, settings: AppSettings) -> TranslationPrompt {
        TranslationPrompt(
            system: renderedSystemPrompt(settings: settings),
            user: renderedUserPrompt(for: selectedText, settings: settings)
        )
    }

    static func addPromptVersion(to settings: inout AppSettings) -> UUID {
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

    static func deletePromptVersion(id: UUID, from settings: inout AppSettings) {
        guard settings.promptVersions.count > 1 else {
            return
        }

        settings.promptVersions.removeAll { $0.id == id }
        if !settings.promptVersions.contains(where: { $0.id == settings.activePromptVersionID }) {
            settings.activePromptVersionID = settings.promptVersions[0].id
        }
    }

    static func activatePromptVersion(id: UUID, in settings: inout AppSettings) {
        guard settings.promptVersions.contains(where: { $0.id == id }) else {
            return
        }

        settings.activePromptVersionID = id
    }

    private static func renderedUserPrompt(for selectedText: String, settings: AppSettings) -> String {
        let template = activePrompt(in: settings).prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = renderTemplate(template, selectedText: selectedText, settings: settings)
        guard !prompt.contains("{{selectedText}}") else {
            return prompt
        }

        if template.contains("{{selectedText}}") {
            return prompt
        }

        return "\(prompt)\n\n\(selectedText)"
    }

    private static func renderedSystemPrompt(settings: AppSettings) -> String {
        let template = activePrompt(in: settings).systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = renderTemplate(template, selectedText: "", settings: settings)
        let languageInstruction = """
        Source language setting: \(settings.sourceLanguage)
        Target language: \(settings.targetLanguage)
        """

        guard !prompt.isEmpty else {
            return languageInstruction
        }

        return "\(prompt)\n\(languageInstruction)"
    }

    private static func renderTemplate(_ template: String, selectedText: String, settings: AppSettings) -> String {
        template
            .replacingOccurrences(of: "{{selectedText}}", with: selectedText)
            .replacingOccurrences(of: "{{sourceLanguage}}", with: settings.sourceLanguage)
            .replacingOccurrences(of: "{{targetLanguage}}", with: settings.targetLanguage)
    }
}

extension AppSettings {
    var activePromptVersion: PromptVersion {
        PromptManager.activePrompt(in: self)
    }

    func renderedPrompt(for selectedText: String) -> String {
        PromptManager.translationPrompt(for: selectedText, settings: self).user
    }

    func renderedSystemPrompt() -> String {
        PromptManager.translationPrompt(for: "", settings: self).system
    }
}

extension AppState {
    func addPromptVersion() -> UUID {
        PromptManager.addPromptVersion(to: &settings)
    }

    func deletePromptVersion(id: UUID) {
        PromptManager.deletePromptVersion(id: id, from: &settings)
    }

    func activatePromptVersion(id: UUID) {
        PromptManager.activatePromptVersion(id: id, in: &settings)
    }
}

extension PromptVersion {
    static let defaultSystemPrompt = """
    You are a professional translation engine. Translate the selected text into {{targetLanguage}}.
    Return only the translated text. Preserve the original meaning, formatting, line breaks, technical terms, numbers, and URLs.
    Do not add explanations, quotes, markdown fences, or extra commentary.
    """

    static let defaultPrompt = """
    Source language setting: {{sourceLanguage}}
    Target language: {{targetLanguage}}

    {{selectedText}}
    """

    static let defaultTranslation = PromptVersion(
        id: UUID(uuidString: "8C6B9B59-0B38-47B9-9A55-8240E1F5B6D4")!,
        name: "默认提示词",
        systemPrompt: defaultSystemPrompt,
        prompt: defaultPrompt
    )
}
