#!/usr/bin/env python3
"""背单词 app Mac App Store 上架营销截图生成器

基于用户提供的原始 app 截图, 不改动页面内容, 仅做:
  1. 方向修正 (02/04 源图为逆时针存储, 顺时针扶正)
  2. 清晰度增强 (2x 高质量放大 + 锐化)
  3. 套用 Mac App Store 营销版式 (深色背景 + macOS 窗口栏 + 主副标题 + 底部卖点)

输出:
  - source/enhanced/            增强后的高清截图
  - appstore/mac_2560x1600/     Mac App Store 上架截图 (2560x1600)
  - marketing/                  横幅 1920x1080 / 方形 1080x1080

用法: python3 generate_screenshots.py
依赖: Pillow, Noto Sans CJK SC 字体
"""

import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(BASE_DIR, "source")
ENH_DIR = os.path.join(SRC_DIR, "enhanced")

FONT_BOLD_PATH = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
FONT_REG_PATH = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
FONT_INDEX_SC = 2  # Noto Sans CJK SC 在 ttc 中的索引

# 深色主题配色 (参照营销样图), 绿色取自 app 界面主色
BG_TOP = (36, 38, 41)         # 背景顶部 深炭灰
BG_BOTTOM = (51, 53, 56)      # 背景底部 炭灰
TEXT_WHITE = (245, 243, 238)  # 主标题 暖白
GREEN_SUB = (94, 234, 113)    # 副标题 亮绿
GREEN_ICON = (52, 199, 89)    # 卖点图标绿
GRAY_DESC = (158, 161, 166)   # 卖点描述灰

APP_TITLE = None  # 窗口栏不显示应用名 (品牌名由用户自行决定)

# 每张截图的营销文案, 按 App Store 展示顺序排列
# rotate: 源图存储方向修正
SCREENS = [
    {
        "file": "01-home-wordbooks.png",
        "rotate": 0,
        "headline": "海量词书 随心切换",
        "sub": "小学到大学 · 新概念 · 同步教材全覆盖",
        "callouts": [("书", "全学段词书", "小学到大学 应有尽有"),
                     ("新", "持续更新", "热门词书不断上新")],
    },
    {
        "file": "02-word-card.png",
        "rotate": -90,
        "headline": "翻转卡片 高效记忆",
        "sub": "认识与否一键标记 · 智能规划学习",
        "callouts": [("卡", "翻转记忆", "看词忆义 加深印象"),
                     ("智", "智能安排", "熟悉程度自动规划")],
    },
    {
        "file": "03-word-detail.png",
        "rotate": 0,
        "headline": "词根短语 深度学习",
        "sub": "词根词缀 · 常用短语 · 经典例句",
        "callouts": [("词", "词根词缀", "构词规律巧记忆"),
                     ("句", "经典例句", "真实语境学用法")],
    },
    {
        "file": "04-vocab-test.png",
        "rotate": -90,
        "headline": "词汇量测试 精准评估",
        "sub": "几分钟快速测出真实词汇量",
        "callouts": [("测", "快速测试", "几分钟完成评估"),
                     ("准", "精准结果", "科学算法估算词量")],
    },
    {
        "file": "05-study-calendar.png",
        "rotate": 0,
        "headline": "每日打卡 见证坚持",
        "sub": "学习日历记录每一天的努力",
        "callouts": [("历", "学习日历", "每日打卡看得见"),
                     ("签", "补签机制", "偶尔漏签也不怕")],
    },
    {
        "file": "06-study-stats.png",
        "rotate": 0,
        "headline": "学习数据 一目了然",
        "sub": "单词 · 时长 · 连续天数 全维度统计",
        "callouts": [("统", "多维统计", "单词时长全记录"),
                     ("析", "图表分析", "学习趋势一目了然")],
    },
    {
        "file": "07-study-settings.png",
        "rotate": 0,
        "headline": "个性设置 自由定制",
        "sub": "学习量 · 发音 · 播放 由你掌控",
        "callouts": [("设", "灵活定制", "学习量自由调整"),
                     ("音", "英美发音", "自动播放磨耳朵")],
    },
    {
        "file": "08-profile.png",
        "rotate": 0,
        "headline": "生词掌握 全面管理",
        "sub": "生词本 · 已掌握 · 学习日历 一站管理",
        "callouts": [("生", "生词本", "难词集中攻克"),
                     ("熟", "已掌握", "熟词一目了然")],
    },
]


