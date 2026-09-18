#!/usr/bin/env python3
"""好记英语 App Store 上架营销截图生成器

风格: 深色高级质感背景 + 白色主标题 + 品牌绿副标题 + 悬浮界面卡片 + 底部卖点
(参考用户提供的营销样图风格)

输出:
  - 6.5 英寸: 1242 x 2688
  - 6.9 英寸: 1320 x 2868 (App Store 必填)
  - 营销横幅 1920x1080 / 方形 1080x1080

用法: python3 generate_screenshots.py
依赖: Pillow, Noto Sans CJK SC 字体
"""

import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(BASE_DIR, "source")

FONT_BOLD_PATH = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
FONT_REG_PATH = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
FONT_INDEX_SC = 2  # Noto Sans CJK SC 在 ttc 中的索引

# 深色主题配色 (采样自参考营销图)
BG_TOP = (36, 38, 41)        # 背景顶部 深炭灰
BG_BOTTOM = (51, 53, 56)     # 背景底部 炭灰
TEXT_WHITE = (245, 243, 238)  # 主标题 暖白
GREEN_SUB = (94, 234, 113)   # 副标题 亮绿
GREEN_ICON = (52, 199, 89)   # 卖点图标绿
GRAY_DESC = (158, 161, 166)  # 卖点描述灰

MAX_UPSCALE = 1.5  # 限制放大倍数, 保证清晰度

# 每张截图的营销文案, 按 App Store 展示顺序排列
# rotate: 源图存储方向修正; callouts: 底部两个卖点 (图标字, 标题, 描述)
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


def rounded_card(img, radius):
    """圆角截图卡片"""
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


def decorate_background(bg, s):
    """深色背景装饰: 中部柔光 + 淡绿光晕 + 微细圆点"""
    w, h = bg.size
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([w * 0.10, h * 0.24, w * 0.90, h * 0.78], fill=(255, 255, 255, 14))
    gd.ellipse([w * 0.28, h * 0.34, w * 0.72, h * 0.68], fill=(94, 234, 113, 10))
    glow = glow.filter(ImageFilter.GaussianBlur(int(150 * s)))
    bg.alpha_composite(glow)
    deco = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(deco)
    for cx, cy, r, alpha in [(0.90, 0.08, 0.30, 7), (0.04, 0.26, 0.22, 6),
                             (0.95, 0.62, 0.18, 5), (0.08, 0.90, 0.26, 7)]:
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
        cw = draw.textlength(char, font=icon_f)
        draw.text((x + icon_sz / 2 - cw / 2, y + icon_sz / 2), char, font=icon_f,
                  fill=(255, 255, 255), anchor="mm")
        tx = x + icon_sz + gap_icon_text
        draw.text((tx, y + 6 * s), title, font=title_f, fill=TEXT_WHITE)
        draw.text((tx, y + 56 * s), desc, font=desc_f, fill=GRAY_DESC)
        x += wdt + gap_between


def render_screenshot(screen, canvas_w, canvas_h, out_path):
    s = canvas_w / 1242.0  # 缩放系数, 6.9 寸时约为 1.063
    bg = vertical_gradient((canvas_w, canvas_h), BG_TOP, BG_BOTTOM).convert("RGBA")
    decorate_background(bg, s)
    draw = ImageDraw.Draw(bg)

    # 主标题 (白色) / 副标题 (亮绿)
    head_f = font(FONT_BOLD_PATH, int(118 * s))
    sub_f = font(FONT_REG_PATH, int(52 * s))
    tracking = 4 * s
    hw = tracked_width(draw, screen["headline"], head_f, tracking)
    draw_tracked(draw, ((canvas_w - hw) / 2, 208 * s), screen["headline"], head_f,
                 TEXT_WHITE, tracking)
    sw = draw.textlength(screen["sub"], font=sub_f)
    draw.text(((canvas_w - sw) / 2, 396 * s), screen["sub"], font=sub_f, fill=GREEN_SUB)

    # 截图卡片 (先按存储方向扶正)
    src = Image.open(os.path.join(SRC_DIR, screen["file"]))
    if screen.get("rotate"):
        src = src.rotate(screen["rotate"], expand=True)
    aspect = src.width / src.height
    max_w = canvas_w - 2 * 56 * s
    if aspect >= 1.3:      # 宽窗口
        max_h = 820 * s
    elif aspect >= 0.75:   # 近方形竖屏窗口
        max_h = 1330 * s
    else:                  # 竖屏手机截图
        max_h = 1720 * s
    cw, ch = fit_size(src.width, src.height, max_w, max_h)
    if cw > src.width * MAX_UPSCALE:  # 限制放大, 保证清晰
        cw, ch = int(src.width * MAX_UPSCALE), int(src.height * MAX_UPSCALE)
    shot = src.resize((cw, ch), Image.LANCZOS)
    shot = shot.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
    card = rounded_card(shot, radius=int(48 * s))

    region_top, region_bot = 580 * s, 2250 * s
    card_x = int((canvas_w - card.width) / 2)
    card_y = int(region_top + (region_bot - region_top - card.height) * 0.5)
    paste_with_shadow(bg, card, (card_x, card_y), radius=int(56 * s),
                      blur=int(52 * s), offset=(0, int(30 * s)))

    # 底部卖点
    draw_callouts(draw, bg, screen["callouts"], canvas_w, 2360 * s, s)

    bg.convert("RGB").save(out_path, "PNG")
    print("生成", out_path)


