import Foundation

enum TranslationStatus: Equatable, Sendable {
    case ready
    case loading(String)
    case translated
    case error(String)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }

        return false
    }
}

struct ToastMessage: Equatable, Identifiable, Sendable {
    let id = UUID()
    let message: String
}

enum TranslationInputError: LocalizedError {
    case emptyText

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "未检测到选中文本。请先在任意应用中选中文本，再按快捷键。"
        }
    }
}
