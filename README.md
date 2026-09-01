# Paste — Mac 剪贴板管理工具

保存、搜索、同步你复制的一切。面向 Mac App Store 的原生 SwiftUI 应用。

## 功能

- **自动保存**：监听系统剪贴板，捕获文本、富文本、链接、图片、颜色、文件与代码片段
- **智能分类**：自动识别链接 / 颜色 / 代码等内容类型
- **全文搜索**：按内容、来源应用、预览标题即时筛选
- **置顶与看板**：常用条目置顶，按「工作 / 灵感 / 代码片段」整理
- **一键粘贴**：菜单栏面板或主窗口双击即可粘贴到当前应用
- **iCloud 同步**：SwiftData + CloudKit，多台 Mac 共享历史
- **菜单栏常驻**：`LSUIElement` 菜单栏应用，快捷键 `⇧⌘V` 呼出

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
2. 将 Bundle ID `com.mypaste.Paste` 换成你的唯一标识
3. 在开发者后台启用 **iCloud / CloudKit**，容器建议：`iCloud.com.mypaste.Paste`
4. 运行目标 **My Mac**
5. 首次粘贴到其他 App 时，在「系统设置 → 隐私与安全性 → 辅助功能」中允许 Paste

## 项目结构

```
Paste/
├── Paste.xcodeproj
├── Paste/
│   ├── PasteApp.swift          # 菜单栏 + 主窗口入口
│   ├── Models/                 # SwiftData 模型与 AppState
│   ├── Services/               # 剪贴板监听、存储、同步状态
│   ├── Views/                  # 主界面 / 列表 / 预览 / 设置
│   ├── Utilities/              # 主题、类型识别、快捷键
│   ├── Info.plist
│   ├── Paste.entitlements      # Sandbox + CloudKit
│   └── PrivacyInfo.xcprivacy
├── PasteTests/
└── preview/                    # 交互式 UI 预览（浏览器）
```

## App Store 准备清单

> 上架时请使用你自己的唯一应用名 / Bundle ID。已有商业应用名为 Paste，审核时建议使用可区分名称（例如 myPaste）。

- [x] App Sandbox 与 Hardened Runtime
- [x] CloudKit / iCloud 容器 entitlement
- [x] Privacy Manifest（`PrivacyInfo.xcprivacy`）
- [x] 辅助功能用途说明文案
- [ ] 替换 App Icon 资源（`Assets.xcassets/AppIcon.appiconset`）
- [ ] 配置真实 Team ID / Bundle ID / iCloud 容器
- [ ] App Store Connect 截图与审核说明（需说明剪贴板与辅助功能用途）
- [ ] 可选：接入 `KeyboardShortcuts` 等库做可自定义全局热键

## UI 预览

当前云环境无法编译 macOS 应用。可用浏览器打开交互预览：

```bash
open Paste/preview/index.html
```

## 许可

MIT