def font(path, size):
    return ImageFont.truetype(path, size, index=FONT_INDEX_SC)


def enhance_sources():
    """源图增强: 方向扶正 + 2x 放大 + 锐化, 输出到 source/enhanced/"""
    os.makedirs(ENH_DIR, exist_ok=True)
    for screen in SCREENS:
        src = Image.open(os.path.join(SRC_DIR, screen["file"])).convert("RGB")
        if screen.get("rotate"):
            src = src.rotate(screen["rotate"], expand=True)
        w, h = src.size
        up = src.resize((w * 2, h * 2), Image.LANCZOS)
        up = up.filter(ImageFilter.UnsharpMask(radius=2, percent=110, threshold=1))
        up = up.filter(ImageFilter.UnsharpMask(radius=1, percent=45, threshold=2))
        up.save(os.path.join(ENH_DIR, screen["file"]), "PNG")
        print(f"增强 {screen['file']}: {w}x{h} -> {up.width}x{up.height}")


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


def mac_window(capture, title=APP_TITLE):
    """给截图加 macOS 窗口标题栏 (红黄绿按钮, 可选居中标题)"""
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
    if title:
        title_f = font(FONT_REG_PATH, int(bar_h * 0.40))
        d.text((w / 2, bar_h / 2), title, font=title_f, fill=(90, 90, 92), anchor="mm")
    return win, radius


def decorate_background(bg, s):
    """深色背景装饰: 中部柔光 + 淡绿光晕 + 微细圆点"""
    w, h = bg.size
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([w * 0.16, h * 0.20, w * 0.84, h * 0.94], fill=(255, 255, 255, 13))
    gd.ellipse([w * 0.30, h * 0.34, w * 0.70, h * 0.78], fill=GREEN_SUB[:3] + (9,))
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
    """底部卖点: 绿色圆角图标字 + 白色标题 + 灰色描述, 两个并排居中"""
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
        ld.rounded_rectangle([x, y, x + icon_sz, y + icon_sz], 26 * s, fill=GREEN_ICON + (255,))
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


def load_enhanced(screen):
    return Image.open(os.path.join(ENH_DIR, screen["file"]))