def render_banner(out_path, width, height):
    s = width / 1920.0
    bg = vertical_gradient((width, height), BG_TOP, BG_BOTTOM).convert("RGBA")
    glow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([width * 0.45, height * 0.1, width * 1.1, height * 0.95], fill=(255, 255, 255, 13))
    gd.ellipse([width * 0.55, height * 0.25, width * 0.95, height * 0.8], fill=(94, 234, 113, 12))
    glow = glow.filter(ImageFilter.GaussianBlur(int(140 * s)))
    bg.alpha_composite(glow)
    draw = ImageDraw.Draw(bg)

    # 左侧文案
    name_f = font(FONT_BOLD_PATH, int(150 * s))
    tag_f = font(FONT_REG_PATH, int(56 * s))
    li_f = font(FONT_REG_PATH, int(44 * s))
    x0 = 150 * s
    draw.text((x0, 200 * s), "好记英语", font=name_f, fill=TEXT_WHITE)
    draw.text((x0, 400 * s), "让背单词更高效", font=tag_f, fill=GREEN_SUB)
    bullets = ["海量词书 · 小初高大学全覆盖", "翻转卡片 · 智能记忆曲线",
               "词汇量测试 · 精准评估", "打卡统计 · 养成学习习惯"]
    by = 560 * s
    for b in bullets:
        draw.ellipse([x0 + 6 * s, by + 18 * s, x0 + 26 * s, by + 38 * s], fill=GREEN_SUB)
        draw.text((x0 + 56 * s, by), b, font=li_f, fill=(235, 233, 228))
        by += 92 * s

    # 右侧截图组合 (竖屏单词卡片 + 宽屏词书页)
    card_img = Image.open(os.path.join(SRC_DIR, "02-word-card.png")).rotate(-90, expand=True)
    ch_ = int(880 * s)
    cw_ = int(card_img.width * ch_ / card_img.height)
    hero = rounded_card(card_img.resize((cw_, ch_), Image.LANCZOS), radius=int(44 * s))
    hero = hero.rotate(-4, expand=True, resample=Image.BICUBIC)

    home = Image.open(os.path.join(SRC_DIR, "01-home-wordbooks.png"))
    hw_ = int(800 * s)
    hh_ = int(home.height * hw_ / home.width)
    home_card = rounded_card(home.resize((hw_, hh_), Image.LANCZOS), radius=int(40 * s))
    home_card = home_card.rotate(3, expand=True, resample=Image.BICUBIC)

    paste_with_shadow(bg, hero, (int(width - hero.width - 150 * s), int(90 * s)), int(50 * s),
                      blur=int(44 * s), offset=(0, int(24 * s)))
    paste_with_shadow(bg, home_card, (int(width - hero.width - home_card.width - 60 * s),
                                      int(height - home_card.height - 90 * s)),
                      int(46 * s), blur=int(40 * s), offset=(0, int(22 * s)))
    bg.convert("RGB").save(out_path, "PNG")
    print("生成", out_path)


def render_square(out_path, size=1080):
    s = size / 1080.0
    bg = vertical_gradient((size, size), BG_TOP, BG_BOTTOM).convert("RGBA")
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([size * 0.15, size * 0.3, size * 0.85, size * 0.85],
                                 fill=(255, 255, 255, 12))
    glow = glow.filter(ImageFilter.GaussianBlur(int(110 * s)))
    bg.alpha_composite(glow)
    draw = ImageDraw.Draw(bg)

    name_f = font(FONT_BOLD_PATH, int(110 * s))
    tag_f = font(FONT_REG_PATH, int(44 * s))
    nw = draw.textlength("好记英语", font=name_f)
    draw.text(((size - nw) / 2, 90 * s), "好记英语", font=name_f, fill=TEXT_WHITE)
    tw = draw.textlength("让背单词更高效", font=tag_f)
    draw.text(((size - tw) / 2, 240 * s), "让背单词更高效", font=tag_f, fill=GREEN_SUB)

    card_img = Image.open(os.path.join(SRC_DIR, "02-word-card.png")).rotate(-90, expand=True)
    ch_ = int(560 * s)
    cw_ = int(card_img.width * ch_ / card_img.height)
    card = rounded_card(card_img.resize((cw_, ch_), Image.LANCZOS), radius=int(40 * s))
    paste_with_shadow(bg, card, (int((size - card.width) / 2), int(350 * s)), int(46 * s),
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
    out_65 = os.path.join(BASE_DIR, "appstore", "6.5-inch_1242x2688")
    out_69 = os.path.join(BASE_DIR, "appstore", "6.9-inch_1320x2868")
    out_mkt = os.path.join(BASE_DIR, "marketing")
    for d in (out_65, out_69, out_mkt):
        os.makedirs(d, exist_ok=True)

    for i, screen in enumerate(SCREENS, 1):
        name = f"{i:02d}-{os.path.splitext(screen['file'])[0]}.png"
        render_screenshot(screen, 1242, 2688, os.path.join(out_65, name))
        render_screenshot(screen, 1320, 2868, os.path.join(out_69, name))

    render_banner(os.path.join(out_mkt, "banner-1920x1080.png"), 1920, 1080)
    render_square(os.path.join(out_mkt, "square-1080x1080.png"), 1080)
    print("全部完成")


if __name__ == "__main__":
    main()
