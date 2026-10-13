#!/usr/bin/env python3
"""인벤토리용 컬러 아이템 아이콘 -> godot/assets/icons/<아이템 id>.png

아이템이 차지하는 칸 크기(가로x세로)에 맞춘 그림 (칸당 64px). 4배로 그린 뒤 줄여서 가장자리를 매끈하게.
같은 종류라도 등급(rarity)에 따라 금속(녹슨 철 -> 철 -> 강철 -> 금장식)과 장식 색이 달라짐.
실행: 게임에서 아이템 목록을 뽑고 그림을 만든다
  godot --headless --path godot -- --dumpitems /tmp/items.json
  python3 tools/gen_icons.py /tmp/items.json
"""
import hashlib
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

CELL = 64
SS = 4  # 슈퍼샘플링 배율
OUT = os.path.join(os.path.dirname(__file__), "..", "godot", "assets", "icons")

# ---------------------------------------------------------------- 색
METALS = [  # 등급별 금속 (어두운, 중간, 밝은)
    ((70, 58, 48), (122, 104, 88), (170, 150, 128)),     # 0 녹슨 철
    ((78, 82, 88), (140, 146, 154), (210, 214, 220)),    # 1 철
    ((70, 84, 100), (150, 168, 188), (232, 238, 246)),   # 2 강철
    ((60, 74, 92), (140, 160, 186), (236, 242, 250)),    # 3 고급 강철
    ((40, 40, 50), (95, 95, 112), (190, 190, 210)),      # 4 흑철
    ((110, 78, 20), (205, 160, 55), (255, 232, 150)),    # 5 금
]
GOLD = ((120, 84, 18), (212, 166, 60), (255, 236, 160))
WOOD = ((60, 36, 18), (112, 72, 38), (162, 112, 64))
LEATHER = ((58, 34, 20), (118, 74, 42), (170, 120, 76))
GRIP = ((40, 24, 16), (82, 52, 32), (128, 88, 58))
GEMS = [(200, 30, 40), (40, 110, 220), (40, 170, 90), (150, 60, 200), (240, 170, 40), (220, 230, 240)]
CLOTHS = [((70, 20, 24), (140, 40, 44), (196, 84, 80)), ((24, 34, 70), (48, 70, 140), (96, 124, 196)),
          ((28, 56, 30), (56, 110, 60), (110, 166, 104)), ((60, 48, 30), (130, 110, 76), (190, 170, 130)),
          ((50, 26, 64), (100, 56, 128), (160, 110, 190))]


def seed_of(key):
    return int(hashlib.md5(key.encode()).hexdigest()[:8], 16)


def S(v):
    return v * SS


