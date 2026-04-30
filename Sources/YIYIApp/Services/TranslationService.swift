import Foundation

struct TranslationResult: Sendable {
    let text: String
    let totalTokens: Int?
}

protocol TranslationServicing: Sendable {
    func translate(text: String, settings: AppSettings) async throws -> TranslationResult
    func testConnection(with model: ModelVersion, timeoutInterval: TimeInterval) async throws
}

struct TranslationService: TranslationServicing {
    private let client: OpenAITranslationClient

    init(client: OpenAITranslationClient = OpenAITranslationClient()) {
        self.client = client
    }

    func translate(text: String, settings: AppSettings) async throws -> TranslationResult {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw TranslationInputError.emptyText
        }

        let configuration = ModelService.configuration(from: settings)
        let prompt = PromptService.translationPrompt(for: trimmedText, settings: settings)
        return try await client.translate(
            model: configuration.activeModel,
            prompt: prompt,
            timeoutInterval: configuration.requestTimeoutInterval
        )
    }

    func testConnection(with model: ModelVersion, timeoutInterval: TimeInterval) async throws {
        try await client.testConnection(with: model, timeoutInterval: timeoutInterval)
    }
}
