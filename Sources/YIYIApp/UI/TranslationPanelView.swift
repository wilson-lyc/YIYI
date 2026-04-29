import SwiftUI
import AppKit

struct TranslationPanelView: View {
    @ObservedObject var appState: AppState
    @State private var showsCopiedMessage = false
    @State private var isRefreshing = false
    @State private var refreshRotation = 0.0
    @State private var loadingPulse = false

    let onRefreshTranslation: () -> Void

    private let translationHeight: CGFloat = 140
    private var tokenCount: Int {
        TokenEstimator.estimate(appState.originalText) + TokenEstimator.estimate(appState.translatedText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerBar
            translationBody
            actionBar
        }
        .font(.system(size: 17))
        .padding(12)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .overlay(alignment: .bottom) {
            if let toast = appState.toast {
                toastView(toast.message)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 36)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: appState.status) { _, status in
            handleRefreshStatusChange(status)
        }
        .onChange(of: appState.toast) { _, toast in
            guard let toast else {
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    appState.dismissToast(id: toast.id)
                }
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            languagePicker(selection: $appState.settings.sourceLanguage, options: SupportedLanguages.source)
                .frame(width: 128)
            Image(systemName: "arrow.right")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            languagePicker(selection: $appState.settings.targetLanguage, options: SupportedLanguages.target)
                .frame(width: 128)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var translationBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if case let .error(message) = appState.status {
                    Text(message)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.orange)
                } else if case let .loading(message) = appState.status {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 5) {
                            loadingBar(width: 210)
                            loadingBar(width: 285)
                            loadingBar(width: 170)
                        }
                    }
                    .padding(.top, 3)
                    .opacity(loadingPulse ? 0.42 : 1)
                    .animation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true), value: loadingPulse)
                    .onAppear {
                        loadingPulse = true
                    }
                    .onDisappear {
                        loadingPulse = false
                    }
                } else {
                    Text(appState.translatedText.isEmpty ? "译文会显示在这里" : appState.translatedText)
                        .font(.system(size: 15))
                        .lineSpacing(2)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(6)
        }
        .frame(height: translationHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var actionBar: some View {
        HStack(spacing: 4) {
            IconActionButton(systemName: showsCopiedMessage ? "checkmark" : "doc.on.doc", action: copyTranslation)
            .help("复制")
            .disabled(appState.translatedText.isEmpty || appState.status.isLoading)

            IconActionButton(
                systemName: refreshIconName,
                rotationDegrees: refreshRotation,
                action: refreshTranslation
            )
            .help("刷新")

            Spacer(minLength: 0)

            Text("\(tokenCount) tokens")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func languagePicker(selection: Binding<String>, options: [String]) -> some View {
        Picker("", selection: selection) {
            ForEach(options, id: \.self) { language in
                Text(language)
                    .tag(language)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .font(.system(size: 17))
        .controlSize(.regular)
    }

    private func loadingBar(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(.secondary.opacity(0.18))
            .frame(width: width, height: 10)
    }

    private func toastView(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    private func copyTranslation() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.translatedText, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) {
            showsCopiedMessage = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.15)) {
                showsCopiedMessage = false
            }
        }
    }

    private func refreshTranslation() {
        isRefreshing = true
        withAnimation(.easeInOut(duration: 0.45)) {
            refreshRotation += 360
        }
        onRefreshTranslation()
    }

    private var refreshIconName: String {
        if isRefreshing {
            return "progress.indicator"
        }

        return "arrow.clockwise"
    }

    private func handleRefreshStatusChange(_ status: TranslationStatus) {
        guard isRefreshing else {
            return
        }

        switch status {
        case .translated:
            isRefreshing = false
        case .error:
            isRefreshing = false
        case .ready, .loading:
            break
        }
    }
}

private struct IconActionButton: View {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let systemName: String
    var rotationDegrees = 0.0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .rotationEffect(.degrees(rotationDegrees))
                .frame(width: 24, height: 24)
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.45))
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovered && isEnabled ? Color(nsColor: .separatorColor).opacity(0.55) : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

#if DEBUG
#Preview("翻译窗口 - 已翻译") {
    TranslationPanelView(
        appState: .translatedPreview,
        onRefreshTranslation: {}
    )
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("翻译窗口 - 加载中") {
    TranslationPanelView(
        appState: .loadingPreview,
        onRefreshTranslation: {}
    )
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("翻译窗口 - 错误") {
    TranslationPanelView(
        appState: .errorPreview,
        onRefreshTranslation: {}
    )
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}
#endif
