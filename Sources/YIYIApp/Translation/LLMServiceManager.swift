import Foundation

struct ModelVersion: Identifiable, Codable, Equatable {
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

struct LLMServiceConfiguration {
    let activeModel: ModelVersion
    let requestTimeoutInterval: TimeInterval
}

enum LLMServiceManager {
    static func configuration(from settings: AppSettings) -> LLMServiceConfiguration {
        LLMServiceConfiguration(
            activeModel: activeModel(in: settings),
            requestTimeoutInterval: settings.requestTimeoutInterval
        )
    }

    static func activeModel(in settings: AppSettings) -> ModelVersion {
        settings.modelVersions.first { $0.id == settings.activeModelVersionID } ?? .defaultOpenAI
    }

    static func addModelVersion(to settings: inout AppSettings) -> UUID {
        let version = ModelVersion(
            name: "新模型",
            baseURL: "",
            apiKey: "",
            modelName: "",
            extraBodyJSON: ""
        )
        settings.modelVersions.append(version)
        return version.id
    }

    static func deleteModelVersion(id: UUID, from settings: inout AppSettings) {
        guard settings.modelVersions.count > 1 else {
            return
        }

        settings.modelVersions.removeAll { $0.id == id }
        if !settings.modelVersions.contains(where: { $0.id == settings.activeModelVersionID }) {
            settings.activeModelVersionID = settings.modelVersions[0].id
        }
    }

    static func activateModelVersion(id: UUID, in settings: inout AppSettings) {
        guard settings.modelVersions.contains(where: { $0.id == id }) else {
            return
        }

        settings.activeModelVersionID = id
    }
}

extension AppSettings {
    var activeModelVersion: ModelVersion {
        LLMServiceManager.activeModel(in: self)
    }

    var requestTimeoutInterval: TimeInterval {
        TimeInterval(Self.clampedRequestTimeoutSeconds(requestTimeoutSeconds))
    }
}

extension AppState {
    func addModelVersion() -> UUID {
        LLMServiceManager.addModelVersion(to: &settings)
    }

    func deleteModelVersion(id: UUID) {
        LLMServiceManager.deleteModelVersion(id: id, from: &settings)
    }

    func activateModelVersion(id: UUID) {
        LLMServiceManager.activateModelVersion(id: id, in: &settings)
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
