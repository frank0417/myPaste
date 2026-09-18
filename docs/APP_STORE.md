# PasteNest — Mac App Store 上架材料

本文档汇总上架所需的全部素材与配置。标记 ✅ 的已就绪，其余需你补充。

## 1. 应用基本信息

| 项目 | 内容 |
|------|------|
| 应用名称 | **PasteNest** |
| 副标题（30 字符内） | 复制过的，都还在 |
| Bundle ID | `com.mypaste.PasteNest` |
| SKU | `pastenest-macos` |
| 主要类别 | 效率（Productivity） |
| 次要类别 | 工具（Utilities） |
| 内容分级 | 4+（无受限内容） |
| 最低系统 | macOS 14.0 Sonoma |

## 2. 文案素材

### 宣传文本（170 字符内，可随时更新）

> 复制过的，都还在。PasteNest 静静待在菜单栏，收好你复制的文字、链接、图片和代码。快捷键唤出货架，回车粘贴；冻结屏幕圈选标注，图里的字也能在本机识别。无广告，无订阅。

完整营销文案与图解见 [MARKETING.md](MARKETING.md)。

### 描述（4000 字符内）

```
PasteNest 是常驻菜单栏的剪贴板巢穴。你复制的一切——文本、链接、图片、文件、代码、颜色——都会自动保存，随时一键找回。

【底部货架，一呼即出】
默认快捷键唤出屏幕底部卡片货架。回车粘贴到当前 App；双击查看完整内容。主窗口另有独立快捷键，两者不会同时出现。

【截图像发一条消息】
冻结当前屏幕，拖出选区，用矩形、箭头、画笔、马赛克、文字标注。确认后同时进入系统剪贴板和历史。

【图里的字，也能搜】
本机用 Vision 识别中英文。可以复制选中的字，也可以只要文字不要图；识别出链接会自动变成链接条目。

【不用整理，它自己认得】
按类型自动打标：图片、链接、代码、颜色、文件、富文本。搜索标题、正文、来源应用和标签。收藏夹可再打分类。

【重要的，留下来】
收藏的内容长期保存；未收藏的按你设定的天数自动清理（默认 3 天）。

【隐私优先】
历史默认只在你的 Mac 上。可选 iCloud 同步，数据走你的 Apple ID，开发者不可访问。无广告、无分析、无账号。

【为 Mac 而生】
原生 SwiftUI，支持 Apple Silicon 与 Intel。登录时启动，关掉窗口不会退出。快捷键录制即刻生效，可一键恢复默认。
```

### 关键词（100 字符内，逗号分隔）

```
剪贴板,clipboard,复制,粘贴,截图,OCR,历史,效率,Paste,snippet
```

## 3. 视觉素材

| 素材 | 状态 | 说明 |
|------|------|------|
| App 图标 1024×1024 | ✅ | `Paste/Paste/Resources/AppIcon-1024.png` |
| 营销截图 2560×1600 | ✅ | `docs/app-store/screenshots/`（6 张，见 [MARKETING.md](MARKETING.md)） |
| 营销截图 1440×900 | ✅ | 同目录 `*-1440x900.png` |

**上架顺序：**
1. `01-hero` 复制过的，都还在
2. `02-hotkey` 按一下，它就来了
3. `03-screenshot` 截图像发一条消息
4. `04-ocr` 图里的字，也能搜
5. `05-search` 不用整理，它自己认得
6. `06-keep` 重要的，留下来

重新出图：`python3 docs/app-store/render_screenshots.py`

## 4. 法律与合规

| 项目 | 状态 | 说明 |
|------|------|------|
| 隐私政策 URL | ⬜ 需提供 | 必须。可托管在 GitHub Pages，要点见下文 |
| 技术支持 URL | ⬜ 需提供 | 可用 GitHub Issues 页面 |
| 隐私清单 PrivacyInfo.xcprivacy | ✅ | 已包含 UserDefaults 访问声明 |
| App 隐私问卷 | 见下文 | 在 App Store Connect 填写 |
| 出口合规（加密） | 见下文 | 仅用系统加密（iCloud/HTTPS），选「豁免」 |

**隐私政策要点（数据实践）：**
- 收集的数据：剪贴板历史（文本/图片/文件）——**仅存储在用户设备**，可选 iCloud 同步（Apple 端到端加密，开发者不可访问）
- 不收集：无分析、无广告、无追踪、无账号体系
- App Store Connect 问卷答案：「不收集数据」（iCloud 同步由用户主动开启且数据对开发者不可见，按 Apple 指引可声明不收集）

**出口合规：** 仅使用 Apple 系统框架内的加密（CloudKit/HTTPS），在 ITSAppUsesNonExemptEncryption 上可声明 `false`（建议加入 Info.plist 以免每次上传都被询问）。

## 5. 账号与技术准备

| 项目 | 状态 | 说明 |
|------|------|------|
| Apple Developer Program 会员 | ⬜ | $99/年，需邓白氏码（个人账号不需要） |
| App Store Connect 创建 App | ⬜ | 用上面的名称/Bundle ID/SKU |
| 签名证书 + Team ID | ⬜ | Xcode → Settings → Accounts 登录后自动管理 |
| iCloud 容器 | ⬜ | 在开发者后台为 `iCloud.com.mypaste.PasteNest` 注册容器并开启 CloudKit |
| 沙盒构建 | ✅ | `Paste.entitlements` 已开启 App Sandbox + iCloud |
| 辅助功能权限说明 | ✅ | Info.plist 已含用途描述字符串 |

**注意：** 上架版本使用 `Paste.entitlements`（沙盒 + iCloud），与 CI 直装包（`Paste-CI.entitlements`，关沙盒）不同。沙盒下「一键粘贴到其他 App」需要用户授予辅助功能权限，应用内已有引导。

**截图功能与沙盒：** 截图通过 ScreenCaptureKit 冻结当前屏幕，再自绘选区与标注层（矩形 / 箭头 / 马赛克 / 文字等）。需要用户授予「屏幕录制」权限；该路径可在沙盒内运行，App Store 构建无需再调用 `/usr/sbin/screencapture`。系统 `screencapture` 仅作为抓取失败时的兜底（非沙盒直装包才可能走这条路径）。

## 6. 构建与上传

在已登录开发者账号的 Mac 上：

```bash
# 归档并导出 App Store 包（自动签名）
./scripts/package.sh --app-store

# 产物在 dist/AppStore/，用 Transporter 或 Xcode Organizer 上传
```

上传后在 App Store Connect：
1. 选择构建版本 → 填写「此版本新功能」
2. 上传截图、填写第 2 节文案
3. 完成隐私问卷与出口合规声明
4. 提交审核（macOS 应用通常 24–48 小时）

## 7. 审核备注（给审核员）

```
PasteNest 是菜单栏常驻应用（无 Dock 图标）。
- 启动后图标出现在屏幕右上角菜单栏，点击或按 ⇧⌘V 唤出底部面板，按 ⌥⌘V 唤出主窗口（两者互斥显示）。
- 「一键粘贴」功能需要辅助功能权限：设置 → 权限 → 按引导授权。不授权时其余功能（记录、搜索、查看）完全可用。
- iCloud 同步为可选功能，未登录 iCloud 时应用全部本地功能正常。
```

## 8. 定价建议

免费 + 无内购起步，或一次性买断 **¥28 / $4.99**。同品类参考：Paste（订阅制）、Maccy（免费开源）、CopyClip（免费）。营销话术见 [MARKETING.md](MARKETING.md)。
