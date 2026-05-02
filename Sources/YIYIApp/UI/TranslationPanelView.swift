import SwiftUI
import AppKit

@MainActor
final class TranslationPanelPinState: ObservableObject {
    @Published var isPinned = false
}

struct TranslationPanelView: View {
    @ObservedObject var viewModel: TranslationPanelViewModel
    @ObservedObject var pinState: TranslationPanelPinState
    @State private var showsCopiedMessage = false
    @State private var isRefreshing = false
    @State private var isSourceExpanded = false

    let onRefreshTranslation: () -> Void
    let onTogglePinned: () -> Void

    private let panelHorizontalPadding: CGFloat = 12
    private let panelBottomPadding: CGFloat = 10
    private let contentPadding: CGFloat = 8
    private let languagePickerWidth: CGFloat = 106

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerBar
            sourceDisclosure
            translationBody
            actionBar
        }
        .font(.body)
        .padding(.top, 0)
        .padding(.horizontal, panelHorizontalPadding)
        .padding(.bottom, panelBottomPadding)
        .frame(
            minWidth: CGFloat(AppSettings.translationPanelWidthRange.lowerBound),
            maxWidth: .infinity,
            minHeight: CGFloat(AppSettings.translationPanelHeightRange.lowerBound),
            maxHeight: .infinity,
            alignment: .topLeading
        )
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
                .frame(width: languagePickerWidth)
            Image(systemName: "arrow.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            languagePicker(selection: targetLanguageSelection, options: SupportedLanguages.target)
                .frame(width: languagePickerWidth)

            Spacer(minLength: 0)

            IconActionButton(
                systemName: pinState.isPinned ? "pin.fill" : "pin",
                action: onTogglePinned
            )
            .help(pinState.isPinned ? "取消固定" : "固定窗口")
            .frame(width: 32, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
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
            Text(translationDisplayText)
                .font(.title3)
                .lineSpacing(3)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(contentPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.22))
        )
        .layoutPriority(1)
    }

    private var translationDisplayText: String {
        switch viewModel.status {
        case .loading(let message), .error(let message):
            return message
        case .ready, .translated:
            return viewModel.translatedText.isEmpty ? "译文会显示在这里" : viewModel.translatedText
        }
    }

    private var sourceDisclosure: some View {
        VStack(alignment: .leading, spacing: 7) {
            DisclosureGroup(isExpanded: $isSourceExpanded) {
                ScrollView {
                    Text(viewModel.originalText)
                        .font(.callout)
                        .lineSpacing(2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.trailing, 2)
                }
                .frame(minHeight: 54, maxHeight: 126, alignment: .topLeading)
                .padding(.top, 6)
            } label: {
                HStack(spacing: 7) {
                    Text("原文")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(hasOriginalText ? .secondary : Color.secondary.opacity(0.45))

                    Spacer(minLength: 0)
                }
            }
            .disabled(!hasOriginalText)
            .disclosureGroupStyle(.automatic)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .separatorColor).opacity(0.16))
        )
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

    private var hasOriginalText: Bool {
        !viewModel.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        pinState: TranslationPanelPinState(),
        onRefreshTranslation: {},
        onTogglePinned: {}
    )
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("翻译窗口 - 加载中") {
    TranslationPanelView(
        viewModel: .loadingPreview,
        pinState: TranslationPanelPinState(),
        onRefreshTranslation: {},
        onTogglePinned: {}
    )
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("翻译窗口 - 错误") {
    TranslationPanelView(
        viewModel: .errorPreview,
        pinState: TranslationPanelPinState(),
        onRefreshTranslation: {},
        onTogglePinned: {}
    )
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}
#endif
