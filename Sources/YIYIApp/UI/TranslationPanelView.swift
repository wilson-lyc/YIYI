import SwiftUI
import AppKit

struct TranslationPanelView: View {
    @ObservedObject var viewModel: TranslationPanelViewModel
    @State private var showsCopiedMessage = false
    @State private var isRefreshing = false
    @State private var loadingPulse = false

    let onRefreshTranslation: () -> Void

    private let translationHeight: CGFloat = 140
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerBar
            translationBody
            actionBar
        }
        .font(.body)
        .padding(12)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .overlay(alignment: .bottom) {
            if let toast = viewModel.toast {
                toastView(toast.message)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 36)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: viewModel.status) { _, status in
            handleRefreshStatusChange(status)
        }
        .onChange(of: viewModel.toast) { _, toast in
            guard let toast else {
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    viewModel.dismissToast(id: toast.id)
                }
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            languagePicker(selection: sourceLanguageSelection, options: SupportedLanguages.source)
                .frame(width: 128)
            Image(systemName: "arrow.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            languagePicker(selection: targetLanguageSelection, options: SupportedLanguages.target)
                .frame(width: 128)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var targetLanguageSelection: Binding<String> {
        Binding(
            get: { viewModel.settings.targetLanguage },
            set: { viewModel.updateTargetLanguage($0) }
        )
    }

    private var sourceLanguageSelection: Binding<String> {
        Binding(
            get: { viewModel.settings.sourceLanguage },
            set: { viewModel.updateSourceLanguage($0) }
        )
    }

    private var translationBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if case let .error(message) = viewModel.status {
                    Text(message)
                        .font(.body.weight(.medium))
                } else if case let .loading(message) = viewModel.status {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 5) {
                            loadingBar(width: 210)
                            loadingBar(width: 285)
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
                    Text(viewModel.translatedText.isEmpty ? "译文会显示在这里" : viewModel.translatedText)
                        .font(.body)
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
            .disabled(viewModel.translatedText.isEmpty || viewModel.status.isLoading)

            IconActionButton(
                systemName: "arrow.clockwise",
                action: refreshTranslation
            )
            .help("刷新")
            .disabled(viewModel.originalText.isEmpty || viewModel.status.isLoading)

            Spacer(minLength: 0)

            Text(viewModel.tokenCountText)
                .font(.body.weight(.medium))
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
        .font(.body)
        .controlSize(.regular)
    }

    private func loadingBar(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(.secondary.opacity(0.18))
            .frame(width: width, height: 10)
    }

    private func toastView(_ message: String) -> some View {
        Text(message)
            .font(.caption.weight(.medium))
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
        viewModel.copyTranslation()
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
        onRefreshTranslation()
    }

    private func handleRefreshStatusChange(_ status: TranslationStatus) {
        guard isRefreshing else {
            return
        }

        switch status {
        case .translated:
            stopRefreshing()
        case .error:
            stopRefreshing()
        case .ready, .loading:
            break
        }
    }

    private func stopRefreshing() {
        isRefreshing = false
    }
}

private struct IconActionButton: View {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.medium))
                .frame(width: 28, height: 28)
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
        viewModel: .translatedPreview,
        onRefreshTranslation: {}
    )
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("翻译窗口 - 加载中") {
    TranslationPanelView(
        viewModel: .loadingPreview,
        onRefreshTranslation: {}
    )
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("翻译窗口 - 错误") {
    TranslationPanelView(
        viewModel: .errorPreview,
        onRefreshTranslation: {}
    )
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}
#endif