def render_mac_screenshot(screen, out_path, canvas_w=2560, canvas_h=1600):
    """Mac App Store 横版截图 (2560x1600)"""
    s = canvas_w / 2560.0
    bg = vertical_gradient((canvas_w, canvas_h), BG_TOP, BG_BOTTOM).convert("RGBA")
    decorate_background(bg, s)
    draw = ImageDraw.Draw(bg)

    # 主标题 (白色) / 副标题 (亮绿)
    head_f = font(FONT_BOLD_PATH, int(116 * s))
    sub_f = font(FONT_REG_PATH, int(54 * s))
    tracking = 4 * s
    hw = tracked_width(draw, screen["headline"], head_f, tracking)
    draw_tracked(draw, ((canvas_w - hw) / 2, 108 * s), screen["headline"], head_f,
                 TEXT_WHITE, tracking)
    sw = draw.textlength(screen["sub"], font=sub_f)
    draw.text(((canvas_w - sw) / 2, 268 * s), screen["sub"], font=sub_f, fill=GREEN_SUB)

    # 增强后的界面截图 (不超过增强图原生尺寸, 保证清晰)
    src = load_enhanced(screen)
    max_w = 1900 * s
    max_h = 880 * s
    cw, ch = fit_size(src.width, src.height, max_w, max_h)
    shot = src.resize((cw, ch), Image.LANCZOS)
    card, radius = mac_window(shot)

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
    gd.ellipse([width * 0.55, height * 0.2, width * 0.98, height * 0.85], fill=GREEN_SUB[:3] + (12,))
    glow = glow.filter(ImageFilter.GaussianBlur(int(140 * s)))
    bg.alpha_composite(glow)
    draw = ImageDraw.Draw(bg)

    # 左侧文案 (功能导向, 不含品牌名)
    name_f = font(FONT_BOLD_PATH, int(150 * s))
    tag_f = font(FONT_REG_PATH, int(56 * s))
    li_f = font(FONT_REG_PATH, int(44 * s))
    x0 = 150 * s
    draw.text((x0, 200 * s), "高效背单词", font=name_f, fill=TEXT_WHITE)
    draw.text((x0, 400 * s), "海量词书 · 翻转卡片 · 词汇测试 · 打卡统计", font=tag_f, fill=GREEN_SUB)
    bullets = ["海量词书 · 小初高大学全覆盖", "翻转卡片 · 智能记忆",
               "词汇量测试 · 精准评估", "打卡统计 · 养成学习习惯"]
    by = 560 * s
    for b in bullets:
        draw.ellipse([x0 + 6 * s, by + 18 * s, x0 + 26 * s, by + 38 * s], fill=GREEN_SUB)
        draw.text((x0 + 56 * s, by), b, font=li_f, fill=(235, 233, 228))
        by += 92 * s

    # 右侧: 竖屏单词卡片 + 宽屏词书页 (增强图)
    card_img = load_enhanced(SCREENS[1])
    ch_ = int(880 * s)
    cw_ = int(card_img.width * ch_ / card_img.height)
    hero, _ = mac_window(card_img.resize((cw_, ch_), Image.LANCZOS))
    hero = hero.rotate(-4, expand=True, resample=Image.BICUBIC)

    home = load_enhanced(SCREENS[0])
    hw_ = int(800 * s)
    hh_ = int(home.height * hw_ / home.width)
    home_card, _ = mac_window(home.resize((hw_, hh_), Image.LANCZOS))
    home_card = home_card.rotate(3, expand=True, resample=Image.BICUBIC)

    paste_with_shadow(bg, hero, (int(width - hero.width - 150 * s), int(90 * s)), 40,
                      blur=int(44 * s), offset=(0, int(24 * s)))
    paste_with_shadow(bg, home_card, (int(width - hero.width - home_card.width - 60 * s),
                                      int(height - home_card.height - 90 * s)),
                      36, blur=int(40 * s), offset=(0, int(22 * s)))
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

    name_f = font(FONT_BOLD_PATH, int(110 * s))
    tag_f = font(FONT_REG_PATH, int(44 * s))
    nw = draw.textlength("高效背单词", font=name_f)
    draw.text(((size - nw) / 2, 90 * s), "高效背单词", font=name_f, fill=TEXT_WHITE)
    tw = draw.textlength("海量词书 · 智能记忆 · 打卡统计", font=tag_f)
    draw.text(((size - tw) / 2, 240 * s), "海量词书 · 智能记忆 · 打卡统计", font=tag_f, fill=GREEN_SUB)

    card_img = load_enhanced(SCREENS[1])
    ch_ = int(560 * s)
    cw_ = int(card_img.width * ch_ / card_img.height)
    card, radius = mac_window(card_img.resize((cw_, ch_), Image.LANCZOS))
    paste_with_shadow(bg, card, (int((size - card.width) / 2), int(350 * s)), radius,
                      blur=int(38 * s), offset=(0, int(20 * s)))

    pill_f = font(FONT_REG_PATH, int(32 * s))
    pills = ["海量词书", "智能记忆", "词汇测试", "打卡统计"]
    widths = [draw.textlength(t, font=pill_f) + 64 * s for t in pills]
    gap = 24 * s
    total = sum(widths) + gap * (len(pills) - 1)
    px, py = (size - total) / 2, 350 * s + card.height + 70 * s
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

    enhance_sources()

    for i, screen in enumerate(SCREENS, 1):
        name = f"{i:02d}-{os.path.splitext(screen['file'])[0]}.png"
        render_mac_screenshot(screen, os.path.join(out_mac, name))

    render_banner(os.path.join(out_mkt, "banner-1920x1080.png"), 1920, 1080)
    render_square(os.path.join(out_mkt, "square-1080x1080.png"), 1080)
    print("全部完成")


if __name__ == "__main__":
    main()
