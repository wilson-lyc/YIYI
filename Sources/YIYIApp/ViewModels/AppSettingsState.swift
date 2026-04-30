import Foundation

@MainActor
final class AppSettingsState: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            guard persistsSettings else {
                return
            }

            settingsRepository.save(settings)
        }
    }

    private let persistsSettings: Bool
    private let settingsRepository: AppSettingsRepository

    init(
        settings: AppSettings? = nil,
        persistsSettings: Bool = true,
        settingsRepository: AppSettingsRepository = DefaultAppSettingsRepository()
    ) {
        self.settingsRepository = settingsRepository
        self.settings = settings ?? settingsRepository.loadSettings()
        self.persistsSettings = persistsSettings
    }
}
