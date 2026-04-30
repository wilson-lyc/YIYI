import Foundation

enum PromptService {
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
        PromptService.activePrompt(in: self)
    }

    func renderedPrompt(for selectedText: String) -> String {
        PromptService.translationPrompt(for: selectedText, settings: self).user
    }

    func renderedSystemPrompt() -> String {
        PromptService.translationPrompt(for: "", settings: self).system
    }
}
