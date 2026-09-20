# App Review 2.1 — Information Needed 回复稿

苹果这条 **不是功能被拒**，是新开发者账号缺少审核历史，要求补材料。不必改代码、不必重新打包，除非你还想修别的问题。

## 你要做的三件事

1. **在真机 Mac（最新 macOS）录一段屏**（见下方脚本）。云环境录不了，必须你本机录。
2. 打开 [App Store Connect](https://appstoreconnect.apple.com) → 该 App → **审核 / Resolution Center** → **Reply**，把下面英文全文贴进去，并 **附上那段视频**。
3. 同一页打开 **App Review Information → Notes（备注）**，再贴一遍同样英文（以后提交会带着）。然后点 **Submit for Review**。

附件优先用 Resolution Center 的附件。若体积太大，把 `.mov` 放到 iCloud 共享链接（任何人可看、勿设密码）写进回复。

---

## 录屏脚本（约 60–90 秒）

用 **QuickTime Player → 文件 → 新建屏幕录制**。从 **启动 App 开始**，不要先切到已经打开的界面。

1. Spotlight（⌘Space）搜 `PasteNest`，回车启动。
2. **立刻把鼠标移到屏幕右上角菜单栏**，点层叠方块图标（`square.stack.3d.up.fill`）。  
   本应用是菜单栏常驻（`LSUIElement`），**Dock 里没有图标**。审核员最容易卡在这一步。
3. 底部货架出现后，展示自动填好的示例卡片（链接 / 代码 / 文本等）。
4. 打开备忘录或文本编辑，复制一句无隐私的话（例如 `PasteNest review demo`），再唤出货架，指出新卡片出现。
5. 在货架里按 ⌘F 搜索刚才那句话，展示命中。
6. 按 ⌥⌘V 打开主窗口（与货架互斥），点标签筛选、打开收藏夹。
7. 菜单栏图标 **右键 → 设置**（或货架里的设置），展示快捷键页；打开「同步」页，说明 iCloud 是可选、默认本机。
8. **不要登录任何账号**（本应用没有账号）。**不要演示内购**（本应用没有内购，买断在下载时完成）。
9. 辅助功能 / 屏幕录制可以不授权：记录、搜索、查看不依赖它们。若已授权，可再录一次区域截图（⇧⌘D），非必须。
10. 停录。导出 `.mov` 或 `.mp4`。

录屏里不要出现密码、验证码、别人的聊天记录。

---

## 复制这段英文到 Resolution Center 和 Notes

```
Hello App Review team,

Thank you for the message. PasteNest is a new Mac App Store listing from this developer account. The app is complete and was tested on a physical Mac running the latest macOS. A screen recording of the typical user flow is attached to this reply (and will remain in App Review Notes for future submissions).

IMPORTANT — how to open the app:
PasteNest is a menu-bar (LSUIElement) accessory app. It does not show a Dock icon. After launch, look at the right side of the menu bar for a stacked-square status item. Click it, or press Shift-Command-V, to open the bottom clipboard shelf. Press Option-Command-V to open the main window. Right-click the status item to Quit or open Settings.

1) Screen recording
The attached recording was captured on a physical Mac with the latest macOS. It begins with launching PasteNest from Spotlight, shows the menu-bar icon, the bottom shelf, copying text into history, search, the main window, favorites, and Settings.

This app has:
- No account registration, login, or account deletion (there is no user account system).
- No user-generated content from other people, and no social feed. History is only the signed-in Mac user’s own clipboard, stored locally. Reporting/blocking is not applicable.
- No In-App Purchase. PasteNest is a paid download (one-time purchase on the Mac App Store). After install, all features are unlocked. Payment is handled entirely by Apple. There is no paid content gate inside the app.

2) Purpose and target audience
PasteNest is a clipboard history manager for macOS 14+. Target audience: individuals and professionals who copy text, links, images, code, and files all day (developers, writers, designers, office users).

Problem: macOS keeps only the latest clipboard item, so previous copies are lost.
Value: the app sits in the menu bar, automatically saves copies, auto-tags them (link, code, image, color, file, etc.), lets the user search and pin/favorite items, and paste them again from a bottom shelf or main window. Optional iCloud sync (user’s own Apple ID) can share history across their Macs. Data stays on device unless the user turns on iCloud.

3) Setup and how to use main features
- No login credentials. No demo account. No sample files required.
- Launch PasteNest. If the library is empty, the app seeds a few harmless sample items (Apple Developer docs link, a SwiftUI snippet, a short Chinese note, a color hex, a product sentence) so Review can see the UI immediately.
- Click the menu-bar icon or press Shift-Command-V for the shelf; Option-Command-V for the main window; Shift-Command-D for optional region screenshot.
- Copy any text in another app; it appears in the shelf within about a second if “Listen to clipboard” is on (default).
- Command-F searches titles, body, source app, and tags.
- Double-click a card to view it; Return can paste. “Paste into another app” needs Accessibility permission (System Settings → Privacy & Security → Accessibility). History, search, and viewing work without that permission.
- Screenshots need Screen Recording permission. OCR uses Apple Vision on-device (Chinese and English). Neither permission is required for core history.
- Settings → Sync: “Sync via iCloud” is optional and off unless the user enables it. Local features work without iCloud.

4) External services used for core functionality
- Apple App Store commerce only (paid app download). No Stripe, no third-party payment SDK, no StoreKit IAP products.
- Optional Apple iCloud / CloudKit for syncing the user’s own history. The developer cannot read this data.
- On-device Apple frameworks only for intelligence: Vision (OCR), NaturalLanguage / NLContextualEmbedding (local search ranking). No cloud AI API, no analytics SDK, no ads, no third-party auth.

5) Regional differences
The app functions the same in all App Store regions. There is no geo-blocked content. The primary UI language is Simplified Chinese. Clipboard capture, search, favorites, screenshots, and optional iCloud work the same worldwide.

6) Regulated industry / protected material
PasteNest is a general productivity utility. It is not in a licensed/regulated industry (not finance, health, gambling, legal practice, transportation, etc.). It does not include protected third-party media catalogs. Sample items shown on first launch are original demo strings plus a public Apple Developer documentation URL. No extra credentials or licenses apply.

Please let us know if you need anything else. Thank you.
```

---

## 提交后

状态会回到 **Waiting for Review**。一般不必上传新构建。若 Resolution Center 还要你补视频清晰度或「找不到菜单栏图标」，按他们的下一封邮件再回即可。
