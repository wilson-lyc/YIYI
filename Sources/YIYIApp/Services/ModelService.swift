import Foundation

struct ModelServiceConfiguration: Sendable {
    let activeModel: ModelVersion
    let requestTimeoutInterval: TimeInterval
}

enum ModelService {
    static func configuration(from settings: AppSettings) -> ModelServiceConfiguration {
        ModelServiceConfiguration(
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
        ModelService.activeModel(in: self)
    }

    var requestTimeoutInterval: TimeInterval {
        TimeInterval(Self.clampedRequestTimeoutSeconds(requestTimeoutSeconds))
    }
}
