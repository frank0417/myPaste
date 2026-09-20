#!/usr/bin/env python3
"""PasteNest Mac App Store 上架营销截图生成器

风格: 深色高级质感背景 + 白色主标题 + 品牌青绿副标题 + macOS 窗口/面板卡片 + 底部卖点
(参照用户提供的营销样图风格)

输入: source/ 下的 PasteNest UI 截图 (由 preview 页面高清截取)
输出:
  - appstore/mac_2560x1600/  Mac App Store 上架截图 (2560x1600)
  - marketing/banner-1920x1080.png / square-1080x1080.png

用法: python3 generate_screenshots.py
依赖: Pillow, Noto Sans CJK SC 字体
"""

import os
import re
from PIL import Image, ImageDraw, ImageFont, ImageFilter

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(BASE_DIR, "source")
APP_ICON = "/workspace/Paste/Paste/Resources/AppIcon-1024.png"  # 应用图标 (鸟巢)

FONT_BOLD_PATH = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
FONT_REG_PATH = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
FONT_INDEX_SC = 2  # Noto Sans CJK SC 在 ttc 中的索引

# 深色主题配色 (参照营销样图), 点缀色取自 PasteNest 品牌青绿
BG_TOP = (36, 38, 41)         # 背景顶部 深炭灰
BG_BOTTOM = (51, 53, 56)      # 背景底部 炭灰
TEXT_WHITE = (245, 243, 238)  # 主标题 暖白
ACCENT_SUB = (94, 234, 212)   # 副标题 亮青 (品牌 teal 提亮)
ACCENT_ICON = (15, 118, 110)  # 卖点图标 品牌青绿 #0F766E
CORAL = (224, 122, 95)        # 品牌珊瑚色 (辅助光晕)
GRAY_DESC = (158, 161, 166)   # 卖点描述灰

MAX_UPSCALE = 1.5  # 限制放大倍数, 保证清晰度

# Mac App Store 截图配置, 按展示顺序排列
# chrome: "window" 加 macOS 标题栏; "none" 保持原样 (面板/自带窗口栏/全屏)
SCREENS = [
    {
        "file": "01-main-window.png",
        "chrome": "window",
        "headline": "复制的一切 尽在掌握",
        "sub": "文本 · 链接 · 图片 · 代码 自动保存",
        "callouts": [("存", "自动保存", "复制即入库 永不丢失"),
                     ("类", "智能分类", "链接图片代码自动打标")],
    },
    {
        "file": "04-menubar-panel.png",
        "chrome": "none",
        "headline": "菜单栏常驻 一呼即出",
        "sub": "⇧⌘V 唤出面板 · 双击即刻粘贴",
        "callouts": [("快", "全局快捷键", "⇧⌘V 随手唤起"),
                     ("贴", "一键粘贴", "双击卡片即刻上屏")],
    },
    {
        "file": "02-search.png",
        "chrome": "window",
        "headline": "全文搜索 秒速定位",
        "sub": "标题 · 正文 · 来源应用 全部可搜",
        "callouts": [("搜", "全文搜索", "内容来源标签都能搜"),
                     ("准", "实时命中", "输入即显搜索结果")],
    },
    {
        "file": "03-filter-code.png",
        "chrome": "window",
        "headline": "智能分类 自动打标",
        "sub": "链接 · 颜色 · 代码 · 图片 按类型筛选",
        "callouts": [("类", "自动分类", "无需手动整理"),
                     ("板", "看板整理", "工作灵感各归其位")],
    },
    {
        "file": "06-screenshot-annotator.png",
        "chrome": "none",
        "headline": "截图标注 识别文字",
        "sub": "区域截图 · 画笔标注 · 本机识字",
        "callouts": [("截", "截图入库", "标注后同步进剪贴板"),
                     ("识", "本机识字", "Vision 识别中英文")],
    },
    {
        "file": "05-settings-hotkeys.png",
        "chrome": "none",
        "headline": "快捷键 自由定义",
        "sub": "面板 · 主窗口 · 截图 各有专属热键",
        "callouts": [("键", "自定义热键", "录下即刻生效"),
                     ("云", "iCloud 同步", "多台 Mac 共享历史")],
    },
]


def font(path, size):
    return ImageFont.truetype(path, size, index=FONT_INDEX_SC)


def vertical_gradient(size, top, bottom):
    w, h = size
    grad = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        grad.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return grad.resize((w, h))


def draw_tracked(draw, xy, text, fnt, fill, tracking=0):
    """绘制带字间距的文本, 返回总宽度"""
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=fnt, fill=fill)
        x += draw.textlength(ch, font=fnt) + tracking
    return x - xy[0] - tracking


