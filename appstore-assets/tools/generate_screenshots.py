#!/usr/bin/env python3
"""好记英语 App Store 上架营销截图生成器

将原始 app 界面截图合成为符合 App Store 规范的营销截图:
  - 6.5 英寸: 1242 x 2688 (iPhone 11 Pro Max / XS Max 尺寸)
  - 6.9 英寸: 1320 x 2868 (iPhone 16 Pro Max 尺寸, App Store 必填)
以及营销横幅素材 (1920x1080 / 1080x1080)。

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

# 品牌色 (采样自 app 界面)
BRAND_TOP = (62, 193, 110)     # 渐变顶部亮绿
BRAND_BOTTOM = (14, 122, 60)   # 渐变底部深绿
WHITE = (255, 255, 255)

# 每张截图的营销文案, 按 App Store 展示顺序排列
# rotate: 源图存储方向修正 (部分截图为逆时针存储, 需顺时针旋转扶正)
SCREENS = [
    {
        "file": "01-home-wordbooks.png",
        "rotate": 0,
        "headline": "海量词书 随心切换",
        "sub": "小学到大学·新概念 同步教材全覆盖",
        "pills": ["同步教材", "覆盖全学段", "持续更新", "词库全面", "分类清晰", "即选即学"],
    },
    {
        "file": "02-word-card.png",
        "rotate": -90,
        "headline": "翻转卡片 高效记忆",
        "sub": "认识与否一键标记 智能规划学习",
        "pills": ["翻转卡片", "一键标记", "智能复习", "沉浸学习", "高效记忆", "轻松坚持"],
    },
    {
        "file": "03-word-detail.png",
        "rotate": 0,
        "headline": "词根短语 深度学习",
        "sub": "词根词缀·常用短语·经典例句",
        "pills": ["词根词缀", "常用短语", "经典例句", "学习笔记", "深度解析", "举一反三"],
    },
    {
        "file": "04-vocab-test.png",
        "rotate": -90,
        "headline": "词汇量测试 精准评估",
        "sub": "几分钟快速测出真实词汇量",
        "pills": ["快速测试", "精准评估", "科学算法", "动态出题", "结果可信", "因材施教"],
    },
    {
        "file": "05-study-calendar.png",
        "rotate": 0,
        "headline": "每日打卡 见证坚持",
        "sub": "学习日历记录每一天的努力",
        "pills": ["每日打卡", "补签卡", "习惯养成", "月度总览", "连续记录", "数据总结"],
    },
    {
        "file": "06-study-stats.png",
        "rotate": 0,
        "headline": "学习数据 一目了然",
        "sub": "单词·时长·连续天数 全维度统计",
        "pills": ["学习时长", "连续天数", "周期统计", "图表分析", "本周本月", "进步可见"],
    },
    {
        "file": "07-study-settings.png",
        "rotate": 0,
        "headline": "个性设置 自由定制",
        "sub": "学习量·发音·播放 由你掌控",
        "pills": ["学习量定制", "英美发音", "自动播放", "灵活调整", "贴心默认", "即刻生效"],
    },
    {
        "file": "08-profile.png",
        "rotate": 0,
        "headline": "生词掌握 全面管理",
        "sub": "生词本·已掌握·学习日历 一站管理",
        "pills": ["生词本", "已掌握", "学习日历", "我的词书", "学习统计", "词汇测试"],
    },
]

MAX_UPSCALE = 1.5  # 限制放大倍数, 保证清晰度


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


def rounded_card(img, radius, ring=0, ring_color=WHITE):
    """给截图加圆角和白色描边环"""
    w, h = img.size
    out = Image.new("RGBA", (w + ring * 2, h + ring * 2), (0, 0, 0, 0))
    mask = Image.new("L", out.size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, out.width - 1, out.height - 1], radius + ring, fill=255)
    if ring:
        ring_layer = Image.new("RGBA", out.size, ring_color + (255,))
        out.paste(ring_layer, (0, 0), mask)
    inner = Image.new("L", img.size, 0)
    di = ImageDraw.Draw(inner)
    di.rounded_rectangle([0, 0, w - 1, h - 1], radius, fill=255)
    out.paste(img.convert("RGBA"), (ring, ring), inner)
    return out


def paste_with_shadow(canvas, card, pos, radius, blur=48, offset=(0, 26), alpha=88):
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
    """背景装饰: 柔和光圈与半透明圆"""
    w, h = bg.size
    deco = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(deco)
    circles = [
        (0.86, 0.10, 0.34, 16), (0.06, 0.30, 0.26, 12),
        (0.94, 0.58, 0.22, 10), (0.10, 0.86, 0.30, 14),
        (0.70, 0.96, 0.26, 10),
    ]
    for cx, cy, r, alpha in circles:
        d.ellipse([w * (cx - r / 2), h * (cy - r / 2), w * (cx + r / 2), h * (cy + r / 2)],
                  fill=(255, 255, 255, alpha))
    # 中部柔光
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([w * 0.08, h * 0.30, w * 0.92, h * 0.86], fill=(255, 255, 255, 26))
    glow = glow.filter(ImageFilter.GaussianBlur(int(160 * s)))
    bg.alpha_composite(glow)
    bg.alpha_composite(deco)


def render_screenshot(screen, canvas_w, canvas_h, out_path):
    s = canvas_w / 1242.0  # 缩放系数, 6.9 寸时约为 1.063
    bg = vertical_gradient((canvas_w, canvas_h), BRAND_TOP, BRAND_BOTTOM).convert("RGBA")
    decorate_background(bg, s)
    draw = ImageDraw.Draw(bg)

    # 顶部品牌胶囊
    pill_f = font(FONT_REG_PATH, int(34 * s))
    pill_text = "好记英语 · 高效背单词"
    pw = draw.textlength(pill_text, font=pill_f)
    pill_w, pill_h = pw + 88 * s, 72 * s
    pill_x, pill_y = (canvas_w - pill_w) / 2, 148 * s
    pill_layer = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    ImageDraw.Draw(pill_layer).rounded_rectangle(
        [pill_x, pill_y, pill_x + pill_w, pill_y + pill_h], pill_h / 2,
        fill=(255, 255, 255, 30), outline=(255, 255, 255, 90), width=max(2, int(2 * s)))
    bg.alpha_composite(pill_layer)
    draw.text((canvas_w / 2 - pw / 2, pill_y + pill_h / 2), pill_text, font=pill_f,
              fill=(255, 255, 255, 235), anchor="lm")

    # 主标题 / 副标题
    head_f = font(FONT_BOLD_PATH, int(118 * s))
    sub_f = font(FONT_REG_PATH, int(50 * s))
    tracking = 4 * s
    hw = tracked_width(draw, screen["headline"], head_f, tracking)
    draw_tracked(draw, ((canvas_w - hw) / 2, 268 * s), screen["headline"], head_f, WHITE, tracking)
    sw = draw.textlength(screen["sub"], font=sub_f)
    draw.text(((canvas_w - sw) / 2, 452 * s), screen["sub"], font=sub_f, fill=(255, 255, 255, 215))

    # 截图卡片 (先按存储方向扶正)
    src = Image.open(os.path.join(SRC_DIR, screen["file"]))
    if screen.get("rotate"):
        src = src.rotate(screen["rotate"], expand=True)
    aspect = src.width / src.height
    max_w = canvas_w - 2 * 56 * s
    if aspect >= 1.3:      # 宽窗口
        max_h = 780 * s
    elif aspect >= 0.75:   # 近方形竖屏窗口
        max_h = 1300 * s
    else:                  # 竖屏手机截图
        max_h = 1700 * s
    scale_cap = MAX_UPSCALE
    cw, ch = fit_size(src.width, src.height, max_w, max_h)
    if cw > src.width * scale_cap:  # 限制放大, 保证清晰
        cw, ch = int(src.width * scale_cap), int(src.height * scale_cap)
    shot = src.resize((cw, ch), Image.LANCZOS)
    shot = shot.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
    ring = max(6, int(8 * s))
    card = rounded_card(shot, radius=int(44 * s), ring=ring)

    region_top, region_bot = 620 * s, canvas_h - 130 * s
    bias = 0.46 if aspect >= 1.3 else 0.5
    card_x = int((canvas_w - card.width) / 2)
    card_y = int(region_top + (region_bot - region_top - card.height) * bias)
    paste_with_shadow(bg, card, (card_x, card_y), radius=int(52 * s),
                      blur=int(46 * s), offset=(0, int(26 * s)))

    # 特性胶囊 (卡片下方, 宽屏截图放两排)
    pill2_f = font(FONT_REG_PATH, int(36 * s))
    pills = screen["pills"]
    rows = [pills[:3], pills[3:]] if aspect >= 1.3 else [pills[:3]]
    py = card_y + card.height + 92 * s
    for row in rows:
        if not row:
            continue
        widths = [draw.textlength(t, font=pill2_f) + 72 * s for t in row]
        gap = 28 * s
        total = sum(widths) + gap * (len(row) - 1)
        px = (canvas_w - total) / 2
        ph = 78 * s
        if py + ph > canvas_h - 60 * s:
            break
        layer = Image.new("RGBA", bg.size, (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        for t, wdt in zip(row, widths):
            ld.rounded_rectangle([px, py, px + wdt, py + ph], ph / 2, fill=(255, 255, 255, 26))
            px += wdt + gap
        bg.alpha_composite(layer)
        px = (canvas_w - total) / 2
        for t, wdt in zip(row, widths):
            draw.text((px + wdt / 2, py + ph / 2), t, font=pill2_f,
                      fill=(255, 255, 255, 230), anchor="mm")
            px += wdt + gap
        py += ph + 26 * s

    bg.convert("RGB").save(out_path, "PNG")
    print("生成", out_path)


def render_banner(out_path, width, height):
    s = width / 1920.0
    bg = vertical_gradient((width, height), BRAND_TOP, BRAND_BOTTOM).convert("RGBA")
    # 背景装饰
    deco = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    d = ImageDraw.Draw(deco)
    for cx, cy, r, a in [(0.92, 0.12, 0.40, 14), (0.55, 0.95, 0.30, 10), (0.05, 0.85, 0.24, 12)]:
        d.ellipse([width * (cx - r / 2), height * (cy - r / 2),
                   width * (cx + r / 2), height * (cy + r / 2)], fill=(255, 255, 255, a))
    bg.alpha_composite(deco)
    draw = ImageDraw.Draw(bg)

    # 左侧文案
    name_f = font(FONT_BOLD_PATH, int(150 * s))
    tag_f = font(FONT_REG_PATH, int(56 * s))
    li_f = font(FONT_REG_PATH, int(44 * s))
    x0 = 150 * s
    draw.text((x0, 200 * s), "好记英语", font=name_f, fill=WHITE)
    draw.text((x0, 400 * s), "让背单词更高效", font=tag_f, fill=(255, 255, 255, 225))
    bullets = ["海量词书 · 小初高大学全覆盖", "翻转卡片 · 智能记忆曲线",
               "词汇量测试 · 精准评估", "打卡统计 · 养成学习习惯"]
    by = 560 * s
    for b in bullets:
        draw.ellipse([x0 + 6 * s, by + 18 * s, x0 + 26 * s, by + 38 * s], fill=(255, 255, 255, 235))
        draw.text((x0 + 56 * s, by), b, font=li_f, fill=(255, 255, 255, 235))
        by += 92 * s

    # 右侧截图组合 (竖屏单词卡片 + 宽屏词书页)
    card_img = Image.open(os.path.join(SRC_DIR, "02-word-card.png")).rotate(-90, expand=True)
    ch_ = int(880 * s)
    cw_ = int(card_img.width * ch_ / card_img.height)
    hero = rounded_card(card_img.resize((cw_, ch_), Image.LANCZOS), radius=int(40 * s), ring=int(7 * s))
    hero = hero.rotate(-4, expand=True, resample=Image.BICUBIC)

    home = Image.open(os.path.join(SRC_DIR, "01-home-wordbooks.png"))
    hw_ = int(800 * s)
    hh_ = int(home.height * hw_ / home.width)
    home_card = rounded_card(home.resize((hw_, hh_), Image.LANCZOS), radius=int(40 * s), ring=int(7 * s))
    home_card = home_card.rotate(3, expand=True, resample=Image.BICUBIC)

    paste_with_shadow(bg, hero, (int(width - hero.width - 150 * s), int(90 * s)), int(46 * s),
                      blur=int(40 * s), offset=(0, int(22 * s)))
    paste_with_shadow(bg, home_card, (int(width - hero.width - home_card.width - 60 * s),
                                      int(height - home_card.height - 90 * s)),
                      int(46 * s), blur=int(40 * s), offset=(0, int(22 * s)))
    bg.convert("RGB").save(out_path, "PNG")
    print("生成", out_path)


def render_square(out_path, size=1080):
    s = size / 1080.0
    bg = vertical_gradient((size, size), BRAND_TOP, BRAND_BOTTOM).convert("RGBA")
    deco = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(deco)
    for cx, cy, r, a in [(0.9, 0.08, 0.36, 14), (0.08, 0.9, 0.3, 12)]:
        d.ellipse([size * (cx - r / 2), size * (cy - r / 2),
                   size * (cx + r / 2), size * (cy + r / 2)], fill=(255, 255, 255, a))
    bg.alpha_composite(deco)
    draw = ImageDraw.Draw(bg)

    name_f = font(FONT_BOLD_PATH, int(110 * s))
    tag_f = font(FONT_REG_PATH, int(44 * s))
    nw = draw.textlength("好记英语", font=name_f)
    draw.text(((size - nw) / 2, 90 * s), "好记英语", font=name_f, fill=WHITE)
    tw = draw.textlength("让背单词更高效", font=tag_f)
    draw.text(((size - tw) / 2, 240 * s), "让背单词更高效", font=tag_f, fill=(255, 255, 255, 225))

    card_img = Image.open(os.path.join(SRC_DIR, "02-word-card.png")).rotate(-90, expand=True)
    ch_ = int(560 * s)
    cw_ = int(card_img.width * ch_ / card_img.height)
    card = rounded_card(card_img.resize((cw_, ch_), Image.LANCZOS), radius=int(36 * s), ring=int(6 * s))
    paste_with_shadow(bg, card, (int((size - card.width) / 2), int(350 * s)), int(42 * s),
                      blur=int(36 * s), offset=(0, int(20 * s)))

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
        ld.rounded_rectangle([px, py, px + wdt, py + ph], ph / 2, fill=(255, 255, 255, 28))
        px += wdt + gap
    bg.alpha_composite(layer)
    px = (size - total) / 2
    for t, wdt in zip(pills, widths):
        draw.text((px + wdt / 2, py + ph / 2), t, font=pill_f, fill=(255, 255, 255, 235), anchor="mm")
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
