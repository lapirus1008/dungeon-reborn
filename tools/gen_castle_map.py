#!/usr/bin/env python3
"""클루조 성 지도 생성기: 큰 성(성벽·안뜰·본성·막사·창고) + 서쪽 숲 + 남서쪽 성당.

타일 문자 (godot/scripts/dungeon.gd _load_map 참고)
  #  벽/바위 (지나갈 수 없음)     .  성 안 실내 바닥
  ,  야외 (숲/안뜰, 천장 없음)    T  나무 (야외, 지나갈 수 없음)
  r  야외 폐허 기둥               c  성당 실내 바닥 (높은 천장)
  P  성당 기둥                    p  실내 기둥
실행: python3 tools/gen_castle_map.py  →  godot/assets/maps/clouseau_castle.json
"""
import json, random, os

W = H = 72
rnd = random.Random(1207)
g = [['#'] * W for _ in range(H)]


def fill(x0, z0, x1, z1, ch):
    for z in range(z0, z1 + 1):
        for x in range(x0, x1 + 1):
            g[z][x] = ch


def ring(x0, z0, x1, z1, ch='#'):
    for x in range(x0, x1 + 1):
        g[z0][x] = ch
        g[z1][x] = ch
    for z in range(z0, z1 + 1):
        g[z][x0] = ch
        g[z][x1] = ch


# 1) 전체를 숲(야외)으로
fill(1, 1, W - 2, H - 2, ',')

# 2) 성: 바깥 성벽 + 안뜰
CX0, CZ0, CX1, CZ1 = 34, 4, 69, 60
fill(CX0, CZ0, CX1, CZ1, ',')
ring(CX0, CZ0, CX1, CZ1)
fill(CX0, 30, CX0, 31, ',')           # 서쪽 정문
fill(50, CZ1, 51, CZ1, ',')            # 남쪽 뒷문


def building(x0, z0, x1, z1, floor='.'):
    fill(x0, z0, x1, z1, floor)
    ring(x0, z0, x1, z1)


def split(x0, z0, x1, z1, depth=0):
    """실내 사각형(벽 안쪽 좌표)을 재귀로 나눔. 칸막이 벽마다 2칸 문."""
    w, h = x1 - x0 + 1, z1 - z0 + 1
    if max(w, h) < 11 or depth > 4:
        return
    vertical = w > h if abs(w - h) > 2 else rnd.random() < 0.5
    if vertical:
        cut = rnd.randint(x0 + 4, x1 - 4)
        for z in range(z0, z1 + 1):
            g[z][cut] = '#'
        d = rnd.randint(z0, z1 - 1)
        g[d][cut] = g[d + 1][cut] = '.'
        if h > 12:  # 긴 벽은 문 하나 더
            d2 = rnd.randint(z0, z1 - 1)
            g[d2][cut] = g[d2 + 1][cut] = '.'
        split(x0, z0, cut - 1, z1, depth + 1)
        split(cut + 1, z0, x1, z1, depth + 1)
    else:
        cut = rnd.randint(z0 + 4, z1 - 4)
        for x in range(x0, x1 + 1):
            g[cut][x] = '#'
        d = rnd.randint(x0, x1 - 1)
        g[cut][d] = g[cut][d + 1] = '.'
        if w > 12:
            d2 = rnd.randint(x0, x1 - 1)
            g[cut][d2] = g[cut][d2 + 1] = '.'
        split(x0, z0, x1, cut - 1, depth + 1)
        split(x0, cut + 1, x1, z1, depth + 1)


# 본성 (큰 건물): 가운데 큰 홀은 남기고 나머지를 방으로
building(48, 13, 67, 49)
split(49, 14, 66, 24)            # 북쪽 방들
split(49, 38, 66, 48)            # 남쪽 방들
for x in range(49, 67):          # 큰 홀(25~37) 둘레 벽 + 문
    g[25][x] = '#'
    g[37][x] = '#'