class Canvas:
    def __init__(self, w_cells, h_cells):
        self.W = w_cells * CELL * SS
        self.H = h_cells * CELL * SS
        self.img = Image.new("RGBA", (self.W, self.H), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def poly(self, pts, fill, outline=(18, 12, 8), width=S(2.2)):
        self.d.polygon(pts, fill=fill)
        if outline:
            self.d.line(pts + [pts[0]], fill=outline, width=int(width), joint="curve")

    def shaded_poly(self, pts, cols, axis=(1, 0), outline=(18, 12, 8)):
        """세 가지 색으로 한쪽은 어둡고 반대쪽은 밝게 (빛이 왼쪽 위에서)"""
        mask = Image.new("L", (self.W, self.H), 0)
        ImageDraw.Draw(mask).polygon(pts, fill=255)
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        grad = Image.new("RGBA", (self.W, self.H))
        gd = ImageDraw.Draw(grad)
        steps = 48
        ax, ay = axis
        for i in range(steps):
            k = i / (steps - 1)
            c = lerp3(cols[2], cols[1], cols[0], k)
            if ax:
                xa = x0 + (x1 - x0) * i / steps
                gd.rectangle([xa, y0, x0 + (x1 - x0) * (i + 1) / steps + 1, y1], fill=c + (255,))
            else:
                ya = y0 + (y1 - y0) * i / steps
                gd.rectangle([x0, ya, x1, y0 + (y1 - y0) * (i + 1) / steps + 1], fill=c + (255,))
        self.img.paste(grad, (0, 0), mask)
        if outline:
            self.d.line(pts + [pts[0]], fill=outline, width=int(S(2.2)), joint="curve")

    def ellipse(self, box, fill, outline=(18, 12, 8), width=S(2)):
        self.d.ellipse(box, fill=fill, outline=outline, width=int(width))

    def radial(self, cx, cy, r, inner, outer, outline=(18, 12, 8)):
        steps = 30
        for i in range(steps):
            k = i / (steps - 1)
            rr = r * (1 - k * 0.92)
            c = lerp(outer, inner, k)
            ox = -r * 0.25 * k
            self.d.ellipse([cx - rr + ox, cy - rr + ox, cx + rr + ox, cy + rr + ox], fill=c + (255,))
        if outline:
            self.d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=outline, width=int(S(2)))

    def line(self, pts, fill, width):
        self.d.line(pts, fill=fill, width=int(width), joint="curve")

    def glow(self, cx, cy, r, color, alpha=120):
        g = Image.new("RGBA", (self.W, self.H), (0, 0, 0, 0))
        ImageDraw.Draw(g).ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (alpha,))
        g = g.filter(ImageFilter.GaussianBlur(r * 0.5))
        self.img = Image.alpha_composite(self.img, g)
        self.d = ImageDraw.Draw(self.img)

    def save(self, path):
        # 그림자 한 겹 깔고 줄이기
        alpha = self.img.split()[3]
        sh = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
        sh.putalpha(alpha.point(lambda a: int(a * 0.55)))
        sh = sh.filter(ImageFilter.GaussianBlur(S(2)))
        base = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
        base.paste(sh, (int(S(2)), int(S(3))), sh)
        out = Image.alpha_composite(base, self.img)
        out = out.resize((self.W // SS, self.H // SS), Image.LANCZOS)
        out.save(path)


def lerp(a, b, k):
    return tuple(int(a[i] + (b[i] - a[i]) * k) for i in range(3))


def lerp3(a, b, c, k):
    return lerp(a, b, k * 2) if k < 0.5 else lerp(b, c, (k - 0.5) * 2)


def rot(pts, cx, cy, ang):
    ca, sa = math.cos(ang), math.sin(ang)
    return [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca) for x, y in pts]


# ---------------------------------------------------------------- 무기
def blade_weapon(c, r, kind, key):
    """검/장검/단검: 세로(약간 기울임)로 칼날-가드-손잡이-폼멜"""
    W, H = c.W, c.H
    metal = METALS[min(r, 5)]
    rnd = seed_of(key)
    cx = W / 2
    ang = 0.0 if kind != "longsword" else -0.32
    pad = H * 0.06
    total = H - pad * 2
    grip_l = total * (0.2 if kind == "longsword" else 0.17 if kind == "sword" else 0.26)
    blade_l = total - grip_l - total * 0.08
    bw = W * (0.17 if kind == "longsword" else 0.32 if kind == "sword" else 0.34) * (0.55 if kind == "longsword" else 1)
    if kind == "longsword":
        bw = W * 0.11
    top = pad
    guard_y = top + blade_l
    # 칼날
    blade = [(cx, top), (cx + bw / 2, top + bw * 1.2), (cx + bw / 2, guard_y), (cx - bw / 2, guard_y), (cx - bw / 2, top + bw * 1.2)]
    shapes = []
    shapes.append(("blade", blade))
    gw = bw * (3.6 if kind != "dagger" else 2.6) * (1.25 if kind == "longsword" else 1)
    gh = total * 0.045
    guard = [(cx - gw / 2, guard_y), (cx + gw / 2, guard_y), (cx + gw / 2 - gh * 0.5, guard_y + gh), (cx - gw / 2 + gh * 0.5, guard_y + gh)]
    gripw = bw * (0.55 if kind != "longsword" else 0.8)
    grip = [(cx - gripw / 2, guard_y + gh), (cx + gripw / 2, guard_y + gh), (cx + gripw / 2, guard_y + gh + grip_l), (cx - gripw / 2, guard_y + gh + grip_l)]
    pr = gripw * 0.95
    py = guard_y + gh + grip_l + pr * 0.7
    if ang:
        blade = rot(blade, cx, H / 2, ang)
        guard = rot(guard, cx, H / 2, ang)
        grip = rot(grip, cx, H / 2, ang)
        pcx, pcy = rot([(cx, py)], cx, H / 2, ang)[0]
    else:
        pcx, pcy = cx, py
    c.shaded_poly(blade, metal)
    # 칼날 가운데 홈(풀러)
    a, b = (cx, top + bw * 1.6), (cx, guard_y - bw * 0.3)
    if ang:
        a, b = rot([a, b], cx, H / 2, ang)
    c.line([a, b], metal[0] + (160,), S(1.6) * (1.6 if kind == "longsword" else 1))
    gcol = GOLD if r >= 3 else METALS[min(r, 5)]
    c.shaded_poly(guard, gcol, axis=(0, 1))
    c.shaded_poly(grip, GRIP)
    # 손잡이 감은 줄
    for k in range(1, 5):
        y = guard_y + gh + grip_l * k / 5
        p1, p2 = (cx - gripw / 2, y), (cx + gripw / 2, y - gripw * 0.4)
        if ang:
            p1, p2 = rot([p1, p2], cx, H / 2, ang)
        c.line([p1, p2], GRIP[0], S(1.4))
    c.radial(pcx, pcy, pr, gcol[2], gcol[0])
    if r >= 2:
        gem = GEMS[rnd % len(GEMS)]
        gx, gy = (cx, guard_y + gh / 2)
        if ang:
            gx, gy = rot([(gx, gy)], cx, H / 2, ang)[0]
        c.radial(gx, gy, gh * 0.75, lerp(gem, (255, 255, 255), 0.5), gem)


def mace(c, r, key):
    W, H = c.W, c.H
    metal = METALS[min(r, 5)]
    cx = W / 2
    hw = W * 0.14
    shaft = [(cx - hw / 2, H * 0.3), (cx + hw / 2, H * 0.3), (cx + hw / 2, H * 0.9), (cx - hw / 2, H * 0.9)]
    c.shaded_poly(shaft, WOOD if r < 2 else GRIP)
    c.shaded_poly([(cx - hw * 0.7, H * 0.78), (cx + hw * 0.7, H * 0.78), (cx + hw * 0.7, H * 0.92), (cx - hw * 0.7, H * 0.92)], GRIP)
    c.radial(cx, H * 0.95, hw * 0.6, metal[2], metal[0])
    # 머리: 플랜지 6개
    hy = H * 0.2
    hr = W * 0.36
    for k in range(6):
        a = k * math.pi / 3
        pts = [(cx, hy), (cx + math.cos(a - 0.25) * hr, hy + math.sin(a - 0.25) * hr * 0.9), (cx + math.cos(a) * hr * 1.08, hy + math.sin(a) * hr), (cx + math.cos(a + 0.25) * hr, hy + math.sin(a + 0.25) * hr * 0.9)]
        c.shaded_poly(pts, metal)
    c.radial(cx, hy, hr * 0.45, metal[2], metal[0])


def staff(c, r, key):
    W, H = c.W, c.H
    rnd = seed_of(key)
    gem = GEMS[rnd % len(GEMS)]
    ang = 0.22
    cx = W / 2
    sw = W * 0.09
    shaft = [(cx - sw / 2, H * 0.2), (cx + sw / 2, H * 0.2), (cx + sw / 2, H * 0.96), (cx - sw / 2, H * 0.96)]
    shaft = rot(shaft, cx, H / 2, ang)
    c.shaded_poly(shaft, WOOD)
    # 감긴 가죽
    for k in range(3):
        y = H * (0.55 + 0.04 * k)
        p1, p2 = rot([(cx - sw / 2, y), (cx + sw / 2, y - sw * 0.5)], cx, H / 2, ang)
        c.line([p1, p2], LEATHER[0], S(2))
    hx, hy = rot([(cx, H * 0.15)], cx, H / 2, ang)[0]
    c.glow(hx, hy, W * 0.32, gem, 110)
    # 갈퀴 같은 머리 장식
    prong = METALS[min(r, 5)] if r < 3 else GOLD
    for s in (-1, 1):
        pts = [(hx + s * W * 0.04, hy + H * 0.06), (hx + s * W * 0.2, hy - H * 0.02), (hx + s * W * 0.1, hy - H * 0.08), (hx + s * W * 0.02, hy + H * 0.0)]
        c.shaded_poly(pts, prong)
    c.radial(hx, hy, W * 0.13, lerp(gem, (255, 255, 255), 0.6), gem)


def crossbow(c, r, key):
    W, H = c.W, c.H
    cx = W / 2
    sw = W * 0.12
    c.shaded_poly([(cx - sw / 2, H * 0.12), (cx + sw / 2, H * 0.12), (cx + sw * 0.8, H * 0.92), (cx - sw * 0.8, H * 0.92)], WOOD)
    metal = METALS[min(r, 5)]
    # 활(프로드): 휘어진 판
    py = H * 0.24
    pts_top, pts_bot = [], []
    for k in range(21):
        t = k / 20
        x = W * 0.06 + (W * 0.88) * t
        y = py + math.sin(math.pi * t) * -H * 0.08
        pts_top.append((x, y - H * 0.02))
        pts_bot.append((x, y + H * 0.02))
    c.shaded_poly(pts_top + pts_bot[::-1], metal, axis=(0, 1))
    # 시위
    c.line([(W * 0.07, py), (cx, H * 0.48), (W * 0.93, py)], (220, 210, 190), S(1.6))
    # 방아쇠·볼트
    c.shaded_poly([(cx - sw * 0.25, H * 0.05), (cx + sw * 0.25, H * 0.05), (cx + sw * 0.25, H * 0.5), (cx - sw * 0.25, H * 0.5)], METALS[1])
    c.shaded_poly([(cx, H * 0.0 + S(4)), (cx + sw * 0.5, H * 0.07), (cx - sw * 0.5, H * 0.07)], METALS[2])
    c.shaded_poly([(cx + sw * 0.4, H * 0.6), (cx + sw * 1.1, H * 0.66), (cx + sw * 0.4, H * 0.7)], METALS[0])


SHIELD_PAINT = [((120, 24, 28), (230, 200, 80)), ((24, 50, 120), (230, 230, 230)), ((30, 90, 40), (230, 200, 80)),
                ((90, 60, 30), (200, 170, 120)), ((40, 40, 40), (200, 40, 40)), ((110, 30, 110), (230, 200, 80))]


def shield(c, r, key):
    W, H = c.W, c.H
    rnd = seed_of(key)
    base, accent = SHIELD_PAINT[rnd % len(SHIELD_PAINT)]
    if r <= 0:
        base, accent = (96, 66, 38), (140, 100, 60)
    pts = []
    for k in range(25):
        t = k / 24
        pts.append((W * 0.08 + W * 0.84 * t, H * 0.08 + math.sin(math.pi * t) * -H * 0.02))
    for k in range(25):
        t = k / 24
        x = W * 0.92 - W * 0.42 * (t ** 0.8)
        y = H * 0.08 + H * 0.84 * (t ** 1.25) if t < 1 else H * 0.92
        pts.append((x, H * 0.08 + (H * 0.84) * (1 - (1 - t) ** 1.6)))
    for k in range(25):
        t = k / 24
        pts.append((W * 0.5 - W * 0.42 * (t ** 1.25), H * 0.92 - H * 0.84 * (t ** 1.6)))
    c.shaded_poly(pts, (lerp(base, (0, 0, 0), 0.35), base, lerp(base, (255, 255, 255), 0.3)))
    # 문장: 세로 띠 / 십자 / 셰브론
    style = (rnd >> 4) % 3
    mask = Image.new("L", (c.W, c.H), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    layer = Image.new("RGBA", (c.W, c.H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    if r > 0:
        if style == 0:
            ld.rectangle([W * 0.42, 0, W * 0.58, H], fill=accent + (255,))
        elif style == 1:
            ld.rectangle([W * 0.43, 0, W * 0.57, H], fill=accent + (255,))
            ld.rectangle([0, H * 0.3, W, H * 0.4], fill=accent + (255,))
        else:
            ld.polygon([(0, H * 0.55), (W / 2, H * 0.25), (W, H * 0.55), (W, H * 0.68), (W / 2, H * 0.38), (0, H * 0.68)], fill=accent + (255,))
    else:
        for k in range(1, 4):
            ld.line([(W * k / 4, 0), (W * k / 4, H)], fill=(60, 40, 22, 255), width=int(S(2)))
    c.img.paste(layer, (0, 0), Image.composite(layer.split()[3], Image.new("L", (c.W, c.H), 0), mask))
    c.d = ImageDraw.Draw(c.img)
    rim = METALS[min(r, 5)] if r < 4 else GOLD
    c.line(pts + [pts[0]], rim[1], S(5))
    c.line(pts + [pts[0]], (18, 12, 8), S(1.6))
    c.radial(W / 2, H * 0.36, W * 0.1, rim[2], rim[0])


def orb(c, r, key):
    W, H = c.W, c.H
    gem = GEMS[seed_of(key) % len(GEMS)]
    c.shaded_poly([(W * 0.3, H * 0.8), (W * 0.7, H * 0.8), (W * 0.8, H * 0.94), (W * 0.2, H * 0.94)], GOLD if r >= 2 else METALS[1])
    c.glow(W / 2, H * 0.44, W * 0.42, gem, 120)
    c.radial(W / 2, H * 0.44, W * 0.3, lerp(gem, (255, 255, 255), 0.7), lerp(gem, (0, 0, 0), 0.3))
    c.ellipse([W * 0.36, H * 0.28, W * 0.46, H * 0.36], (255, 255, 255, 170), outline=None)


# ---------------------------------------------------------------- 방어구
def armor_cols(atype, r, key):
    if atype == "plate":
        return METALS[min(r + 1, 5)], "metal"
    if atype == "leather":
        return (lerp(LEATHER[0], (0, 0, 0), 0.1 * (r % 2)), LEATHER[1], LEATHER[2]), "leather"
    return CLOTHS[seed_of(key) % len(CLOTHS)], "cloth"


def helmet(c, r, atype, key):
    W, H = c.W, c.H
    cols, mat = armor_cols(atype, r, key)
    if mat == "cloth":
        # 두건
        pts = [(W * 0.5, H * 0.06), (W * 0.86, H * 0.4), (W * 0.9, H * 0.92), (W * 0.1, H * 0.92), (W * 0.14, H * 0.4)]
        c.shaded_poly(pts, cols)
        c.poly([(W * 0.3, H * 0.42), (W * 0.7, H * 0.42), (W * 0.66, H * 0.86), (W * 0.34, H * 0.86)], (16, 12, 10, 255))
        return
    # 투구 몸통 (dome은 오른쪽→위→왼쪽 순서라 아래 모서리는 왼쪽부터 이어야 꼬이지 않음)
    bottom = 0.92 if mat == "metal" else 0.72
    dome = [(W * 0.5 + math.cos(a) * W * 0.38, H * 0.5 - math.sin(a) * H * 0.42) for a in [i * math.pi / 20 for i in range(21)]]
    c.shaded_poly(dome + [(W * 0.13, H * bottom), (W * 0.87, H * bottom)], cols)
    if mat == "metal":
        c.poly([(W * 0.2, H * 0.46), (W * 0.8, H * 0.46), (W * 0.8, H * 0.55), (W * 0.2, H * 0.55)], (14, 12, 12, 255))  # 눈구멍
        c.poly([(W * 0.46, H * 0.55), (W * 0.54, H * 0.55), (W * 0.54, H * 0.84), (W * 0.46, H * 0.84)], (14, 12, 12, 255))  # 숨구멍
        c.line([(W * 0.5, H * 0.1), (W * 0.5, H * 0.44)], cols[2], S(3))
        for k in range(4):
            x = W * (0.24 + 0.17 * k)
            if abs(x - W * 0.5) < W * 0.08:
                continue
            for j in range(3):
                c.ellipse([x - S(2), H * (0.64 + 0.08 * j) - S(2), x + S(2), H * (0.64 + 0.08 * j) + S(2)], (12, 10, 10, 255), outline=None)
        if r >= 3:
            c.shaded_poly([(W * 0.46, H * 0.02), (W * 0.54, H * 0.02), (W * 0.6, H * 0.14), (W * 0.4, H * 0.14)], CLOTHS[0])
    else:
        # 가죽 모자: 아래 테두리 + 귀덮개
        c.shaded_poly([(W * 0.13, H * 0.66), (W * 0.87, H * 0.66), (W * 0.87, H * 0.76), (W * 0.13, H * 0.76)], LEATHER, axis=(0, 1))
        for x0 in (0.14, 0.72):
            c.shaded_poly([(W * x0, H * 0.74), (W * (x0 + 0.14), H * 0.74), (W * (x0 + 0.12), H * 0.95), (W * (x0 + 0.02), H * 0.95)], cols)
        for k in range(6):
            c.ellipse([W * (0.2 + 0.12 * k) - S(2), H * 0.71 - S(2), W * (0.2 + 0.12 * k) + S(2), H * 0.71 + S(2)], (200, 180, 140, 255), outline=None)


def chest_armor(c, r, atype, key):
    W, H = c.W, c.H
    cols, mat = armor_cols(atype, r, key)
    body = [(W * 0.3, H * 0.06), (W * 0.7, H * 0.06), (W * 0.96, H * 0.18), (W * 0.9, H * 0.46), (W * 0.78, H * 0.42),
            (W * 0.8, H * 0.94), (W * 0.2, H * 0.94), (W * 0.22, H * 0.42), (W * 0.1, H * 0.46), (W * 0.04, H * 0.18)]
    c.shaded_poly(body, cols)
    c.poly([(W * 0.38, H * 0.06), (W * 0.62, H * 0.06), (W * 0.5, H * 0.16)], (14, 10, 8, 255))  # 목
    if mat == "metal":
        for k in range(3):
            y = H * (0.56 + 0.12 * k)
            c.line([(W * 0.21, y), (W * 0.79, y)], cols[0], S(3))
        c.line([(W * 0.5, H * 0.16), (W * 0.5, H * 0.52)], cols[2], S(3))
        if r >= 3:
            c.line([(W * 0.22, H * 0.94), (W * 0.78, H * 0.94)], GOLD[1], S(5))
    elif mat == "leather":
        for k in range(5):
            y = H * (0.22 + 0.1 * k)
            c.line([(W * 0.46, y), (W * 0.54, y + H * 0.04)], (210, 190, 150), S(2))
            c.line([(W * 0.54, y), (W * 0.46, y + H * 0.04)], (210, 190, 150), S(2))
        c.line([(W * 0.2, H * 0.72), (W * 0.8, H * 0.72)], LEATHER[0], S(6))
        c.shaded_poly([(W * 0.45, H * 0.69), (W * 0.55, H * 0.69), (W * 0.55, H * 0.76), (W * 0.45, H * 0.76)], GOLD)
    else:
        c.line([(W * 0.5, H * 0.16), (W * 0.5, H * 0.94)], cols[0], S(3))
        c.line([(W * 0.22, H * 0.6), (W * 0.78, H * 0.6)], GOLD[1] if r >= 2 else cols[0], S(5))


def legs(c, r, atype, key):
    W, H = c.W, c.H
    cols, mat = armor_cols(atype, r, key)
    belt = [(W * 0.16, H * 0.04), (W * 0.84, H * 0.04), (W * 0.86, H * 0.14), (W * 0.14, H * 0.14)]
    left = [(W * 0.14, H * 0.14), (W * 0.49, H * 0.14), (W * 0.46, H * 0.95), (W * 0.18, H * 0.95)]
    right = [(W * 0.51, H * 0.14), (W * 0.86, H * 0.14), (W * 0.82, H * 0.95), (W * 0.54, H * 0.95)]
    c.shaded_poly(left, cols)
    c.shaded_poly(right, cols)
    c.shaded_poly(belt, LEATHER, axis=(0, 1))
    c.shaded_poly([(W * 0.45, H * 0.05), (W * 0.55, H * 0.05), (W * 0.55, H * 0.13), (W * 0.45, H * 0.13)], GOLD if r >= 2 else METALS[1])
    if mat == "metal":
        for x0 in (0.18, 0.56):
            c.radial(W * (x0 + 0.13), H * 0.55, W * 0.09, cols[2], cols[0])
            for k in range(3):
                y = H * (0.7 + 0.08 * k)
                c.line([(W * x0, y), (W * (x0 + 0.27), y)], cols[0], S(2.5))
    else:
        c.line([(W * 0.32, H * 0.16), (W * 0.32, H * 0.94)], cols[0], S(1.6))
        c.line([(W * 0.68, H * 0.16), (W * 0.68, H * 0.94)], cols[0], S(1.6))


def gloves(c, r, atype, key):
    W, H = c.W, c.H
    cols, mat = armor_cols(atype, r, key)
    for s, x0 in ((1, 0.06), (-1, 0.52)):
        cuff = [(W * x0, H * 0.62), (W * (x0 + 0.4), H * 0.62), (W * (x0 + 0.42), H * 0.94), (W * (x0 - 0.02), H * 0.94)]
        palm = [(W * (x0 + 0.02), H * 0.3), (W * (x0 + 0.38), H * 0.3), (W * (x0 + 0.38), H * 0.64), (W * (x0 + 0.02), H * 0.64)]
        c.shaded_poly(palm, cols)
        for k in range(4):
            fx = W * (x0 + 0.04 + 0.085 * k)
            c.shaded_poly([(fx, H * (0.1 + 0.03 * abs(k - 1.5))), (fx + W * 0.07, H * (0.1 + 0.03 * abs(k - 1.5))), (fx + W * 0.07, H * 0.32), (fx, H * 0.32)], cols)
        thumb_x = x0 + (0.38 if s > 0 else 0.02)
        c.shaded_poly([(W * thumb_x, H * 0.4), (W * (thumb_x + 0.1 * s), H * 0.32), (W * (thumb_x + 0.12 * s), H * 0.4), (W * thumb_x, H * 0.55)], cols)
        c.shaded_poly(cuff, cols if mat != "cloth" else LEATHER)
        if mat == "metal":
            for k in range(3):
                c.line([(W * (x0 + 0.02), H * (0.38 + 0.08 * k)), (W * (x0 + 0.38), H * (0.38 + 0.08 * k))], cols[0], S(2))


def boots(c, r, atype, key):
    W, H = c.W, c.H
    cols, mat = armor_cols(atype, r, key)
    if mat == "cloth":
        cols = LEATHER
    for x0 in (0.04, 0.5):
        shaft = [(W * (x0 + 0.06), H * 0.08), (W * (x0 + 0.3), H * 0.08), (W * (x0 + 0.3), H * 0.7), (W * (x0 + 0.06), H * 0.7)]
        foot = [(W * (x0 + 0.06), H * 0.62), (W * (x0 + 0.3), H * 0.62), (W * (x0 + 0.44), H * 0.78), (W * (x0 + 0.44), H * 0.92), (W * (x0 + 0.04), H * 0.92)]
        c.shaded_poly(shaft, cols)
        c.shaded_poly(foot, cols)
        c.line([(W * (x0 + 0.04), H * 0.92), (W * (x0 + 0.44), H * 0.92)], (20, 14, 10), S(5))
        c.line([(W * (x0 + 0.06), H * 0.16), (W * (x0 + 0.3), H * 0.16)], cols[0], S(4))
        if mat == "metal":
            c.radial(W * (x0 + 0.18), H * 0.4, W * 0.07, cols[2], cols[0])


# ---------------------------------------------------------------- 장신구·소모품·보물
def ring(c, r, key):
    W, H = c.W, c.H
    gem = GEMS[seed_of(key) % len(GEMS)]
    c.d.ellipse([W * 0.18, H * 0.3, W * 0.82, H * 0.9], outline=GOLD[0], width=int(S(10)))
    c.d.ellipse([W * 0.2, H * 0.32, W * 0.8, H * 0.88], outline=GOLD[1], width=int(S(6)))
    c.d.arc([W * 0.22, H * 0.34, W * 0.78, H * 0.86], 190, 300, fill=GOLD[2], width=int(S(3)))
    c.glow(W / 2, H * 0.28, W * 0.2, gem, 100)
    c.radial(W / 2, H * 0.28, W * 0.16, lerp(gem, (255, 255, 255), 0.6), gem)


def necklace(c, r, key):
    W, H = c.W, c.H
    gem = GEMS[seed_of(key) % len(GEMS)]
    for k in range(19):
        a = math.pi * k / 18
        x = W / 2 - math.cos(a) * W * 0.4
        y = H * 0.12 + math.sin(a) * H * 0.4
        c.ellipse([x - S(3.2), y - S(3.2), x + S(3.2), y + S(3.2)], GOLD[1] + (255,), outline=GOLD[0], width=S(1))
    c.shaded_poly([(W * 0.5, H * 0.5), (W * 0.66, H * 0.66), (W * 0.5, H * 0.94), (W * 0.34, H * 0.66)], GOLD)
    c.radial(W / 2, H * 0.69, W * 0.1, lerp(gem, (255, 255, 255), 0.6), gem)


FLASKS = {"health_potion": (200, 30, 40), "fire_flask": (240, 110, 20), "rock_flask": (130, 100, 60),
          "lightning_flask": (70, 150, 250), "mimic_flask": (150, 60, 200), "protection_flask": (230, 190, 60)}


def flask(c, key):
    W, H = c.W, c.H
    col = FLASKS.get(key, (200, 40, 60))
    round_ = key == "health_potion"
    # 병목·코르크
    c.shaded_poly([(W * 0.4, H * 0.12), (W * 0.6, H * 0.12), (W * 0.6, H * 0.34), (W * 0.4, H * 0.34)], ((150, 170, 180), (200, 220, 230), (240, 250, 255)))
    c.shaded_poly([(W * 0.38, H * 0.02), (W * 0.62, H * 0.02), (W * 0.6, H * 0.14), (W * 0.4, H * 0.14)], WOOD)
    if round_:
        c.glow(W / 2, H * 0.64, W * 0.36, col, 90)
        c.radial(W / 2, H * 0.64, W * 0.32, lerp(col, (255, 255, 255), 0.45), lerp(col, (0, 0, 0), 0.35))
    else:
        body = [(W * 0.4, H * 0.32), (W * 0.6, H * 0.32), (W * 0.84, H * 0.7), (W * 0.8, H * 0.94), (W * 0.2, H * 0.94), (W * 0.16, H * 0.7)]
        c.glow(W / 2, H * 0.7, W * 0.36, col, 80)
        c.shaded_poly(body, (lerp(col, (0, 0, 0), 0.4), col, lerp(col, (255, 255, 255), 0.45)))
        if key == "lightning_flask":
            c.line([(W * 0.5, H * 0.5), (W * 0.42, H * 0.68), (W * 0.56, H * 0.7), (W * 0.46, H * 0.88)], (255, 255, 220), S(3))
        elif key == "fire_flask":
            c.shaded_poly([(W * 0.5, H * 0.52), (W * 0.62, H * 0.78), (W * 0.5, H * 0.88), (W * 0.38, H * 0.78)], ((200, 60, 10), (255, 170, 40), (255, 240, 160)), outline=None)
    c.ellipse([W * 0.32, H * 0.5, W * 0.42, H * 0.62], (255, 255, 255, 150), outline=None)


def bandage(c):
    W, H = c.W, c.H
    cloth = ((170, 160, 140), (225, 215, 195), (250, 245, 232))
    c.shaded_poly([(W * 0.14, H * 0.3), (W * 0.86, H * 0.3), (W * 0.86, H * 0.8), (W * 0.14, H * 0.8)], cloth)
    c.ellipse([W * 0.62, H * 0.3, W * 0.98, H * 0.8], cloth[1] + (255,))
    c.ellipse([W * 0.72, H * 0.44, W * 0.88, H * 0.66], (150, 140, 120, 255))
    c.line([(W * 0.14, H * 0.5), (W * 0.02, H * 0.9)], cloth[2], S(6))
    c.line([(W * 0.4, H * 0.3), (W * 0.36, H * 0.8)], (200, 60, 60), S(3))


def torch(c):
    W, H = c.W, c.H
    c.shaded_poly([(W * 0.4, H * 0.3), (W * 0.6, H * 0.3), (W * 0.56, H * 0.96), (W * 0.44, H * 0.96)], WOOD)
    c.shaded_poly([(W * 0.32, H * 0.22), (W * 0.68, H * 0.22), (W * 0.62, H * 0.36), (W * 0.38, H * 0.36)], ((80, 70, 60), (150, 140, 120), (200, 190, 170)))
    c.glow(W / 2, H * 0.15, W * 0.4, (255, 140, 30), 120)
    c.shaded_poly([(W * 0.5, H * 0.0 + S(2)), (W * 0.7, H * 0.16), (W * 0.62, H * 0.24), (W * 0.38, H * 0.24), (W * 0.3, H * 0.16)], ((220, 70, 10), (255, 160, 30), (255, 240, 150)), outline=None)


def bolts(c):
    W, H = c.W, c.H
    for k, dx in enumerate((-0.18, 0.0, 0.18)):
        x = W * (0.5 + dx)
        c.line([(x, H * 0.12), (x + W * 0.04 * (k - 1), H * 0.9)], WOOD[1], S(4))
        c.shaded_poly([(x, H * 0.02), (x + W * 0.08, H * 0.12), (x - W * 0.08, H * 0.12)], METALS[1])
        c.shaded_poly([(x - W * 0.08, H * 0.8), (x + W * 0.08, H * 0.8), (x + W * 0.04, H * 0.92), (x - W * 0.04, H * 0.92)], ((140, 30, 30), (200, 50, 40), (240, 120, 100)))
    c.line([(W * 0.2, H * 0.55), (W * 0.8, H * 0.55)], LEATHER[1], S(5))


def treasure(c, key, r):
    W, H = c.W, c.H
    if key == "gold_coins":
        for i, (x, y) in enumerate([(0.36, 0.66), (0.62, 0.68), (0.5, 0.48), (0.32, 0.4), (0.66, 0.42)]):
            c.ellipse([W * (x - 0.2), H * (y - 0.14), W * (x + 0.2), H * (y + 0.14)], GOLD[1] + (255,), outline=GOLD[0], width=S(2))
            c.ellipse([W * (x - 0.12), H * (y - 0.08), W * (x + 0.12), H * (y + 0.08)], GOLD[2] + (255,), outline=None)
    elif key in ("ruby", "sapphire"):
        col = (210, 30, 50) if key == "ruby" else (40, 90, 230)
        c.glow(W / 2, H / 2, W * 0.4, col, 110)
        pts = [(W * 0.5, H * 0.08), (W * 0.86, H * 0.4), (W * 0.5, H * 0.92), (W * 0.14, H * 0.4)]
        c.shaded_poly(pts, (lerp(col, (0, 0, 0), 0.4), col, lerp(col, (255, 255, 255), 0.6)))
        c.line([(W * 0.14, H * 0.4), (W * 0.86, H * 0.4)], lerp(col, (255, 255, 255), 0.4), S(2))
        c.line([(W * 0.5, H * 0.08), (W * 0.36, H * 0.4), (W * 0.5, H * 0.92)], lerp(col, (255, 255, 255), 0.3), S(1.5))
    elif key == "golden_crown":
        pts = [(W * 0.1, H * 0.8), (W * 0.1, H * 0.3), (W * 0.3, H * 0.52), (W * 0.5, H * 0.2), (W * 0.7, H * 0.52), (W * 0.9, H * 0.3), (W * 0.9, H * 0.8)]
        c.shaded_poly(pts, GOLD)
        for i, x in enumerate((0.25, 0.5, 0.75)):
            c.radial(W * x, H * 0.68, W * 0.06, (255, 220, 220), GEMS[i])
    elif key == "silver_goblet":
        s = ((110, 110, 120), (190, 190, 200), (245, 245, 250))
        c.shaded_poly([(W * 0.2, H * 0.08), (W * 0.8, H * 0.08), (W * 0.66, H * 0.48), (W * 0.34, H * 0.48)], s)
        c.shaded_poly([(W * 0.45, H * 0.48), (W * 0.55, H * 0.48), (W * 0.55, H * 0.8), (W * 0.45, H * 0.8)], s)
        c.shaded_poly([(W * 0.28, H * 0.8), (W * 0.72, H * 0.8), (W * 0.76, H * 0.92), (W * 0.24, H * 0.92)], s)
        c.radial(W / 2, H * 0.28, W * 0.07, (255, 200, 200), GEMS[0])
    elif key == "dragon_heart":
        col = (180, 20, 30)
        c.glow(W / 2, H / 2, W * 0.45, (255, 80, 30), 130)
        pts = [(W * 0.5, H * 0.9), (W * 0.14, H * 0.5), (W * 0.2, H * 0.2), (W * 0.4, H * 0.14), (W * 0.5, H * 0.26), (W * 0.6, H * 0.14), (W * 0.8, H * 0.2), (W * 0.86, H * 0.5)]
        c.shaded_poly(pts, (lerp(col, (0, 0, 0), 0.5), col, (255, 120, 80)))
    else:  # ancient_relic 등
        stone = ((70, 76, 70), (120, 130, 118), (180, 190, 176))
        c.shaded_poly([(W * 0.3, H * 0.06), (W * 0.7, H * 0.06), (W * 0.82, H * 0.94), (W * 0.18, H * 0.94)], stone)
        c.glow(W / 2, H * 0.45, W * 0.25, (90, 230, 200), 140)
        c.line([(W * 0.4, H * 0.3), (W * 0.6, H * 0.45), (W * 0.42, H * 0.6), (W * 0.58, H * 0.75)], (120, 255, 220), S(3))


def draw(key, info):
    w, h = info["size"]
    c = Canvas(int(w), int(h))
    slot, cat, r = info["slot"], info["cat"], int(info.get("rarity", 0) or 0)
    if slot == "weapon":
        if cat in ("sword", "longsword", "dagger"):
            blade_weapon(c, r, cat, key)
        elif cat == "mace":
            mace(c, r, key)
        elif cat == "staff":
            staff(c, r, key)
        elif cat == "crossbow":
            crossbow(c, r, key)
        elif cat == "shield":
            shield(c, r, key)
        elif cat == "orb":
            orb(c, r, key)
        else:
            blade_weapon(c, r, "sword", key)
    elif slot == "head":
        helmet(c, r, cat, key)
    elif slot == "chest":
        chest_armor(c, r, cat, key)
    elif slot == "legs":
        legs(c, r, cat, key)
    elif slot == "hands":
        gloves(c, r, cat, key)
    elif slot == "feet":
        boots(c, r, cat, key)
    elif slot == "ring":
        ring(c, r, key)
    elif slot == "necklace":
        necklace(c, r, key)
    elif slot == "consumable":
        bandage(c) if key == "bandage" else flask(c, key)
    elif slot == "torch":
        torch(c)
    elif slot == "ammo":
        bolts(c)
    else:
        treasure(c, key, r)
    return c


if __name__ == "__main__":
    items = json.load(open(sys.argv[1]))
    os.makedirs(OUT, exist_ok=True)
    for key, info in items.items():
        draw(key, info).save(os.path.join(OUT, key + ".png"))
    print("wrote", len(items), "icons to", os.path.abspath(OUT))
