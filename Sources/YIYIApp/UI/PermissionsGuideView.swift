import SwiftUI

struct PermissionsGuideView: View {
    @ObservedObject var permissionService: AppPermissionService
    let onReject: () -> Void
    let onOpenSettings: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("开启 YIYI 所需权限", systemImage: "hand.point.up.left.fill")
                    .font(.title3.weight(.semibold))

                Text("划词翻译需要 macOS 辅助功能权限。开启后，YIYI 才会注册快捷键并开始监听划词翻译操作。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(permissionService.requirements) { requirement in
                    permissionRow(requirement)
                }
            }

            Divider()

            HStack {
                Spacer()

                if permissionService.hasFullPermission {
                    Button("完成") {
                        onFinish()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button("拒绝并退出", role: .destructive) {
                        onReject()
                    }
                    .controlSize(.large)

                    Button("配置权限") {
                        onOpenSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .frame(width: 500)
        .background(LexiTheme.surface)
    }

    private func permissionRow(_ requirement: AppPermissionRequirement) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: requirement.isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(requirement.isGranted ? Color.green : LexiTheme.warm)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(requirement.title)
                    .font(.headline)

                Text(requirement.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text(requirement.isGranted ? "已开启" : "未开启")
                .font(.caption.weight(.semibold))
                .foregroundStyle(requirement.isGranted ? Color.green : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(LexiTheme.card, in: Capsule())
        }
        .padding(12)
        .background(LexiTheme.card.opacity(0.75), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
