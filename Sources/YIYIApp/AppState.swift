import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var originalText = "Select text anywhere on macOS, press Option + D, and YIYI will translate it in place without breaking your reading flow."
    @Published var translatedText = "在 macOS 任意位置选中文本，按下 Option + D，易译会在不打断阅读流程的情况下就地完成翻译。"
    @Published var status: TranslationStatus = .ready
    @Published var settings = AppSettings.load() {
        didSet {
            settings.save()
        }
    }

    func beginTranslation() {
        status = .loading
        translatedText = ""
    }

    func captureSelectedText() async {
        beginTranslation()

        do {
            originalText = try await SelectedTextReader.readSelectedText()
            settings.sourceLanguage = "自动识别"
            settings.targetLanguage = TranslationLanguageDetector.defaultTargetLanguage(for: originalText)
            try await translateCurrentText()
        } catch {
            translatedText = ""
            status = .error(error.localizedDescription)
        }
    }

    func translateCurrentText() async throws {
        let text = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw SelectedTextReader.ReadError.emptySelection
        }

        status = .loading
        translatedText = try await DeepSeekTranslationClient(settings: settings).translate(text)
        status = .translated
    }

    func refreshTranslation() {
        status = .loading
        translatedText = ""

        Task { @MainActor in
            do {
                try await translateCurrentText()
            } catch {
                translatedText = ""
                status = .error(error.localizedDescription)
            }
        }
    }

    func showEmptySelectionHint() {
        status = .error("未检测到选中文本。请先在任意应用中选中文本，再按 \(settings.shortcutDisplay)。")
    }

    func addPromptVersion() -> UUID {
        let nextIndex = settings.promptVersions.count + 1
        let version = PromptVersion(
            name: "Prompt \(nextIndex)",
            content: """
            Translate the selected text into \(settings.targetLanguage).
            Return only the result.

            {{selectedText}}
            """
        )
        settings.promptVersions.append(version)
        settings.activePromptVersionID = version.id
        return version.id
    }

    func deletePromptVersion(id: UUID) {
        guard settings.promptVersions.count > 1 else {
            return
        }

        settings.promptVersions.removeAll { $0.id == id }
        if !settings.promptVersions.contains(where: { $0.id == settings.activePromptVersionID }) {
            settings.activePromptVersionID = settings.promptVersions[0].id
        }
    }

    func activatePromptVersion(id: UUID) {
        guard settings.promptVersions.contains(where: { $0.id == id }) else {
            return
        }

        settings.activePromptVersionID = id
    }
}

enum TranslationStatus: Equatable {
    case ready
    case loading
    case translated
    case error(String)
}
