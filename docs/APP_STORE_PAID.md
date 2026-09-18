# PasteNest — 付费上架 Mac App Store 步骤

目标：**用户在 App Store 里付一次钱买下应用**（买断），不是订阅，也不需要写内购代码。

买断只改 App Store Connect 的价格，**不需要 StoreKit**。仓库里的沙盒、隐私清单、出口合规声明已经按上架要求配好。你需要在自己的 Mac 上完成账号、合同、截图和上传。

---

## 先选收费方式

| 方式 | 用户怎么付钱 | 要不要改代码 | 建议 |
|------|----------------|--------------|------|
| **买断（推荐）** | 下载前付一次，之后更新免费 | 否 | 第一版用这个 |
| 免费 + 内购解锁 | 先装再买功能 | 要接 StoreKit | 以后想做试用再考虑 |
| 订阅 | 按月/年续费 | 要接 StoreKit + 订阅组 | 同类里 Paste 用这个，审核和运营更重 |

本文按 **买断** 写。定价建议：中国区 **¥28**（可在 ¥18–38 之间选）。同品类参考：Paste（订阅）、Maccy（免费开源）。

苹果抽成：默认 **30%**；加入 [App Store Small Business Program](https://developer.apple.com/app-store/small-business-program/) 且年收入低于 100 万美元后为 **15%**。

---

## 总流程（按这个顺序做）

```
1. 加入 Apple Developer Program（$99/年）
2. 签 Paid Apps 合同 + 填税表和银行账户   ← 付费应用卡在这里最多
3. 开发者后台注册 Bundle ID 和 iCloud 容器
4. App Store Connect 创建 App，设价格
5. 补齐隐私政策、技术支持链接、截图
6. 在 Mac 上用沙盒证书打包并上传
7. 填元数据、隐私问卷、审核备注，提交审核
```

下面逐步展开。文案、SKU、审核备注等素材见 [APP_STORE.md](APP_STORE.md)。

---

## 第 1 步：Apple Developer Program

1. 用你的 Apple ID 打开 [developer.apple.com/programs](https://developer.apple.com/programs/enroll/)。
2. 选 **个人** 或 **公司/组织**：
   - 个人：不需要邓白氏码，上架名显示个人姓名。
   - 公司：需要邓白氏码（D-U-N-S），上架名显示公司名。
3. 支付会员费 **99 美元/年**，等邮件确认（通常几小时到两天）。
4. 登录后记下 **Team ID**（开发者后台右上角 Membership → Team ID）。后面打包要用。

中国大陆个人账号可以卖付费 Mac 应用，收款走 App Store Connect 里绑的银行卡。

---

## 第 2 步：签 Paid Apps 合同（付费必须）

没签这份合同，Connect 里只能标免费。

1. 打开 [App Store Connect](https://appstoreconnect.apple.com) → **商务 / Business**。
2. **协议** 里找到 **Paid Apps** → **View and Agree to Terms**。必须由 **Account Holder** 签署。
3. 同一页补齐：
   - **银行账户**：可填国内银行卡；状态变成 Active 才能收款。
   - **税务信息**：
     - 所有开发者都要填 **美国税表**（中国个人一般是 **W-8BEN**）。
     - 中国区销售可能还要按提示补本地税表。
4. 等合同、银行、税表三项都显示 **Active**。银行核验有时要 **1–5 个工作日**，这期间不要急着提交审核。

官方说明：

- [签署付费协议](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements)
- [填写税务信息](https://developer.apple.com/help/app-store-connect/manage-tax-information/provide-tax-information/)
- [设置价格](https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price)

---

## 第 3 步：注册 App ID 和 iCloud

1. 打开 [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list)。
2. **Identifiers** → **+** → **App IDs** → **App**。
3. Description 填 `PasteNest`，Bundle ID 选 **Explicit**，填：

   `com.mypaste.PasteNest`

   若这个 ID 已被占用，改成你自己的（例如 `com.你的域名.PasteNest`），并同步改 Xcode 的 `PRODUCT_BUNDLE_IDENTIFIER` 和 `Paste.entitlements` 里的 iCloud 容器名。
4. Capability 勾选：
   - **App Sandbox**（Mac App Store 强制）
   - **iCloud** → 勾选 **CloudKit** → 创建容器 `iCloud.com.mypaste.PasteNest`（或与你的 Bundle ID 对应的容器）
5. 证书不用手搓：在 Mac 上用 Xcode → **Settings → Accounts** 登录开发者账号，勾选 **Automatically manage signing** 即可。App Store 会用 **Apple Distribution**，不要用 Developer ID（那是站外 DMG 用的）。

---

## 第 4 步：在 App Store Connect 创建应用并定价

1. App Store Connect → **我的 App** → **+** → **新建 App**。
2. 填写：

   | 字段 | 填什么 |
   |------|--------|
   | 平台 | **macOS** |
   | 名称 | PasteNest（商店显示名，全球唯一） |
   | 主要语言 | 简体中文 |
   | Bundle ID | 选上一步注册的 ID |
   | SKU | `pastenest-macos`（仅内部用，上架后不能改） |
   | 用户访问权限 | 完整访问即可 |

3. **价格与销售范围**（侧边栏 **Monetization → Pricing and Availability**）：
   1. **Add Pricing**。
   2. **基准国家/地区** 选 **中国大陆**（基准价苹果不会随汇率自动改）。
   3. 选价格档，例如 **¥28**，点 Next。
   4. 其它 174 个店面价格让苹果按汇率自动换算，不要手改（除非你明确要某国不同价）。
   5. Confirm。
4. **销售范围**：默认全球。若只想先卖国内，可只勾中国大陆。
5. **App 信息**：
   - 主要类别：效率（Productivity）
   - 次要类别：工具（Utilities）
   - 内容版权：4+（无限制内容）

价格必须在 **提交审核前** 设好。以后可以改价，也可以改成免费；买断应用 **不需要** 再配内购商品。

---

## 第 5 步：法律链接与隐私问卷

App Store **强制** 隐私政策 URL，没有无法提交。

| 项目 | 怎么做 |
|------|--------|
| 隐私政策 URL | 把 [PRIVACY.md](PRIVACY.md) 放到能公开访问的地址。国内用户打不开 GitHub Pages 时，用自己的网站、Notion 公开页、或国内可访问的静态托管。 |
| 技术支持 URL | 可用 GitHub Issues，例如 `https://github.com/frank0417/myPaste/issues` |
| 营销 URL | 可选 |
| App 隐私问卷 | 选 **不收集数据**（历史只存在用户设备；iCloud 由用户自己的账号端到端同步，开发者不可见） |
| 出口合规 | Info.plist 已设 `ITSAppUsesNonExemptEncryption = false`，上传时选豁免即可 |
| 许可协议 | 用苹果标准 EULA 即可；不必另写 |

隐私政策页必须用 **https**，打开后能读到正文，不要登录墙。

---

## 第 6 步：截图（至少 1 张，建议 5 张）

Mac 截图必须是 **16:10**，且为下列之一：

- 1280 × 800
- 1440 × 900
- 2560 × 1600
- 2880 × 1800

格式：PNG 或 JPEG，**sRGB**，**不要透明通道（alpha）**，单张不超过 10 MB。最多 10 张。

建议拍这 5 张（菜单栏尽量干净）：

1. 底部货架（卡片流 + 顶栏标签）
2. 详情弹窗
3. 时间线 + 自动标签
4. 搜索（有命中计数）
5. 设置页（自定义快捷键）

在 Mac 上可用：系统设置 → 显示器，把分辨率调到 1440×900 或 1280×800 再截。Preview / 预览里检查：工具 → 显示检查器 → 确认没有 Alpha。

图标 1024×1024 已在 `Paste/Paste/Resources/AppIcon-1024.png`，一般不用再传。

---

## 第 7 步：本机签名、归档、上传

必须在 **已登录开发者账号的 Mac + Xcode 15.4+** 上操作。Linux / Cloud Agent 编不出 `.app`。

1. 打开工程并设 Team：

   ```bash
   cd Paste
   open Paste.xcodeproj
   ```

   选中 target **PasteNest** → Signing & Capabilities → Team 选你的开发者团队。  
   确认 **App Sandbox** 和 **iCloud (CloudKit)** 已开，entitlements 用的是 `Paste.entitlements`（**不是** `Paste-CI.entitlements`）。

2. 归档并导出 App Store 包（把 `YOUR_TEAM_ID` 换成第 1 步的 Team ID）：

   ```bash
   ./scripts/package.sh --app-store --team YOUR_TEAM_ID --version 1.5.8
   ```

   产物在 `dist/AppStore/`，一般是 `.pkg`。

3. 上传（任选一种）：

   - 打开 **Transporter**（Mac App Store 搜 “Transporter”）→ 拖入 `.pkg` → Deliver
   - 或 Xcode → **Window → Organizer** → 选 Archive → **Distribute App** → App Store Connect
   - 或命令行：`xcrun altool` / `xcrun iTMSTransporter`（需 App 专用密码）

4. 上传后等 **10–30 分钟**，构建才会出现在 Connect 的「构建版本」里。处理失败会发邮件，常见原因：
   - 用了 Developer ID 而不是 Apple Distribution
   - iCloud 容器没在该 Team 下注册
   - 沙盒没开（CI 的 `Paste-CI.entitlements` 关了沙盒，**不能**用于上架）

App Store 包 **不需要** 公证（notarytool）。公证只用于站外 DMG。

---

## 第 8 步：填版本页并提交审核

在 App Store Connect 打开这个 macOS 版本：

1. **构建版本**：选刚上传的那一包。
2. **此版本的新功能**：首发可写「首次发布。」
3. **描述 / 宣传文本 / 关键词**：直接用 [APP_STORE.md](APP_STORE.md) 第 2 节。
4. **截图**：上传第 6 步的图。
5. **版权**：`2026 PasteNest`（或你的名字/公司）。
6. **联系信息**：填你自己能接到的邮箱和电话（审核员可能打给你，不对外展示）。
7. **审核备注**（Notes）：贴 APP_STORE.md 第 7 节，务必说明：
   - 这是菜单栏应用，没有 Dock 图标
   - 启动后看屏幕右上角
   - 快捷键 `⇧⌘V` / `⌥⌘V`
   - 辅助功能、屏幕录制是可选权限
8. 点 **添加以供审核** → **提交以供审核**。

macOS 应用通常 **24–48 小时** 出结果，也可能更久。

---

## 审核时审核员怎么用（写进备注）

PasteNest 是 `LSUIElement` 菜单栏应用，审核员如果只看 Dock 会以为「打不开」。备注里写清楚：

```
PasteNest 是菜单栏常驻应用（无 Dock 图标）。
- 启动后图标出现在屏幕右上角菜单栏。点击图标，或按 ⇧⌘V 唤出底部面板，按 ⌥⌘V 唤出主窗口。
- 「一键粘贴」需要辅助功能权限：系统设置 → 隐私与安全性 → 辅助功能。不授权时记录、搜索、查看仍可用。
- 截图需要屏幕录制权限。不授权时其它功能正常。
- iCloud 同步可选。未登录 iCloud 时本地功能完整。
- 这是付费买断应用，无账号、无广告、无第三方追踪。
```

剪贴板 + 辅助功能 + 截屏是审核敏感点。不要在截图或演示数据里出现别人的隐私内容、密码、密钥。

---

## 第 9 步：过审之后

1. 状态变为 **Ready for Sale / 已就绪销售** 后，商店页几小时内能搜到。
2. 用另一台 Mac、**未登录你开发者账号的 Apple ID** 搜索 PasteNest，确认标价和购买流程。
3. 收入在 App Store Connect → **付款和财务报告**。中国区通常每月打一次款（需达到最低打款额）。
4. 以后发版：把 `CFBundleVersion`（当前 28）加一，`CFBundleShortVersionString`（当前 1.5.8）按需要升，再 `--app-store` 上传，在 Connect 新建版本提交。

---

## 和站外 DMG 的区别（不要混用）

| | Mac App Store | GitHub / 官网 DMG |
|--|----------------|-------------------|
| 签名 | Apple Distribution + 沙盒 | Developer ID + 公证 |
| Entitlements | `Paste.entitlements`（沙盒 + iCloud） | `Paste-CI.entitlements`（CI 关沙盒） |
| 命令 | `./scripts/package.sh --app-store --team TEAMID` | `./scripts/package.sh --sign --notarize` |
| 收费 | App Store 买断 | 你自己收款（本仓库不负责） |

同一 Bundle ID 不能同时用两套分发证书长期并存搞混；商店版必须走沙盒。

---

## 提交前核对清单

- [ ] Developer Program 已激活，Team ID 已知
- [ ] Paid Apps 协议、银行、税表均为 Active
- [ ] Bundle ID 与 iCloud 容器已在该 Team 注册
- [ ] Connect 里已创建 macOS App，价格已设（例如 ¥28）
- [ ] 隐私政策 URL、技术支持 URL 可打开
- [ ] 至少 1 张 16:10 截图（无 alpha）
- [ ] Xcode Team 正确，使用 `Paste.entitlements`
- [ ] `./scripts/package.sh --app-store --team TEAMID` 成功
- [ ] Transporter / Organizer 上传成功，构建可被选中
- [ ] 审核备注说明了菜单栏入口和权限
- [ ] 隐私问卷填「不收集数据」，出口合规豁免

还缺的素材（截图、两个 URL、真实 Team）标在 [APP_STORE.md](APP_STORE.md) 里。