def tracked_width(draw, text, fnt, tracking=0):
    return sum(draw.textlength(ch, font=fnt) for ch in text) + tracking * max(len(text) - 1, 0)


def rounded_image(img, radius):
    w, h = img.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius, fill=255)
    out.paste(img.convert("RGBA"), (0, 0), mask)
    return out


def paste_with_shadow(canvas, card, pos, radius, blur=48, offset=(0, 26), alpha=110):
    x, y = pos
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle([x + offset[0], y + offset[1],
                          x + card.width + offset[0], y + card.height + offset[1]],
                         radius, fill=(0, 0, 0, alpha))
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(card, (x, y))


def fit_size(src_w, src_h, max_w, max_h):
    scale = min(max_w / src_w, max_h / src_h)
    return int(src_w * scale), int(src_h * scale)


def mac_window(capture, title="PasteNest"):
    """给截图加 macOS 窗口标题栏 (红黄绿按钮 + 居中标题)"""
    w, h = capture.size
    bar_h = max(int(w * 0.030), 40)
    total_h = h + bar_h
    radius = max(int(w * 0.014), 16)
    win = Image.new("RGBA", (w, total_h), (0, 0, 0, 0))
    mask = Image.new("L", (w, total_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, total_h - 1], radius, fill=255)
    body = Image.new("RGBA", (w, total_h), (236, 236, 238, 255))
    body.paste(capture.convert("RGBA"), (0, bar_h))
    win.paste(body, (0, 0), mask)

    d = ImageDraw.Draw(win)
    dot_r = max(int(bar_h * 0.26), 8)
    dot_y = bar_h // 2
    dot_x0 = int(bar_h * 0.55)
    for i, color in enumerate([(255, 95, 87), (254, 188, 46), (40, 200, 64)]):
        cx = dot_x0 + i * int(dot_r * 2.8) + dot_r
        d.ellipse([cx - dot_r, dot_y - dot_r, cx + dot_r, dot_y + dot_r], fill=color)
    title_f = font(FONT_REG_PATH, int(bar_h * 0.40))
    d.text((w / 2, bar_h / 2), title, font=title_f, fill=(90, 90, 92), anchor="mm")
    return win, radius


def decorate_background(bg, s):
    """深色背景装饰: 中部柔光 + 青绿/珊瑚光晕 + 微细圆点"""
    w, h = bg.size
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([w * 0.16, h * 0.20, w * 0.84, h * 0.94], fill=(255, 255, 255, 13))
    gd.ellipse([w * 0.30, h * 0.34, w * 0.70, h * 0.78], fill=ACCENT_SUB[:3] + (9,))
    gd.ellipse([w * 0.60, h * 0.15, w * 0.95, h * 0.55], fill=CORAL + (7,))
    glow = glow.filter(ImageFilter.GaussianBlur(int(140 * s)))
    bg.alpha_composite(glow)
    deco = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(deco)
    for cx, cy, r, alpha in [(0.06, 0.12, 0.22, 6), (0.95, 0.30, 0.20, 5),
                             (0.08, 0.88, 0.24, 7), (0.92, 0.92, 0.18, 5)]:
        d.ellipse([w * (cx - r / 2), h * (cy - r / 2), w * (cx + r / 2), h * (cy + r / 2)],
                  fill=(255, 255, 255, alpha))
    bg.alpha_composite(deco)


def draw_callouts(draw, bg, callouts, canvas_w, y, s):
    """底部卖点: 青绿圆角图标字 + 白色标题 + 灰色描述, 两个并排居中"""
    icon_f = font(FONT_BOLD_PATH, int(46 * s))
    title_f = font(FONT_BOLD_PATH, int(42 * s))
    desc_f = font(FONT_REG_PATH, int(33 * s))
    icon_sz = 96 * s
    gap_icon_text = 26 * s

    items = []
    for char, title, desc in callouts:
        tw = max(draw.textlength(title, font=title_f), draw.textlength(desc, font=desc_f))
        items.append((char, title, desc, icon_sz + gap_icon_text + tw))
    gap_between = 84 * s
    total = sum(it[3] for it in items) + gap_between * (len(items) - 1)
    x = (canvas_w - total) / 2

    layer = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    for char, title, desc, wdt in items:
        ld.rounded_rectangle([x, y, x + icon_sz, y + icon_sz], 26 * s, fill=ACCENT_ICON + (255,))
        x += wdt + gap_between
    bg.alpha_composite(layer)

    x = (canvas_w - total) / 2
    for char, title, desc, wdt in items:
        draw.text((x + icon_sz / 2, y + icon_sz / 2), char, font=icon_f,
                  fill=(255, 255, 255), anchor="mm")
        tx = x + icon_sz + gap_icon_text
        draw.text((tx, y + 6 * s), title, font=title_f, fill=TEXT_WHITE)
        draw.text((tx, y + 56 * s), desc, font=desc_f, fill=GRAY_DESC)
        x += wdt + gap_between


