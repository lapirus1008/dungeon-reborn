#!/usr/bin/env bash
# 스팀에 올릴 윈도우용 게임 폴더 만들기 → tools/steam/content/windows/
#   DungeonReborn.exe, DungeonReborn.pck (모든 그림·모델·소리), licenses/ (글꼴·에셋·엔진 라이선스)
#   GodotSteam 플러그인(godot/addons/godotsteam)이 있으면 그 DLL(steam_api64.dll 등)도 같이 복사됨
# 사용: GODOT=/경로/Godot_v4.5.1-stable_linux.x86_64 tools/steam/build_steam.sh
#   (윈도우에서는 Git Bash 로 GODOT=/c/.../Godot_v4.5.1-stable_win64.exe 처럼 지정)
set -euo pipefail
GODOT="${GODOT:-godot}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="$HERE/content/windows"
rm -rf "$OUT"
mkdir -p "$OUT/licenses"

echo "[1/3] 게임 내보내기 (Steam Windows 프리셋)"
"$GODOT" --headless --path "$ROOT/godot" --export-release "Steam Windows" "$OUT/DungeonReborn.exe"

echo "[2/3] 라이선스 파일 모으기"
cp "$ROOT"/godot/fonts/OFL-*.txt "$OUT/licenses/"
cp "$ROOT"/godot/assets/kaykit/characters/LICENSE-*.txt "$ROOT"/godot/assets/kaykit/dungeon/LICENSE-*.txt "$OUT/licenses/"
cp "$ROOT/godot/assets/textures/LICENSE.txt" "$OUT/licenses/PolyHaven-textures.txt"
"$GODOT" --headless --path "$ROOT/godot" -s "$HERE/write_engine_license.gd" -- "$OUT/licenses" >/dev/null

echo "[3/3] 확인"
test -f "$OUT/DungeonReborn.exe" && test -f "$OUT/DungeonReborn.pck"
if [ -f "$OUT/steam_api64.dll" ]; then echo "  스팀 연동 DLL 포함됨 (GodotSteam)"; else echo "  ※ steam_api64.dll 없음: GodotSteam 플러그인을 넣지 않아 스팀 계정 로그인·오버레이 없이 동작합니다"; fi
du -sh "$OUT"
echo "완료: $OUT  →  업로드는 tools/steam/upload_steam.sh"
