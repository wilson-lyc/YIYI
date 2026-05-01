import SwiftUI

struct PermissionsGuideView: View {
    @ObservedObject var permissionService: AppPermissionService
    let onReject: () -> Void
    let onOpenSettings: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("开启 YIYI 所需权限")
                    .font(.headline)
            }

            VStack(spacing: 8) {
                ForEach(permissionService.requirements) { requirement in
                    permissionRow(requirement)
                }
            }

            Divider()

            HStack(spacing: 6) {
                Spacer()

                if permissionService.hasFullPermission {
                    Button("完成") {
                        onFinish()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("拒绝并退出", role: .destructive) {
                        onReject()
                    }

                    Button("配置权限") {
                        onOpenSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: 480)
        .background(LexiTheme.surface)
    }

    private func permissionRow(_ requirement: AppPermissionRequirement) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "accessibility")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

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
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(LexiTheme.card, in: Capsule())
        }
        .padding(12)
        .background(LexiTheme.card.opacity(0.75), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
