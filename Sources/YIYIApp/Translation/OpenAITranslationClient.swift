import Foundation

struct OpenAITranslationClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func translate(model: ModelVersion, prompt: TranslationPrompt, timeoutInterval: TimeInterval) async throws -> String {
        let apiKey = model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw TranslationError.missingAPIKey
        }

        var request = URLRequest(url: try chatCompletionsURL(for: model))
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try requestBodyData(
            for: model,
            messages: [
                .init(role: "system", content: prompt.system),
                .init(role: "user", content: prompt.user)
            ],
            temperature: 0.2
        )

        let (data, response) = try await send(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw TranslationError.apiError(statusCode: httpResponse.statusCode, message: decodeAPIError(from: data))
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let translation = completion.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !translation.isEmpty
        else {
            throw TranslationError.emptyResult
        }

        return translation
    }

    func testConnection(with model: ModelVersion, timeoutInterval: TimeInterval) async throws {
        let apiKey = model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw TranslationError.missingAPIKey
        }

        var request = URLRequest(url: try chatCompletionsURL(for: model))
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try requestBodyData(
            for: model,
            messages: [
                .init(role: "user", content: "hello")
            ],
            temperature: 0
        )

        let (data, response) = try await send(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw TranslationError.apiError(statusCode: httpResponse.statusCode, message: decodeAPIError(from: data))
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard completion.choices.first?.message.content != nil else {
            throw TranslationError.emptyResult
        }
    }

    private func chatCompletionsURL(for model: ModelVersion) throws -> URL {
        let trimmedBaseURL = model.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmedBaseURL), components.scheme != nil, components.host != nil else {
            throw TranslationError.invalidBaseURL
        }

        let pathComponents = components.path
            .split(separator: "/")
            .map(String.init)

        if pathComponents.suffix(2) != ["chat", "completions"] {
            components.path = "/" + (pathComponents + ["chat", "completions"]).joined(separator: "/")
        }

        guard let url = components.url else {
            throw TranslationError.invalidBaseURL
        }

        return url
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw TranslationError.network(error)
        }
    }

    private func requestBodyData(for model: ModelVersion, messages: [ChatMessage], temperature: Double) throws -> Data {
        let modelName = model.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else {
            throw TranslationError.missingModelName
        }

        let request = ChatCompletionRequest(
            model: modelName,
            messages: messages,
            stream: false,
            temperature: temperature
        )

        let baseData = try JSONEncoder().encode(request)
        guard var body = try JSONSerialization.jsonObject(with: baseData) as? [String: Any] else {
            throw TranslationError.invalidResponse
        }

        mergeProviderDefaults(for: model, into: &body)
        try mergeExtraBodyJSON(from: model, into: &body)
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func mergeProviderDefaults(for model: ModelVersion, into body: inout [String: Any]) {
        guard usesProviderManagedReasoningAPI(model) else {
            return
        }

        body["thinking"] = ["type": "disabled"]
    }

    private func usesProviderManagedReasoningAPI(_ model: ModelVersion) -> Bool {
        let modelName = model.modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard modelName == "deepseek-v4-flash" || modelName == "deepseek-v4-pro" else {
            return false
        }

        guard
            let components = URLComponents(string: model.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
            let host = components.host?.lowercased()
        else {
            return false
        }

        return host == "api.deepseek.com" || host.hasSuffix(".api.deepseek.com")
    }

    private func mergeExtraBodyJSON(from model: ModelVersion, into body: inout [String: Any]) throws {
        let json = model.extraBodyJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !json.isEmpty else {
            return
        }

        guard let data = json.data(using: .utf8) else {
            throw TranslationError.invalidExtraBodyJSON
        }

        guard let extraBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationError.invalidExtraBodyJSON
        }

        for (key, value) in extraBody {
            body[key] = value
        }
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
    case missingModelName
    case invalidBaseURL
    case invalidResponse
    case invalidExtraBodyJSON
    case emptyResult
    case network(URLError)
    case apiError(statusCode: Int, message: String?)

    var isTimeout: Bool {
        if case let .network(error) = self, error.code == .timedOut {
            return true
        }

        return false
    }

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "翻译失败，请先配置 API Key。"
        case .missingModelName:
            return "翻译失败，请先配置模型名称。"
        case .invalidBaseURL:
            return "翻译失败，服务地址无效。"
        case .invalidResponse:
            return "服务异常，返回内容无法识别。"
        case .invalidExtraBodyJSON:
            return "翻译失败，请检查请求 JSON 格式。"
        case .emptyResult:
            return "翻译失败，服务没有返回译文。"
        case let .network(error):
            return Self.networkErrorDescription(for: error)
        case let .apiError(statusCode, message):
            if let message, !message.isEmpty {
                return "服务异常（HTTP \(statusCode)）：\(message)"
            }

            return "服务异常（HTTP \(statusCode)）。"
        }
    }

    private static func networkErrorDescription(for error: URLError) -> String {
        switch error.code {
        case .timedOut:
            return "翻译超时，暂时没有收到结果。"
        case .notConnectedToInternet:
            return "翻译失败，当前没有网络连接。"
        case .cannotFindHost, .dnsLookupFailed:
            return "翻译失败，服务地址无法访问。"
        case .cannotConnectToHost:
            return "服务异常，暂时无法连接。"
        case .networkConnectionLost:
            return "翻译中断，网络连接已断开。"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            return "服务异常，安全连接失败。"
        default:
            return "翻译失败：\(error.localizedDescription)"
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
    let content: String?

    init(role: String, content: String) {
        self.role = role
        self.content = content
    }
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
