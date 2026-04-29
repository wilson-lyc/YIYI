import Foundation

@MainActor
final class TranslationController {
    private let client: OpenAITranslationClient
    private var activeTranslationTask: Task<Void, Never>?
    private var activeTranslationTaskID: UUID?

    init(client: OpenAITranslationClient = OpenAITranslationClient()) {
        self.client = client
    }

    func cancelActiveTranslation() {
        activeTranslationTask?.cancel()
        activeTranslationTask = nil
        activeTranslationTaskID = nil
    }

    func translateCurrentText(in state: AppState) async throws {
        let text = state.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw SelectedTextReader.ReadError.emptySelection
        }

        state.status = .loading("翻译中……")
        let progressTask = showTranslationProgressMessages(in: state)
        defer {
            progressTask.cancel()
        }

        let settings = state.settings
        let configuration = LLMServiceManager.configuration(from: settings)
        let prompt = PromptManager.translationPrompt(for: text, settings: settings)

        do {
            let translation = try await client.translate(
                model: configuration.activeModel,
                prompt: prompt,
                timeoutInterval: configuration.requestTimeoutInterval
            )
            try Task.checkCancellation()
            state.translatedText = translation
            state.status = .translated
        } catch {
            if let translationError = error as? TranslationError, translationError.isTimeout {
                state.showToast(error.localizedDescription)
            }
            throw error
        }
    }

    func startTranslation(in state: AppState, statusMessage: String) {
        activeTranslationTask?.cancel()
        let taskID = UUID()
        activeTranslationTaskID = taskID
        state.status = .loading(statusMessage)
        state.translatedText = ""

        activeTranslationTask = Task { @MainActor in
            defer {
                if activeTranslationTaskID == taskID {
                    activeTranslationTask = nil
                    activeTranslationTaskID = nil
                }
            }

            do {
                try await translateCurrentText(in: state)
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                state.translatedText = ""
                state.status = .error(error.localizedDescription)
            }
        }
    }

    private func showTranslationProgressMessages(in state: AppState) -> Task<Void, Never> {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, state.status.isLoading else {
                return
            }
            state.status = .loading("正在等待结果……")

            try? await Task.sleep(for: .seconds(13))
            guard !Task.isCancelled, state.status.isLoading else {
                return
            }
            state.status = .loading("还在翻译，请稍候……")
        }
    }
}
