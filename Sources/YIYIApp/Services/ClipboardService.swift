import AppKit

protocol ClipboardServicing: Sendable {
    @MainActor func copy(_ text: String)
}

struct ClipboardService: ClipboardServicing {
    @MainActor
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