def render_mac_screenshot(screen, out_path, canvas_w=2560, canvas_h=1600):
    """Mac App Store 横版截图 (2560x1600)"""
    s = canvas_w / 2560.0
    bg = vertical_gradient((canvas_w, canvas_h), BG_TOP, BG_BOTTOM).convert("RGBA")
    decorate_background(bg, s)
    draw = ImageDraw.Draw(bg)

    # 主标题 (白色) / 副标题 (亮青)
    head_f = font(FONT_BOLD_PATH, int(116 * s))
    sub_f = font(FONT_REG_PATH, int(54 * s))
    tracking = 4 * s
    hw = tracked_width(draw, screen["headline"], head_f, tracking)
    draw_tracked(draw, ((canvas_w - hw) / 2, 108 * s), screen["headline"], head_f,
                 TEXT_WHITE, tracking)
    sw = draw.textlength(screen["sub"], font=sub_f)
    draw.text(((canvas_w - sw) / 2, 268 * s), screen["sub"], font=sub_f, fill=ACCENT_SUB)

    # 界面截图
    src = Image.open(os.path.join(SRC_DIR, screen["file"]))
    max_w = 1900 * s
    max_h = 880 * s
    cw, ch = fit_size(src.width, src.height, max_w, max_h)
    if cw > src.width * MAX_UPSCALE:  # 限制放大, 保证清晰
        cw, ch = int(src.width * MAX_UPSCALE), int(src.height * MAX_UPSCALE)
    shot = src.resize((cw, ch), Image.LANCZOS)
    shot = shot.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))

    if screen["chrome"] == "window":
        card, radius = mac_window(shot)
    else:
        radius = max(int(cw * 0.03), 18)
        card = rounded_image(shot, radius)

    region_top, region_bot = 400 * s, 1300 * s
    card_x = int((canvas_w - card.width) / 2)
    card_y = int(region_top + (region_bot - region_top - card.height) * 0.5)
    paste_with_shadow(bg, card, (card_x, card_y), radius=radius,
                      blur=int(48 * s), offset=(0, int(26 * s)))

    # 底部卖点
    draw_callouts(draw, bg, screen["callouts"], canvas_w, 1380 * s, s * 1.1)

    bg.convert("RGB").save(out_path, "PNG")
    print("生成", out_path)


def render_banner(out_path, width, height):
    s = width / 1920.0
    bg = vertical_gradient((width, height), BG_TOP, BG_BOTTOM).convert("RGBA")
    glow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([width * 0.45, height * 0.05, width * 1.15, height * 1.0], fill=(255, 255, 255, 12))
    gd.ellipse([width * 0.55, height * 0.2, width * 0.98, height * 0.85], fill=ACCENT_SUB[:3] + (12,))
    glow = glow.filter(ImageFilter.GaussianBlur(int(140 * s)))
    bg.alpha_composite(glow)
    draw = ImageDraw.Draw(bg)

    # 左侧: 图标 + 名称 + 标语 + 特性
    name_f = font(FONT_BOLD_PATH, int(140 * s))
    tag_f = font(FONT_REG_PATH, int(54 * s))
    li_f = font(FONT_REG_PATH, int(42 * s))
    x0 = 150 * s
    icon = Image.open(APP_ICON).convert("RGBA").resize((int(180 * s), int(180 * s)), Image.LANCZOS)
    bg.alpha_composite(icon, (int(x0), int(150 * s)))
    draw.text((x0 + 210 * s, 190 * s), "PasteNest", font=name_f, fill=TEXT_WHITE)
    draw.text((x0 + 210 * s, 380 * s), "剪贴板历史，随手可取", font=tag_f, fill=ACCENT_SUB)
    bullets = ["自动保存 · 文本链接图片代码", "全文搜索 · 秒速定位",
               "截图标注 · 本机识字", "iCloud 同步 · 多台 Mac"]
    by = 640 * s
    for b in bullets:
        draw.ellipse([x0 + 6 * s, by + 16 * s, x0 + 26 * s, by + 36 * s], fill=ACCENT_SUB)
        draw.text((x0 + 56 * s, by), b, font=li_f, fill=(235, 233, 228))
        by += 88 * s

    # 右侧: 主窗口截图 (带窗口栏)
    main_shot = Image.open(os.path.join(SRC_DIR, "01-main-window.png"))
    mw = int(1080 * s)
    mh = int(main_shot.height * mw / main_shot.width)
    main_card, radius = mac_window(main_shot.resize((mw, mh), Image.LANCZOS))
    main_card = main_card.rotate(-2, expand=True, resample=Image.BICUBIC)
    paste_with_shadow(bg, main_card, (int(width - main_card.width - 130 * s), int(150 * s)),
                      radius, blur=int(44 * s), offset=(0, int(24 * s)))

    panel = Image.open(os.path.join(SRC_DIR, "04-menubar-panel.png"))
    pw = int(560 * s)
    ph = int(panel.height * pw / panel.width)
    panel_card = rounded_image(panel.resize((pw, ph), Image.LANCZOS), radius=int(28 * s))
    panel_card = panel_card.rotate(2, expand=True, resample=Image.BICUBIC)
    paste_with_shadow(bg, panel_card, (int(width - main_card.width - panel_card.width - 60 * s),
                                       int(height - panel_card.height - 100 * s)),
                      int(28 * s), blur=int(40 * s), offset=(0, int(22 * s)))
    bg.convert("RGB").save(out_path, "PNG")
    print("生成", out_path)


