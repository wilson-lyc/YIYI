import SwiftUI

struct PermissionsGuideView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("辅助功能权限", systemImage: "hand.point.up.left.fill")
                .font(.headline)
            Text("划词读取依赖 macOS Accessibility API。首次启动会弹出授权提示；授权后可在任意应用中选中文字并按快捷键提取。")
                .foregroundStyle(.secondary)

            HStack {
                permissionBadge("Accessibility")
                permissionBadge("Input Monitoring")
                Spacer()
            }
        }
        .padding(14)
        .background(LexiTheme.card.opacity(0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func permissionBadge(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(LexiTheme.accent.opacity(0.16), in: Capsule())
    }
}
