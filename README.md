# YIYI

YIYI 是一个 macOS 原生划词翻译工具。它常驻菜单栏，通过全局快捷键读取当前选中文本，并使用 OpenAI 兼容接口完成翻译。

## 下载

请前往 [GitHub Releases](https://github.com/wilson-lyc/YIYI/releases/latest) 下载最新版本的 `YIYI-*.dmg`。

安装方式：

1. 下载并打开 `YIYI-*.dmg`
2. 将 `YIYI.app` 拖入 `Applications`
3. 首次启动时，如果 macOS 提示来自未知开发者，请在 `系统设置 -> 隐私与安全性` 中允许打开
4. 按提示授予辅助功能权限，用于读取选中文本

当前发布包使用 ad-hoc 签名，未经过 Apple notarization。这是不使用 Apple Developer 账号时的常见打包方式。

## 功能

- 菜单栏常驻入口
- 翻译浮窗展示原文、译文、加载状态和错误提示
- 全局快捷键 `Option + D` 触发划词翻译
- 通过 Accessibility 读取选中文本，必要时使用复制动作兜底
- 支持 OpenAI 兼容接口，默认模型为 `gpt-4o-mini`

## 本地开发

需要 macOS 14 或更高版本，以及 Xcode/Swift 工具链。

```bash
swift run YIYI
```

本地打包：

```bash
Scripts/package_app.sh
```

打包产物会生成在 `dist/` 目录。

## 授权

YIYI 基于 GNU General Public License v3.0 授权，详见 [LICENSE](LICENSE)。

- 你可以自由使用、复制、修改和分发本项目
- 分发修改版本或衍生作品时，需要继续遵守 GPL-3.0 的条款
- 本项目按现状提供，不提供任何明示或暗示担保
