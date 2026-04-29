import Foundation

enum TranslationStatus: Equatable {
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

struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let message: String
}
