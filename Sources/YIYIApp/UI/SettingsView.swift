import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    @State private var selectedPage: SettingsPage = .service
    @State private var selectedPromptID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            navigation
            Divider()
            pageContent
        }
        .frame(minWidth: 980, minHeight: 680)
        .background(SettingsPalette.background)
        .onAppear {
            selectedPromptID = selectedPromptID ?? appState.settings.activePromptVersionID
        }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("易译")
                    .font(.system(size: 28, weight: .bold))
                Text("翻译服务与工作流设置")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 42)
            .padding(.horizontal, 22)

            VStack(spacing: 4) {
                ForEach(SettingsPage.allCases) { page in
                    navigationButton(page)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            statusPanel
                .padding(.horizontal, 14)
                .padding(.bottom, 18)
        }
        .frame(width: 250)
        .background(SettingsPalette.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.28))
                .frame(width: 1)
        }
    }

    private func navigationButton(_ page: SettingsPage) -> some View {
        Button {
            selectedPage = page
        } label: {
            HStack(spacing: 10) {
                Image(systemName: page.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(page.tint.opacity(selectedPage == page ? 1 : 0.14), in: RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(selectedPage == page ? .white : page.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(page.title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(page.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(selectedPage == page ? .white.opacity(0.72) : .secondary)
                }

                Spacer()
            }
            .foregroundStyle(selectedPage == page ? .white : .primary)
            .padding(.horizontal, 10)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedPage == page ? SettingsPalette.selection : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(serviceStatus.title, systemImage: serviceStatus.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(serviceStatus.color)

            Text(serviceStatus.message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsPalette.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(SettingsPalette.border)
        )
    }

    private var pageContent: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedPage {
                    case .service:
                        servicePage
                    case .translation:
                        translationPage
                    case .prompts:
                        promptsPage
                    }
                }
                .frame(maxWidth: 690, alignment: .topLeading)
                .padding(.horizontal, 42)
                .padding(.bottom, 42)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: selectedPage.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(selectedPage.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(selectedPage.tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(selectedPage.title)
                    .font(.system(size: 24, weight: .bold))
                Text(selectedPage.description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 42)
        .frame(height: 92)
    }

    private var servicePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup("模型服务", footer: "Base URL、API Key 和模型名称会直接用于 DeepSeek 兼容的 chat completions 请求。") {
                settingsField("Base URL", systemImage: "link") {
                    TextField("https://api.deepseek.com", text: $appState.settings.baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                settingsDivider

                settingsField("API Key", systemImage: "key.fill") {
                    SecureField("输入 API Key", text: $appState.settings.apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                settingsDivider

                settingsField("模型名称", systemImage: "cpu") {
                    TextField("deepseek-v4-flash", text: $appState.settings.model)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                }
            }

            settingsGroup("连接摘要") {
                VStack(alignment: .leading, spacing: 12) {
                    summaryRow("服务地址", value: trimmed(appState.settings.baseURL), fallback: "未填写")
                    summaryRow("模型", value: trimmed(appState.settings.model), fallback: "未填写")
                    summaryRow("密钥", value: appState.settings.apiKey.isEmpty ? "" : "已填写", fallback: "未填写")
                }
            }
        }
    }

    private var translationPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup("语言与快捷键") {
                settingsField("源语言", systemImage: "text.magnifyingglass") {
                    Picker("", selection: $appState.settings.sourceLanguage) {
                        ForEach(SupportedLanguages.source, id: \.self) { language in
                            Text(language)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }

                settingsDivider

                settingsField("目标语言", systemImage: "character.book.closed") {
                    Picker("", selection: $appState.settings.targetLanguage) {
                        ForEach(SupportedLanguages.target, id: \.self) { language in
                            Text(language)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }

                settingsDivider

                settingsField("全局快捷键", systemImage: "keyboard") {
                    TextField("⌥D", text: $appState.settings.shortcutDisplay)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 130)
                }
            }

            settingsGroup("启动与权限") {
                Toggle(isOn: $appState.settings.launchAtLogin) {
                    Label("登录后自动启动", systemImage: "power")
                }
                .toggleStyle(.switch)

                settingsDivider

                PermissionsGuideView()
            }
        }
    }

    private var promptsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                promptList
                    .frame(width: 230)

                promptDetails
                    .frame(maxWidth: .infinity)
            }

            promptEditor
        }
    }

    private var promptList: some View {
        settingsGroup("Prompt 版本") {
            VStack(spacing: 6) {
                ForEach(appState.settings.promptVersions) { version in
                    promptVersionButton(version)
                }

                Button {
                    selectedPromptID = appState.addPromptVersion()
                } label: {
                    Label("新增版本", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func promptVersionButton(_ version: PromptVersion) -> some View {
        Button {
            selectedPromptID = version.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: appState.settings.activePromptVersionID == version.id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(appState.settings.activePromptVersionID == version.id ? SettingsPalette.success : .secondary)

                Text(version.name)
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selectedPromptID == version.id ? SettingsPalette.selection.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var promptDetails: some View {
        if let prompt = selectedPromptBinding {
            settingsGroup("版本信息") {
                settingsField("名称", systemImage: "tag") {
                    TextField("版本名称", text: prompt.name)
                        .textFieldStyle(.roundedBorder)
                }

                settingsDivider

                settingsField("状态", systemImage: "checkmark.seal") {
                    HStack(spacing: 10) {
                        if appState.settings.activePromptVersionID == prompt.wrappedValue.id {
                            Label("已激活", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(SettingsPalette.success)
                                .font(.system(size: 13, weight: .semibold))
                        } else {
                            Button {
                                appState.activatePromptVersion(id: prompt.wrappedValue.id)
                            } label: {
                                Label("设为当前", systemImage: "checkmark")
                            }
                        }

                        Button(role: .destructive) {
                            appState.deletePromptVersion(id: prompt.wrappedValue.id)
                            selectedPromptID = appState.settings.activePromptVersionID
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .disabled(appState.settings.promptVersions.count <= 1)
                    }
                }
            }
        } else {
            emptyPromptState
        }
    }

    @ViewBuilder
    private var promptEditor: some View {
        if let prompt = selectedPromptBinding {
            settingsGroup("Prompt 内容", footer: "使用 {{selectedText}} 表示当前选中的文本；未包含该变量时，选中文本会自动追加到 Prompt 末尾。") {
                TextEditor(text: prompt.content)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(SettingsPalette.border)
                    )
                    .frame(minHeight: 300)
            }
        } else {
            emptyPromptState
        }
    }

    private var emptyPromptState: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(systemName: "text.quote")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("没有可编辑的 Prompt")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(SettingsPalette.panel, in: RoundedRectangle(cornerRadius: 8))
    }

    private func settingsGroup<Content: View>(
        _ title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsPalette.panel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(SettingsPalette.border)
            )

            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingsField<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 136, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 40)
    }

    private func summaryRow(_ title: String, value: String, fallback: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)

            Text(value.isEmpty ? fallback : value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var settingsDivider: some View {
        Divider()
            .padding(.leading, 150)
            .padding(.vertical, 8)
    }

    private var selectedPromptBinding: Binding<PromptVersion>? {
        let id = selectedPromptID ?? appState.settings.activePromptVersionID
        guard appState.settings.promptVersions.contains(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: {
                appState.settings.promptVersions.first { $0.id == id } ?? appState.settings.promptVersions[0]
            },
            set: { updatedVersion in
                guard let index = appState.settings.promptVersions.firstIndex(where: { $0.id == id }) else {
                    return
                }
                appState.settings.promptVersions[index] = updatedVersion
            }
        )
    }

    private var serviceStatus: SettingsStatus {
        let hasURL = !trimmed(appState.settings.baseURL).isEmpty
        let hasModel = !trimmed(appState.settings.model).isEmpty
        let hasKey = !appState.settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if hasURL && hasModel && hasKey {
            return SettingsStatus(
                title: "服务已配置",
                message: "翻译请求可以使用当前模型服务。",
                symbolName: "checkmark.circle.fill",
                color: SettingsPalette.success
            )
        }

        return SettingsStatus(
            title: "仍需配置",
            message: "请补全服务地址、API Key 与模型名称。",
            symbolName: "exclamationmark.triangle.fill",
            color: SettingsPalette.warning
        )
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum SettingsPage: CaseIterable, Identifiable {
    case service
    case translation
    case prompts

    var id: Self { self }

    var title: String {
        switch self {
        case .service:
            return "模型服务"
        case .translation:
            return "翻译体验"
        case .prompts:
            return "Prompt"
        }
    }

    var subtitle: String {
        switch self {
        case .service:
            return "接口、密钥、模型"
        case .translation:
            return "语言、快捷键、权限"
        case .prompts:
            return "版本与模板"
        }
    }

    var description: String {
        switch self {
        case .service:
            return "配置翻译请求使用的兼容 OpenAI 接口。"
        case .translation:
            return "调整默认语言、启动行为和系统权限提示。"
        case .prompts:
            return "维护多版本 Prompt，并选择当前生效版本。"
        }
    }

    var symbolName: String {
        switch self {
        case .service:
            return "server.rack"
        case .translation:
            return "character.cursor.ibeam"
        case .prompts:
            return "text.quote"
        }
    }

    var tint: Color {
        switch self {
        case .service:
            return Color(red: 0.02, green: 0.42, blue: 0.66)
        case .translation:
            return Color(red: 0.34, green: 0.43, blue: 0.14)
        case .prompts:
            return Color(red: 0.58, green: 0.25, blue: 0.18)
        }
    }
}

private struct SettingsStatus {
    let title: String
    let message: String
    let symbolName: String
    let color: Color
}

private enum SettingsPalette {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .windowBackgroundColor).opacity(0.96)
    static let panel = Color(nsColor: .controlBackgroundColor).opacity(0.82)
    static let border = Color(nsColor: .separatorColor).opacity(0.34)
    static let selection = Color(red: 0.12, green: 0.43, blue: 0.64)
    static let success = Color(red: 0.12, green: 0.52, blue: 0.27)
    static let warning = Color(red: 0.78, green: 0.44, blue: 0.12)
}