for dx in (52, 60):
    g[25][dx] = g[25][dx + 1] = '.'
    g[37][dx] = g[37][dx + 1] = '.'
for z in (28, 34):               # 큰 홀 기둥 두 줄
    for x in range(51, 66, 3):
        g[z][x] = 'p'
fill(48, 30, 48, 32, '.')        # 서쪽 큰 문 (안뜰 → 큰 홀)
fill(56, 13, 57, 13, '.')        # 북쪽 문
fill(58, 49, 59, 49, '.')        # 남쪽 문
# 막사 / 창고 / 대장간
building(36, 6, 45, 14)
split(37, 7, 44, 13)
fill(40, 14, 41, 14, '.')
building(36, 47, 45, 58)
split(37, 48, 44, 57)
fill(40, 47, 41, 47, '.')
building(36, 22, 42, 27)
fill(42, 24, 42, 25, '.')

# 3) 성당 (십자형): 신랑(긴 홀) + 익랑 + 후진, 기둥 두 줄
fill(12, 46, 20, 66, 'c'); ring(12, 46, 20, 66)
fill(7, 51, 25, 55, 'c')
for x in range(7, 26):
    g[50][x] = '#' if not (13 <= x <= 19) else g[50][x]
    g[56][x] = '#' if not (13 <= x <= 19) else g[56][x]
for z in range(50, 57):
    g[z][6] = '#'
    g[z][26] = '#'
fill(13, 51, 19, 55, 'c')
fill(14, 43, 18, 46, 'c'); ring(13, 42, 19, 46); fill(14, 43, 18, 46, 'c')
fill(13, 46, 19, 46, 'c')         # 후진과 신랑 사이 열림
for z in range(48, 66, 2):
    if 50 <= z <= 56:
        continue
    g[z][14] = 'P'
    g[z][18] = 'P'
fill(15, 66, 17, 66, 'c')         # 남쪽 정문
fill(26, 53, 26, 53, 'c')         # 동쪽 옆문
fill(6, 53, 6, 53, 'c')           # 서쪽 옆문

# 4) 숲: 길과 빈터를 비우고 나무를 흩뿌림
clear = set()


def keep_clear(x, z, r=0):
    for dz in range(-r, r + 1):
        for dx in range(-r, r + 1):
            clear.add((x + dx, z + dz))


def path(points, r=1):
    for (ax, az), (bx, bz) in zip(points, points[1:]):
        x, z = ax, az
        while (x, z) != (bx, bz):
            keep_clear(x, z, r)
            if x != bx:
                x += 1 if bx > x else -1
            elif z != bz:
                z += 1 if bz > z else -1
        keep_clear(bx, bz, r)


path([(16, 67), (16, 69), (30, 69), (30, 31), (33, 31)])      # 성당 정문 → 성 정문
path([(27, 53), (30, 53)])                                       # 성당 옆문 → 길
path([(5, 53), (3, 53), (3, 30), (10, 30)])                      # 성당 서문 → 서쪽 숲
path([(10, 10), (22, 10), (22, 30), (30, 30)])                   # 북서 빈터 → 성 정문
path([(10, 10), (4, 4)])
path([(52, 61), (52, 69), (40, 69), (30, 69)])                   # 성 뒷문 → 남쪽 길
path([(30, 10), (30, 2), (60, 2), (70, 2)], 0)                   # 성 북쪽 바깥 길
for cx, cz, r in [(10, 10, 3), (20, 28, 2), (10, 36, 2), (26, 18, 2), (6, 22, 2)]:
    keep_clear(cx, cz, r)
# 북서 빈터의 폐허 기둥
for x, z in [(8, 8), (12, 8), (8, 12), (12, 12)]:
    g[z][x] = 'r'

