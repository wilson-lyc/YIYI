import Foundation

struct ModelVersion: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var baseURL: String
    var apiKey: String
    var modelName: String
    var extraBodyJSON: String

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        apiKey: String,
        modelName: String,
        extraBodyJSON: String = ""
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelName = modelName
        self.extraBodyJSON = extraBodyJSON
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "默认模型"
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName) ?? ""
        extraBodyJSON = try container.decodeIfPresent(String.self, forKey: .extraBodyJSON) ?? ""
    }
}

extension ModelVersion {
    static let defaultOpenAI = ModelVersion(
        id: UUID(uuidString: "D7F24194-8D7A-432B-9B59-5691491D1B5D")!,
        name: "默认模型",
        baseURL: "https://api.openai.com/v1",
        apiKey: "",
        modelName: "gpt-4o-mini"
    )
}
