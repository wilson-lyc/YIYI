import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    @State private var selectedPage: SettingsPage = .general
    @State private var selectedModelID: UUID?
    @State private var selectedPromptID: UUID?
    @State private var hoveredPage: SettingsPage?
    @State private var hoveredModelID: UUID?
    @State private var hoveredPromptID: UUID?
    @State private var isModelAddHovered = false
    @State private var isPromptAddHovered = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(minWidth: 920, minHeight: 620)
        .background(SettingsPalette.background)
        .onAppear {
            selectedModelID = selectedModelID ?? appState.settings.activeModelVersionID
            selectedPromptID = selectedPromptID ?? appState.settings.activePromptVersionID
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 1) {
                ForEach(SettingsPage.allCases) { page in
                    sidebarButton(page)
                }
            }
            .padding(.top, 18)
            .padding(.horizontal, 8)

            Spacer()
        }
        .frame(width: 210)
        .background(SettingsPalette.sidebar)
    }

    private func sidebarButton(_ page: SettingsPage) -> some View {
        Button {
            selectedPage = page
        } label: {
            HStack(spacing: 10) {
                Image(systemName: page.symbolName)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
                Text(page.title)
                    .font(.system(size: 14, weight: .regular))
                Spacer()
            }
            .contentShape(Rectangle())
            .foregroundStyle(selectedPage == page ? .primary : .secondary)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(sidebarButtonBackground(for: page))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            hoveredPage = isHovered ? page : nil
        }
    }

    private func sidebarButtonBackground(for page: SettingsPage) -> Color {
        if selectedPage == page {
            return SettingsPalette.selection
        }

        if hoveredPage == page {
            return SettingsPalette.hover
        }

        return .clear
    }

    @ViewBuilder
    private var content: some View {
        switch selectedPage {
        case .general:
            generalPage
        case .models:
            modelsPage
        case .prompts:
            promptsPage
        }
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            pageTitle("常规")

            settingsPanel {
                settingsRow("主题", contentAlignment: .trailing) {
                    Picker("", selection: $appState.settings.appearancePreference) {
                        ForEach(AppearancePreference.allCases) { preference in
                            Text(preference.title)
                                .tag(preference)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }

                Divider()

                settingsRow("开机自启", contentAlignment: .trailing) {
                    Toggle("", isOn: $appState.settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Divider()

                settingsRow("快捷键配置", contentAlignment: .trailing) {
                    TextField("⌥D", text: $appState.settings.shortcutDisplay)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var modelsPage: some View {
        versionPage(title: "模型") {
            versionList(
                items: appState.settings.modelVersions,
                activeID: appState.settings.activeModelVersionID,
                selectedID: selectedModelID,
                hoveredID: $hoveredModelID,
                isAddHovered: $isModelAddHovered,
                addTitle: "新增模型",
                title: \.name,
                onSelect: { selectedModelID = $0 },
                onAdd: { selectedModelID = appState.addModelVersion() }
            )
        } detail: {
            if let model = selectedModelBinding {
                modelEditor(model)
            } else {
                emptyState("未选择模型")
            }
        }
    }

    private func modelEditor(_ model: Binding<ModelVersion>) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsPanel {
                settingsRow("名称") {
                    TextField("名称", text: model.name)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                settingsRow("协议") {
                    Text("OpenAI")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Divider()

                settingsRow("Base URL") {
                    TextField("https://api.openai.com/v1", text: model.baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                settingsRow("API Key") {
                    SecureField("API Key", text: model.apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                settingsRow("模型名称") {
                    TextField("gpt-4o-mini", text: model.modelName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            actionRow(
                isActive: appState.settings.activeModelVersionID == model.wrappedValue.id,
                activateTitle: "设为当前",
                deleteTitle: "删除",
                canDelete: appState.settings.modelVersions.count > 1,
                onActivate: { appState.activateModelVersion(id: model.wrappedValue.id) },
                onDelete: {
                    appState.deleteModelVersion(id: model.wrappedValue.id)
                    selectedModelID = appState.settings.activeModelVersionID
                }
            )
        }
    }

    private var promptsPage: some View {
        versionPage(title: "提示词") {
            versionList(
                items: appState.settings.promptVersions,
                activeID: appState.settings.activePromptVersionID,
                selectedID: selectedPromptID,
                hoveredID: $hoveredPromptID,
                isAddHovered: $isPromptAddHovered,
                addTitle: "新增提示词",
                title: \.name,
                onSelect: { selectedPromptID = $0 },
                onAdd: { selectedPromptID = appState.addPromptVersion() }
            )
        } detail: {
            if let prompt = selectedPromptBinding {
                promptEditor(prompt)
            } else {
                emptyState("未选择提示词")
            }
        }
    }

    private func promptEditor(_ prompt: Binding<PromptVersion>) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsPanel {
                settingsRow("名称") {
                    TextField("名称", text: prompt.name)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("系统提示词")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    editor(text: prompt.systemPrompt, height: 120)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("提示词")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    editor(text: prompt.prompt, height: 230)
                }
            }

            actionRow(
                isActive: appState.settings.activePromptVersionID == prompt.wrappedValue.id,
                activateTitle: "设为当前",
                deleteTitle: "删除",
                canDelete: appState.settings.promptVersions.count > 1,
                onActivate: { appState.activatePromptVersion(id: prompt.wrappedValue.id) },
                onDelete: {
                    appState.deletePromptVersion(id: prompt.wrappedValue.id)
                    selectedPromptID = appState.settings.activePromptVersionID
                }
            )
        }
    }

    private func versionPage<ListContent: View, DetailContent: View>(
        title: String,
        @ViewBuilder list: () -> ListContent,
        @ViewBuilder detail: () -> DetailContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            pageTitle(title)

            HStack(alignment: .top, spacing: 24) {
                list()
                    .frame(width: 220)

                ScrollView {
                    detail()
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.trailing, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func versionList<Item: Identifiable>(
        items: [Item],
        activeID: UUID,
        selectedID: UUID?,
        hoveredID: Binding<UUID?>,
        isAddHovered: Binding<Bool>,
        addTitle: String,
        title: KeyPath<Item, String>,
        onSelect: @escaping (UUID) -> Void,
        onAdd: @escaping () -> Void
    ) -> some View where Item.ID == UUID {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                Button {
                    onSelect(item.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: activeID == item.id ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(activeID == item.id ? SettingsPalette.accent : .secondary)
                        Text(item[keyPath: title])
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(selectionBackground(isSelected: selectedID == item.id, isHovered: hoveredID.wrappedValue == item.id))
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    hoveredID.wrappedValue = isHovered ? item.id : nil
                }
            }

            Button(action: onAdd) {
                Label(addTitle, systemImage: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(selectionBackground(isSelected: false, isHovered: isAddHovered.wrappedValue))
                    )
            }
            .buttonStyle(.plain)
            .onHover { isHovered in
                isAddHovered.wrappedValue = isHovered
            }
        }
    }

    private func selectionBackground(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return SettingsPalette.selection
        }

        if isHovered {
            return SettingsPalette.hover
        }

        return .clear
    }

    private func pageTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 24, weight: .semibold))
    }

    private func settingsPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsPalette.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(SettingsPalette.border)
        )
    }

    private func settingsRow<Content: View>(
        _ title: String,
        contentAlignment: Alignment = .leading,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: contentAlignment)
        }
        .frame(minHeight: 34)
    }

    private func editor(text: Binding<String>, height: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(SettingsPalette.border)
            )
            .frame(height: height)
    }

    private func actionRow(
        isActive: Bool,
        activateTitle: String,
        deleteTitle: String,
        canDelete: Bool,
        onActivate: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            if isActive {
                Label("当前", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SettingsPalette.accent)
            } else {
                Button(activateTitle, action: onActivate)
            }

            Button(role: .destructive, action: onDelete) {
                Text(deleteTitle)
            }
            .disabled(!canDelete)

            Spacer()
        }
    }

    private func emptyState(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(SettingsPalette.panel, in: RoundedRectangle(cornerRadius: 8))
    }

    private var selectedModelBinding: Binding<ModelVersion>? {
        let id = selectedModelID ?? appState.settings.activeModelVersionID
        guard appState.settings.modelVersions.contains(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: {
                appState.settings.modelVersions.first { $0.id == id } ?? appState.settings.modelVersions[0]
            },
            set: { updatedVersion in
                guard let index = appState.settings.modelVersions.firstIndex(where: { $0.id == id }) else {
                    return
                }
                appState.settings.modelVersions[index] = updatedVersion
            }
        )
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
}

private enum SettingsPage: CaseIterable, Identifiable {
    case general
    case models
    case prompts

    var id: Self { self }

    var title: String {
        switch self {
        case .general:
            return "常规"
        case .models:
            return "模型"
        case .prompts:
            return "提示词"
        }
    }

    var symbolName: String {
        switch self {
        case .general:
            return "gearshape"
        case .models:
            return "cpu"
        case .prompts:
            return "text.quote"
        }
    }
}

private enum SettingsPalette {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .controlBackgroundColor).opacity(0.58)
    static let panel = Color(nsColor: .controlBackgroundColor).opacity(0.72)
    static let border = Color(nsColor: .separatorColor).opacity(0.28)
    static let selection = Color(nsColor: NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua
            ? NSColor(red: 0x38 / 255, green: 0x38 / 255, blue: 0x39 / 255, alpha: 1)
            : NSColor(red: 0xe6 / 255, green: 0xe6 / 255, blue: 0xe7 / 255, alpha: 1)
    })
    static let hover = selection
    static let accent = Color(nsColor: .controlAccentColor)
}

#if DEBUG
#Preview("设置窗口") {
    SettingsView(appState: .settingsPreview)
        .frame(width: 920, height: 620)
}
#endif
