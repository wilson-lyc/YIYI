import Foundation

struct DeepSeekTranslationClient {
    private let settings: AppSettings
    private let session: URLSession

    init(settings: AppSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    func translate(_ text: String) async throws -> String {
        let model = settings.activeModelVersion
        let apiKey = model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw TranslationError.missingAPIKey
        }

        var request = URLRequest(url: try chatCompletionsURL(for: model))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody(for: text))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw TranslationError.apiError(statusCode: httpResponse.statusCode, message: decodeAPIError(from: data))
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let translation = completion.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !translation.isEmpty
        else {
            throw TranslationError.emptyResult
        }

        return translation
    }

    private func chatCompletionsURL(for model: ModelVersion) throws -> URL {
        let trimmedBaseURL = model.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmedBaseURL), components.scheme != nil, components.host != nil else {
            throw TranslationError.invalidBaseURL
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([basePath, "chat", "completions"]
            .filter { !$0.isEmpty }
            .joined(separator: "/"))

        guard let url = components.url else {
            throw TranslationError.invalidBaseURL
        }

        return url
    }

    private func requestBody(for text: String) -> ChatCompletionRequest {
        let model = settings.activeModelVersion

        return ChatCompletionRequest(
            model: model.modelName.trimmingCharacters(in: .whitespacesAndNewlines),
            messages: [
                .init(role: "system", content: settings.renderedSystemPrompt()),
                .init(role: "user", content: settings.renderedPrompt(for: text))
            ],
            stream: false,
            temperature: 0.2
        )
    }

    private func decodeAPIError(from data: Data) -> String? {
        if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
            return errorResponse.error.message
        }

        return String(data: data, encoding: .utf8)
    }
}

enum TranslationError: LocalizedError {
    case missingAPIKey
    case invalidBaseURL
    case invalidResponse
    case emptyResult
    case apiError(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先配置 API Key。"
        case .invalidBaseURL:
            return "Base URL 无效。"
        case .invalidResponse:
            return "模型服务返回了无效响应。"
        case .emptyResult:
            return "模型服务未返回译文。"
        case let .apiError(statusCode, message):
            if let message, !message.isEmpty {
                return "模型服务请求失败（HTTP \(statusCode)）：\(message)"
            }

            return "模型服务请求失败（HTTP \(statusCode)）。"
        }
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let temperature: Double
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessage
    }
}

private struct APIErrorResponse: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}