forest = lambda x, z: not (CX0 <= x <= CX1 and CZ0 <= z <= CZ1) and not (5 <= x <= 27 and 41 <= z <= 67)
for z in range(1, H - 1):
    for x in range(1, W - 1):
        if g[z][x] != ',' or (x, z) in clear:
            continue
        if forest(x, z):
            if rnd.random() < 0.24:
                g[z][x] = 'T'
        elif CX0 < x < CX1 and CZ0 < z < CZ1 and rnd.random() < 0.025:
            g[z][x] = 'T'   # 안뜰에 드문드문 나무
# 성/성당 문 앞은 비움
for x, z in [(33, 30), (33, 31), (32, 30), (32, 31), (16, 67), (15, 67), (17, 67), (27, 53), (5, 53), (50, 61), (51, 61)]:
    if g[z][x] == 'T':
        g[z][x] = ','
# 성 바깥 성벽에 바로 붙은 나무는 치움 (벽을 따라 걸을 수 있게)
for z in range(1, H - 1):
    for x in range(1, W - 1):
        if g[z][x] == 'T' and any(g[z + dz][x + dx] in '.c' or (g[z + dz][x + dx] == '#' and (CX0 <= x + dx <= CX1 and CZ0 <= z + dz <= CZ1)) for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            g[z][x] = ','


def walk(ch):
    return ch in '.,c'


def near_walk(x, z):
    for r in range(0, 6):
        for dz in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if 0 < x + dx < W - 1 and 0 < z + dz < H - 1 and walk(g[z + dz][x + dx]):
                    return [x + dx, z + dz]
    return [x, z]


marks = {
    "spawns": [near_walk(x, z) for x, z in [(4, 4), (4, 26), (4, 44), (28, 4), (28, 66), (2, 69), (66, 8), (66, 56), (38, 30), (62, 66)]],
    "shrines": [near_walk(16, 44), near_walk(20, 28)],
    "stones": [near_walk(x, z) for x, z in [(10, 10), (40, 32), (58, 31), (16, 60), (30, 55)]],
    "exits": [near_walk(x, z) for x, z in [(6, 6), (66, 57), (24, 66)]],
}
decor = {
    # 성 모서리/정문 탑 (타일 좌표, 반지름 m, 높이 m)
    "towers": [[CX0, CZ0, 4.5, 20], [CX1, CZ0, 4.5, 20], [CX0, CZ1, 4.5, 20], [CX1, CZ1, 4.5, 20],
               [CX0, 28, 3.5, 16], [CX0, 33, 3.5, 16], [48, 13, 4.0, 26], [67, 13, 4.0, 26], [48, 49, 4.0, 26], [67, 49, 4.0, 26]],
    "keep": [48, 13, 67, 49],
    "curtain": [CX0, CZ0, CX1, CZ1],
    "cathedral": [12, 42, 20, 66],
    "transept": [6, 50, 26, 56],
    "spire": [16, 66],
    "wall_h": {"castle": 12.0, "keep": 16.0, "cathedral": 10.0},
    # 불빛: [x, z, 종류] — brazier 화로(바닥), chandelier 샹들리에(천장)
    "lights": [[36, 28, "brazier"], [36, 33, "brazier"], [46, 29, "brazier"], [46, 33, "brazier"], [52, 51, "brazier"], [44, 18, "brazier"],
               [54, 31, "chandelier"], [60, 31, "chandelier"], [16, 60, "chandelier"], [16, 53, "chandelier"], [16, 47, "chandelier"],
               [10, 10, "brazier"], [20, 28, "brazier"], [16, 69, "brazier"], [29, 31, "brazier"]],
}
out = {"name": "clouseau_castle", "w": W, "h": H, "rows": [''.join(r) for r in g], **marks, "decor": decor}
p = os.path.join(os.path.dirname(__file__), '..', 'godot', 'assets', 'maps', 'clouseau_castle.json')
json.dump(out, open(p, 'w'), ensure_ascii=False, indent=0)
print('ok', p)
