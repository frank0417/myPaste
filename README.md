# PasteNest — Mac 剪贴板管理工具

保存、搜索、同步你复制的一切。面向 Mac App Store 的原生 SwiftUI 应用。

## 功能

- **自动保存**：监听系统剪贴板，捕获文本、富文本、链接、图片、颜色、文件与代码片段
- **智能分类**：自动识别链接 / 颜色 / 代码等内容类型
- **全文搜索**：按内容、来源应用、预览标题即时筛选
- **置顶与看板**：常用条目置顶，按「工作 / 灵感 / 代码片段」整理
- **收藏夹长期保存**：只有收藏的内容长期保留，未收藏的在最后一次使用满 3 天后自动清理（天数可在「设置 → 历史」调整，置顶也会保留）
- **收藏夹分类标签**：收藏夹是独立面板（底部面板与主窗口都有），收藏可打上自定义分类标签（工作 / 灵感 / 代码 …），按标签筛选，标签也能被搜索命中
- **一键粘贴**：菜单栏面板或主窗口双击即可粘贴到当前应用
- **截图入库**：区域 / 窗口 / 整屏三种截图，用系统原生选区界面（Esc 取消），结果同时进入剪贴板与历史，可搜「截图」找回
- **截图识字**：与截图并列的独立动作（菜单或快捷键 `⌃⇧⌘5`），用 Vision 在本机识别画面文字（中英文），**只保留识别出的文字、不保存图片**；识别出链接会自动变成链接条目
- **全局快捷键**：底部面板、主窗口、区域截图、截图识字各有一个可自定义快捷键（默认 `⇧⌘V` / `⌥⌘V` / `⌃⇧⌘4` / `⌃⇧⌘5`），在「设置 → 通用 → 快捷键」录制；组合被占用时保留原快捷键并提示
- **导出历史**：设置中可将剪贴板历史导出为 JSON
- **首次演示数据**：空库时自动填充示例条目与看板
- **iCloud 同步**：SwiftData + CloudKit，多台 Mac 共享历史
- **菜单栏常驻**：`LSUIElement` 菜单栏应用；底部面板与主窗口互斥显示，不会同时出现

## 系统要求

- macOS 14 Sonoma 或更高
- Xcode 15.4+
- 已登录 Apple ID（用于 iCloud 同步与 App Store 分发）

## 快速开始

```bash
cd Paste
open Paste.xcodeproj
```

1. 在 Xcode 中选择自己的 **Team** 与 Signing
2. 将 Bundle ID `com.mypaste.PasteNest` 换成你的唯一标识
3. 在开发者后台启用 **iCloud / CloudKit**，容器建议：`iCloud.com.mypaste.PasteNest`
4. 运行目标 **My Mac**
5. 首次粘贴到其他 App 时，在「系统设置 → 隐私与安全性 → 辅助功能」中允许 PasteNest
6. 首次截图时，在「系统设置 → 隐私与安全性 → 屏幕录制」中允许 PasteNest（授权后需重启 App）

## 项目结构

```
Paste/
├── Paste.xcodeproj
├── Paste/
│   ├── PasteApp.swift          # 菜单栏 + 主窗口入口
│   ├── Models/                 # SwiftData 模型与 AppState
│   ├── Services/               # 剪贴板监听、存储、截图、同步状态
│   ├── Views/                  # 主界面 / 列表 / 预览 / 设置
│   ├── Utilities/              # 主题、类型识别、快捷键、保留策略、收藏分类
│   ├── Info.plist
│   ├── Paste.entitlements      # Sandbox + CloudKit
│   └── PrivacyInfo.xcprivacy
├── PasteTests/
└── preview/                    # 交互式 UI 预览（浏览器）
```

## App Store 准备清单

> 上架时请使用你自己的唯一应用名 / Bundle ID。本仓库的应用名为 **PasteNest**（App Store 无同名应用；ClipStack / ClipShelf / ClipKeep / ClipNest 均已被占用）。

- [x] App Sandbox 与 Hardened Runtime
- [x] CloudKit / iCloud 容器 entitlement
- [x] Privacy Manifest（`PrivacyInfo.xcprivacy`）
- [x] 辅助功能用途说明文案
- [x] 替换 App Icon 资源（`Assets.xcassets/AppIcon.appiconset`）
- [ ] 配置真实 Team ID / Bundle ID / iCloud 容器
- [ ] App Store Connect 截图与审核说明（需说明剪贴板与辅助功能用途）
- [ ] 可选：接入 `KeyboardShortcuts` 等库做可自定义全局热键

## 打安装包（.dmg / .pkg）

在 **Mac + Xcode** 上：

```bash
./scripts/package.sh              # 生成 dist/PasteNest.app + dist/PasteNest-1.5.0.dmg
./scripts/package.sh --sign --pkg # Developer ID 签名 + .pkg
make package                      # 同上（Makefile 封装）
```

也可用 GitHub Actions：**Actions → Package macOS → Run workflow**，从 Artifacts 下载 DMG。

详细步骤见 [docs/PACKAGING.md](docs/PACKAGING.md)。

> 本 Cloud / Linux 环境无法编译 macOS 二进制；安装包需在 Mac 或 CI 的 `macos-14` runner 上生成。

## UI 预览

当前云环境无法编译 macOS 应用。可用浏览器打开交互预览：

```bash
open Paste/preview/index.html
```

## 许可

MIT