def render_square(out_path, size=1080):
    s = size / 1080.0
    bg = vertical_gradient((size, size), BG_TOP, BG_BOTTOM).convert("RGBA")
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([size * 0.12, size * 0.3, size * 0.88, size * 0.9],
                                 fill=(255, 255, 255, 12))
    glow = glow.filter(ImageFilter.GaussianBlur(int(110 * s)))
    bg.alpha_composite(glow)
    draw = ImageDraw.Draw(bg)

    name_f = font(FONT_BOLD_PATH, int(96 * s))
    tag_f = font(FONT_REG_PATH, int(42 * s))
    icon_sz = int(130 * s)
    icon = Image.open(APP_ICON).convert("RGBA").resize((icon_sz, icon_sz), Image.LANCZOS)
    nw = draw.textlength("PasteNest", font=name_f)
    total_w = icon_sz + 30 * s + nw
    ix = (size - total_w) / 2
    bg.alpha_composite(icon, (int(ix), int(80 * s)))
    draw.text((ix + icon_sz + 30 * s, 80 * s + icon_sz / 2), "PasteNest", font=name_f,
              fill=TEXT_WHITE, anchor="lm")
    tw = draw.textlength("剪贴板历史，随手可取", font=tag_f)
    draw.text(((size - tw) / 2, 260 * s), "剪贴板历史，随手可取", font=tag_f, fill=ACCENT_SUB)

    main_shot = Image.open(os.path.join(SRC_DIR, "01-main-window.png"))
    mw = int(880 * s)
    mh = int(main_shot.height * mw / main_shot.width)
    card, radius = mac_window(main_shot.resize((mw, mh), Image.LANCZOS))
    paste_with_shadow(bg, card, (int((size - card.width) / 2), int(360 * s)), radius,
                      blur=int(38 * s), offset=(0, int(20 * s)))

    pill_f = font(FONT_REG_PATH, int(32 * s))
    pills = ["自动保存", "全文搜索", "截图识字", "iCloud 同步"]
    widths = [draw.textlength(t, font=pill_f) + 64 * s for t in pills]
    gap = 24 * s
    total = sum(widths) + gap * (len(pills) - 1)
    px, py = (size - total) / 2, 360 * s + card.height + 60 * s
    ph = 68 * s
    layer = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    for t, wdt in zip(pills, widths):
        ld.rounded_rectangle([px, py, px + wdt, py + ph], ph / 2, fill=(255, 255, 255, 22))
        px += wdt + gap
    bg.alpha_composite(layer)
    px = (size - total) / 2
    for t, wdt in zip(pills, widths):
        draw.text((px + wdt / 2, py + ph / 2), t, font=pill_f, fill=TEXT_WHITE, anchor="mm")
        px += wdt + gap
    bg.convert("RGB").save(out_path, "PNG")
    print("生成", out_path)


def main():
    out_mac = os.path.join(BASE_DIR, "appstore", "mac_2560x1600")
    out_mkt = os.path.join(BASE_DIR, "marketing")
    for d in (out_mac, out_mkt):
        os.makedirs(d, exist_ok=True)

    for i, screen in enumerate(SCREENS, 1):
        base = re.sub(r"^\d+-", "", os.path.splitext(screen["file"])[0])
        render_mac_screenshot(screen, os.path.join(out_mac, f"{i:02d}-{base}.png"))

    render_banner(os.path.join(out_mkt, "banner-1920x1080.png"), 1920, 1080)
    render_square(os.path.join(out_mkt, "square-1080x1080.png"), 1080)
    print("全部完成")


if __name__ == "__main__":
    main()
