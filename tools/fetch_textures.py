#!/usr/bin/env python3
"""Poly Haven(CC0) 사진 기반 재질을 받아 godot/assets/textures/<자리>/ 에 넣음.
자리 이름은 godot/scripts/dungeon.gd 가 Textures.pick() 으로 찾는 이름과 같음.
실행: python3 tools/fetch_textures.py  (polyhaven.com 접속 필요)"""
import json, os, urllib.request

SLOTS = {
    "wall": "castle_brick_07",          # 성벽/실내 벽
    "floor": "cobblestone_floor_04",     # 실내 바닥
    "ceiling": "dark_wooden_planks",     # 실내 천장 (나무 판자)
    "grass": "forest_floor",             # 숲 바닥
    "gravel": "cobblestone_04",          # 성 안뜰
    "marble": "marble_tiles",            # 성당 바닥
    "roof": "grey_roof_tiles_02",        # 성당·탑 지붕
    "bark": "bark_brown_02",             # 나무 줄기
    "wood": "medieval_wood",             # 의자·통·나무 소품
    "rock": "rock_wall_08",              # 바위
}
MAPS = {"Diffuse": "diff", "nor_gl": "nor_gl", "Rough": "rough"}
UA = {"User-Agent": "dungeon-reborn-asset-fetch/1.0"}


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA))


root = os.path.join(os.path.dirname(__file__), "..", "godot", "assets", "textures")
for slot, aid in SLOTS.items():
    d = os.path.join(root, slot)
    os.makedirs(d, exist_ok=True)
    files = json.load(get(f"https://api.polyhaven.com/files/{aid}"))
    for key, short in MAPS.items():
        url = files[key]["1k"]["jpg"]["url"]
        out = os.path.join(d, f"{aid}_{short}_1k.jpg")
        if not os.path.exists(out):
            with open(out, "wb") as fo:
                fo.write(get(url).read())
        print(slot, out, os.path.getsize(out) // 1024, "KB")
with open(os.path.join(root, "LICENSE.txt"), "w") as f:
    f.write("Textures from Poly Haven (https://polyhaven.com), CC0 1.0 Universal (public domain).\n")
    for slot, aid in SLOTS.items():
        f.write(f"{slot}: https://polyhaven.com/a/{aid}\n")
