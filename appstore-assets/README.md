# PasteNest · Mac App Store 上架素材

基于 PasteNest（Mac 剪贴板管理工具）真实 UI 制作的 Mac App Store 上架截图与营销素材。
所有成品均为高清 PNG（RGB），可直接上传 App Store Connect。

## 目录结构

```
appstore-assets/
├── appstore/
│   └── mac_2560x1600/        # Mac App Store 上架截图（2560×1600 视网膜高清）
├── marketing/
│   ├── banner-1920x1080.png  # 营销横幅（官网 / 社交媒体 / 广告投放）
│   └── square-1080x1080.png  # 方形营销图（朋友圈 / 微博 / 小红书等）
├── source/                   # PasteNest UI 高清截图（由 preview 页面捕获）
└── tools/
    ├── capture_preview.js        # UI 截图捕获脚本（无头 Chrome 截取 preview 页面）
    └── generate_screenshots.py   # 营销素材生成脚本
```

## 上架截图清单（按展示顺序）

| 序号 | 界面 | 主标题 | 副标题 |
|---|---|---|---|
| 01 | 主窗口 | 复制的一切 尽在掌握 | 文本 · 链接 · 图片 · 代码 自动保存 |
| 02 | 菜单栏面板 | 菜单栏常驻 一呼即出 | ⇧⌘V 唤出面板 · 双击即刻粘贴 |
| 03 | 搜索状态 | 全文搜索 秒速定位 | 标题 · 正文 · 来源应用 全部可搜 |
| 04 | 分类筛选 | 智能分类 自动打标 | 链接 · 颜色 · 代码 · 图片 按类型筛选 |
| 05 | 截图标注 | 截图标注 识别文字 | 区域截图 · 画笔标注 · 本机识字 |
| 06 | 快捷键设置 | 快捷键 自由定义 | 面板 · 主窗口 · 截图 各有专属热键 |

对应 `docs/APP_STORE.md` 建议的截图清单（货架面板 / 搜索 / 标签筛选 / 设置），
并补充截图标注功能展示。

## 上传说明（Mac App Store）

1. App Store Connect → 我的 App → 选择版本 → 「App 预览和截屏」→ 选择 **Mac**。
2. 上传 `appstore/mac_2560x1600/` 中的 6 张，按文件名 01→06 顺序拖入。
3. Mac 截屏接受 1280×800 / 1440×900 / 2560×1600 / 2880×1800，本套采用
   2560×1600（视网膜高清），无需其他尺寸。
4. 文案（宣传文本 / 描述 / 关键词）见 `docs/APP_STORE.md` 第 2 节。

## 重新生成

```bash
# 1. 重新捕获 UI 截图 (需 Node + google-chrome + playwright-core)
cd tools && npm install playwright-core && node capture_preview.js

# 2. 重新生成营销素材 (需 Python + Pillow + Noto CJK 字体)
python3 tools/generate_screenshots.py
```

修改 `tools/generate_screenshots.py` 中的 `SCREENS` 配置即可调整文案、
截图顺序与底部卖点；主题色值在文件顶部常量区调整。
UI 截图来自 `Paste/preview/index.html` 交互预览页，界面更新后重新捕获即可。

## 设计说明

- 深色高级质感风格（参照营销样图）：炭灰渐变背景 + 柔光，白色主标题 +
  品牌青绿副标题（取自 PasteNest 品牌色 #0F766E 提亮），底部双卖点
  （青绿图标字 + 白色标题 + 灰色描述）。
- 主窗口截图带原生 macOS 窗口栏（红黄绿按钮 + 居中「PasteNest」标题）；
  菜单栏面板、设置窗口、全屏截图标注保持原始形态。
- 所有 UI 截图以 2x 设备像素比捕获（主窗口 2264×1162），合成时仅缩小
  或少量放大（≤1.5x）并锐化，保证视网膜清晰度。
