import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    var onShortcutRecordingChanged: (Bool) -> Void = { _ in }

    @State private var hoveredModelID: UUID?
    @State private var hoveredPromptID: UUID?
    @State private var isModelAddHovered = false
    @State private var isPromptAddHovered = false
    @State private var isContentScrolled = false
    @State private var contentViewportHeight: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(minWidth: 840, minHeight: 660)
        .background {
            HStack(spacing: 0) {
                Color.clear.frame(width: 180)
                SettingsPalette.background
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            viewModel.prepareSelectionsIfNeeded()
        }
        .onChange(of: viewModel.selectedPage) {
            isContentScrolled = false
        }
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 1) {
                ForEach(SettingsPage.allCases) { page in
                    sidebarButton(page)
                }
            }
            .padding(.top, 54)
            .padding(.horizontal, 6)

            Spacer()
        }
        .frame(width: 180)
        .background(.regularMaterial)
    }

    private func sidebarButton(_ page: SettingsPage) -> some View {
        Button {
            viewModel.selectedPage = page
        } label: {
            HStack(spacing: 8) {
                Image(systemName: page.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 16)
                Text(page.title)
                    .font(.system(size: 13, weight: .regular))
                Spacer()
            }
            .contentShape(Rectangle())
            .foregroundStyle(viewModel.selectedPage == page ? .white : .secondary)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(sidebarButtonBackground(for: page))
            )
        }
        .buttonStyle(.plain)
    }

    private func sidebarButtonBackground(for page: SettingsPage) -> Color {
        if viewModel.selectedPage == page {
            return SettingsPalette.accent
        }

        return .clear
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.selectedPage {
        case .general:
            rightContent(title: viewModel.selectedPage.title) {
                generalPage
            }
        case .models:
            rightContent(title: viewModel.selectedPage.title, scrolls: false) {
                modelsPage
            }
        case .prompts:
            rightContent(title: viewModel.selectedPage.title, scrolls: false) {
                promptsPage
            }
        }
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            plainSettingsGroup {
                settingsRow("主题", contentAlignment: .trailing) {
                    Picker("", selection: $viewModel.settings.appearancePreference) {
                        ForEach(AppearancePreference.allCases) { preference in
                            Text(preference.title)
                                .tag(preference)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                }

                Divider()

                settingsRow("开机自启", contentAlignment: .trailing) {
                    Toggle("", isOn: $viewModel.settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Divider()

                settingsRow("快捷键配置", contentAlignment: .trailing) {
                    shortcutSettingControl
                }

                Divider()

                settingsRow("请求超时", contentAlignment: .trailing) {
                    Stepper(
                        "\(viewModel.settings.requestTimeoutSeconds) 秒",
                        value: $viewModel.settings.requestTimeoutSeconds,
                        in: AppSettings.requestTimeoutRange,
                        step: 5
                    )
                    .frame(width: 230, alignment: .trailing)
                }

                Divider()

                settingsRow("窗口尺寸", contentAlignment: .trailing) {
                    HStack(spacing: 10) {
                        Stepper(
                            "宽 \(viewModel.settings.translationPanelWidth)",
                            value: $viewModel.settings.translationPanelWidth,
                            in: AppSettings.translationPanelWidthRange,
                            step: 20
                        )

                        Stepper(
                            "高 \(viewModel.settings.translationPanelHeight)",
                            value: $viewModel.settings.translationPanelHeight,
                            in: AppSettings.translationPanelHeightRange,
                            step: 20
                        )
                    }
                    .frame(width: 300, alignment: .trailing)
                }
            }

        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var shortcutSettingControl: some View {
        GlobalHotKeySettingControl(
            viewModel: viewModel,
            onRecordingChanged: onShortcutRecordingChanged
        )
    }

    private var modelsPage: some View {
        HStack(alignment: .top, spacing: 18) {
            ScrollView {
                versionList(
                    items: viewModel.settings.modelVersions,
                    activeID: viewModel.settings.activeModelVersionID,
                    selectedID: viewModel.selectedModelID,
                    hoveredID: $hoveredModelID,
                    isAddHovered: $isModelAddHovered,
                    addTitle: "新增模型",
                    title: \.name,
                    onSelect: { viewModel.selectedModelID = $0 },
                    onAdd: { _ = viewModel.addModelVersion() }
                )
            }
            .frame(width: 200)
            .frame(maxHeight: .infinity, alignment: .top)

            if let model = selectedModelBinding {
                modelEditor(model)
            } else {
                emptyState("未选择模型")
            }
        }
        .frame(maxWidth: .infinity, minHeight: contentBodyHeight, alignment: .topLeading)
    }

    private func modelEditor(_ model: Binding<ModelVersion>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsPanel {
                settingsRow("名称") {
                    TextField("名称", text: model.name)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                settingsRow("Base URL") {
                    TextField("Base URL", text: model.baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                settingsRow("API Key") {
                    SecureField("API Key", text: model.apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                settingsRow("模型名称") {
                    TextField("模型名称", text: model.modelName)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("请求 JSON")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    editor(text: model.extraBodyJSON, height: 96)
                        .help(#"例如 {"thinking":{"type":"disabled"}}"#)
                }
            }

            modelActionRow(
                model: model.wrappedValue,
                isActive: viewModel.settings.activeModelVersionID == model.wrappedValue.id,
                canDelete: viewModel.settings.modelVersions.count > 1,
                canActivate: viewModel.modelConnectionTestState == .success,
                onActivate: { viewModel.activateModelVersion(id: model.wrappedValue.id) },
                onDelete: {
                    viewModel.deleteModelVersion(id: model.wrappedValue.id)
                }
            )
        }
        .onChange(of: model.wrappedValue.id) {
            viewModel.resetModelConnectionTestState()
        }
        .onChange(of: model.wrappedValue.baseURL) {
            viewModel.resetModelConnectionTestState()
        }
        .onChange(of: model.wrappedValue.apiKey) {
            viewModel.resetModelConnectionTestState()
        }
        .onChange(of: model.wrappedValue.modelName) {
            viewModel.resetModelConnectionTestState()
        }
        .onChange(of: model.wrappedValue.extraBodyJSON) {
            viewModel.resetModelConnectionTestState()
        }
    }

    private func modelActionRow(
        model: ModelVersion,
        isActive: Bool,
        canDelete: Bool,
        canActivate: Bool,
        onActivate: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            if isActive {
                Label("正在使用", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SettingsPalette.accent)
            } else {
                Button("设为当前", action: onActivate)
                    .disabled(!canActivate)
                    .help(canActivate ? "" : "请先测试连接，测试成功后才能设为当前。")
            }

            Spacer()

            Button {
                guard viewModel.modelConnectionTestState.canStartTest else {
                    return
                }
                testModelConnection(with: model)
            } label: {
                Text(viewModel.modelConnectionTestState.buttonTitle)
                    .foregroundStyle(modelConnectionTestForegroundStyle)
            }
            .disabled(viewModel.modelConnectionTestState.isTesting)
            .allowsHitTesting(viewModel.modelConnectionTestState.canStartTest)
            .help(viewModel.modelConnectionTestState.failureMessage ?? "")

            Button(role: .destructive, action: onDelete) {
                Text("删除")
                    .foregroundStyle(.red)
            }
            .disabled(!canDelete)
        }
    }

    private func testModelConnection(with model: ModelVersion) {
        Task {
            await viewModel.testModelConnection(with: model)
        }
    }

    private var modelConnectionTestForegroundStyle: Color {
        switch viewModel.modelConnectionTestState {
        case .success:
            return .green
        case .idle, .testing, .failure:
            return .primary
        }
    }

    private var promptsPage: some View {
        HStack(alignment: .top, spacing: 18) {
            ScrollView {
                versionList(
                    items: viewModel.settings.promptVersions,
                    activeID: viewModel.settings.activePromptVersionID,
                    selectedID: viewModel.selectedPromptID,
                    hoveredID: $hoveredPromptID,
                    isAddHovered: $isPromptAddHovered,
                    addTitle: "新增提示词",
                    title: \.name,
                    onSelect: { viewModel.selectedPromptID = $0 },
                    onAdd: { _ = viewModel.addPromptVersion() }
                )
            }
            .frame(width: 200)
            .frame(maxHeight: .infinity, alignment: .top)

            if let prompt = selectedPromptBinding {
                promptEditor(prompt, availableHeight: contentBodyHeight)
            } else {
                emptyState("未选择提示词")
            }
        }
        .frame(maxWidth: .infinity, minHeight: contentBodyHeight, alignment: .topLeading)
    }

    private func promptEditor(_ prompt: Binding<PromptVersion>, availableHeight: CGFloat) -> some View {
        let editorHeight = max(180, (availableHeight - 184) / 2)

        return VStack(alignment: .leading, spacing: 14) {
            settingsPanel(maxWidth: .infinity) {
                settingsRow("名称") {
                    TextField("名称", text: prompt.name)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("系统提示词")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    editor(text: prompt.systemPrompt, height: editorHeight)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("提示词")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    editor(text: prompt.prompt, height: editorHeight)
                }
            }

            actionRow(
                isActive: viewModel.settings.activePromptVersionID == prompt.wrappedValue.id,
                activateTitle: "设为当前",
                deleteTitle: "删除",
                canDelete: viewModel.settings.promptVersions.count > 1,
                onActivate: { viewModel.activatePromptVersion(id: prompt.wrappedValue.id) },
                onDelete: {
                    viewModel.deletePromptVersion(id: prompt.wrappedValue.id)
                }
            )
        }
        .frame(maxWidth: .infinity, minHeight: availableHeight, alignment: .topLeading)
    }

    private func versionPage<ListContent: View, DetailContent: View>(
        @ViewBuilder list: () -> ListContent,
        @ViewBuilder detail: () -> DetailContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                list()
                    .frame(width: 200)

                detail()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.trailing, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
        VStack(alignment: .leading, spacing: 6) {
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
                    .padding(.horizontal, 8)
                    .frame(height: 30)
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
                    .padding(.horizontal, 8)
                    .frame(height: 30)
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

    private var contentBodyHeight: CGFloat {
        max(0, contentViewportHeight - 48)
    }

    private func rightContent<Content: View>(
        title: String,
        scrolls: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            pageHeader(title)

            GeometryReader { contentProxy in
                if scrolls {
                    ScrollView {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(
                                    key: SettingsScrollOffsetPreferenceKey.self,
                                    value: proxy.frame(in: .named("SettingsContentScroll")).minY
                                )
                        }
                        .frame(height: 0)

                        content()
                            .padding(24)
                            .frame(maxWidth: .infinity, minHeight: contentProxy.size.height, alignment: .topLeading)
                    }
                    .coordinateSpace(name: "SettingsContentScroll")
                    .onPreferenceChange(SettingsScrollOffsetPreferenceKey.self) { minY in
                        isContentScrolled = minY < -1
                    }
                } else {
                    content()
                        .padding(24)
                        .frame(maxWidth: .infinity, minHeight: contentProxy.size.height, alignment: .topLeading)
                        .onAppear {
                            isContentScrolled = false
                        }
                }
            }
            .onAppear {
                contentViewportHeight = 0
            }
            .background {
                GeometryReader { contentProxy in
                    Color.clear
                        .onAppear {
                            contentViewportHeight = contentProxy.size.height
                        }
                        .onChange(of: contentProxy.size.height) { _, newHeight in
                            contentViewportHeight = newHeight
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func pageHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(height: 60)
        .background {
            if isContentScrolled {
                Rectangle()
                    .fill(.regularMaterial)
            } else {
                SettingsPalette.background
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SettingsPalette.border)
                .frame(height: isContentScrolled ? 1 : 0)
        }
        .shadow(
            color: .black.opacity(isContentScrolled ? 0.14 : 0),
            radius: isContentScrolled ? 10 : 0,
            x: 0,
            y: isContentScrolled ? 4 : 0
        )
    }

    private func settingsPanel<Content: View>(
        maxWidth: CGFloat? = 720,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(12)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(SettingsPalette.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(SettingsPalette.border)
        )
    }

    private func plainSettingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    private func settingsRow<Content: View>(
        _ title: String,
        contentAlignment: Alignment = .leading,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: contentAlignment)
        }
        .frame(minHeight: 30)
    }

    private func editor(text: Binding<String>, height: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(SettingsPalette.border)
            )
            .frame(minHeight: height, maxHeight: height)
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
                    .foregroundStyle(.red)
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
        let id = viewModel.selectedModelID ?? viewModel.settings.activeModelVersionID
        guard viewModel.settings.modelVersions.contains(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: {
                viewModel.settings.modelVersions.first { $0.id == id } ?? viewModel.settings.modelVersions[0]
            },
            set: { updatedVersion in
                guard let index = viewModel.settings.modelVersions.firstIndex(where: { $0.id == id }) else {
                    return
                }
                viewModel.settings.modelVersions[index] = updatedVersion
            }
        )
    }

    private var selectedPromptBinding: Binding<PromptVersion>? {
        let id = viewModel.selectedPromptID ?? viewModel.settings.activePromptVersionID
        guard viewModel.settings.promptVersions.contains(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: {
                viewModel.settings.promptVersions.first { $0.id == id } ?? viewModel.settings.promptVersions[0]
            },
            set: { updatedVersion in
                guard let index = viewModel.settings.promptVersions.firstIndex(where: { $0.id == id }) else {
                    return
                }
                viewModel.settings.promptVersions[index] = updatedVersion
            }
        )
    }
}

private struct SettingsScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
    SettingsView(viewModel: .settingsPreview)
        .frame(width: 900, height: 680)
}
#endif
