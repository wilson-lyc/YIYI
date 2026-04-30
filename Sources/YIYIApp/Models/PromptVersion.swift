import Foundation

struct PromptVersion: Identifiable, Decodable, Equatable, Sendable {
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

struct TranslationPrompt: Sendable {
    let system: String
    let user: String
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
