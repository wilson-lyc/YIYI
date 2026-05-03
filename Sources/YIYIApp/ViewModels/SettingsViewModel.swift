import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            guard !isApplyingExternalSettings else {
                return
            }

            settingsState.settings = settings
        }
    }
    @Published var selectedPage: SettingsPage = .general
    @Published var selectedModelID: UUID?
    @Published var selectedPromptID: UUID?
    @Published private(set) var modelConnectionTestState: ModelConnectionTestState = .idle

    private let settingsState: AppSettingsState
    private let translationService: TranslationServicing
    private var settingsCancellable: AnyCancellable?
    private var isApplyingExternalSettings = false

    init(
        settingsState: AppSettingsState,
        translationService: TranslationServicing = TranslationService()
    ) {
        self.settingsState = settingsState
        self.translationService = translationService
        self.settings = settingsState.settings

        settingsCancellable = settingsState.$settings
            .removeDuplicates()
            .sink { [weak self] settings in
                guard let self, self.settings != settings else {
                    return
                }

                self.isApplyingExternalSettings = true
                self.settings = settings
                self.isApplyingExternalSettings = false
        }
    }

    func prepareSelectionsIfNeeded() {
        selectedModelID = selectedModelID ?? settings.activeModelVersionID
        selectedPromptID = selectedPromptID ?? settings.activePromptVersionID
    }

    func updateShortcut(_ shortcut: AppShortcut) {
        settings.shortcutDisplay = shortcut.display
        settings.shortcutKeyCode = shortcut.keyCode
        settings.shortcutModifiers = shortcut.modifiers
    }

    func addModelVersion() -> UUID {
        let id = ModelService.addModelVersion(to: &settings)
        selectedModelID = id
        modelConnectionTestState = .idle
        return id
    }

    func deleteModelVersion(id: UUID) {
        ModelService.deleteModelVersion(id: id, from: &settings)
        selectedModelID = settings.activeModelVersionID
        modelConnectionTestState = .idle
    }

    func activateModelVersion(id: UUID) {
        ModelService.activateModelVersion(id: id, in: &settings)
    }

    func addPromptVersion() -> UUID {
        let id = PromptService.addPromptVersion(to: &settings)
        selectedPromptID = id
        return id
    }

    func deletePromptVersion(id: UUID) {
        PromptService.deletePromptVersion(id: id, from: &settings)
        selectedPromptID = settings.activePromptVersionID
    }

    func activatePromptVersion(id: UUID) {
        PromptService.activatePromptVersion(id: id, in: &settings)
    }

    func testModelConnection(with model: ModelVersion) async {
        modelConnectionTestState = .testing

        do {
            try await translationService.testConnection(
                with: model,
                timeoutInterval: settings.requestTimeoutInterval
            )
            if selectedModelID == model.id, currentModel(matches: model) {
                modelConnectionTestState = .success
            }
        } catch {
            if selectedModelID == model.id, currentModel(matches: model) {
                modelConnectionTestState = .failure(error.localizedDescription)
            }
        }
    }

    func resetModelConnectionTestState() {
        modelConnectionTestState = .idle
    }

    func currentModel(matches model: ModelVersion) -> Bool {
        settings.modelVersions.first { $0.id == model.id } == model
    }
}

enum ModelConnectionTestState: Equatable {
    case idle
    case testing
    case success
    case failure(String)

    var buttonTitle: String {
        switch self {
        case .idle:
            return "测试连接"
        case .testing:
            return "测试中..."
        case .success:
            return "测试成功"
        case .failure:
            return "测试失败"
        }
    }

    var isTesting: Bool {
        self == .testing
    }

    var canStartTest: Bool {
        switch self {
        case .idle, .failure:
            return true
        case .testing, .success:
            return false
        }
    }

    var failureMessage: String? {
        switch self {
        case let .failure(message):
            return message
        case .idle, .testing, .success:
            return nil
        }
    }
}

enum SettingsPage: CaseIterable, Identifiable {
    case general
    case models
    case prompts

    var id: Self { self }

    var title: String {
        switch self {
        case .general:
            return "常规"
        case .models:
            return "模型"
        case .prompts:
            return "用户提示词"
        }
    }

    var symbolName: String {
        switch self {
        case .general:
            return "gearshape"
        case .models:
            return "cpu"
        case .prompts:
            return "text.quote"
        }
    }
}
