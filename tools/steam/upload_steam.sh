#!/usr/bin/env bash
# 만든 게임 폴더를 스팀에 올리기 (SteamCMD 필요: https://developer.valvesoftware.com/wiki/SteamCMD)
# 사용: STEAM_APP_ID=1234560 STEAM_DEPOT_ID=1234561 STEAM_USER=내스팀웍스계정 tools/steam/upload_steam.sh "빌드 설명"
#   처음 한 번은 스팀 가드 코드를 물어봄. 올린 빌드는 Steamworks > SteamPipe > 빌드 에서 브랜치(default)에 지정해야 실제로 배포됨
set -euo pipefail
: "${STEAM_APP_ID:?STEAM_APP_ID 를 지정하세요 (스팀웍스 앱 ID)}"
: "${STEAM_DEPOT_ID:?STEAM_DEPOT_ID 를 지정하세요 (보통 앱 ID + 1, 윈도우 디포)}"
: "${STEAM_USER:?STEAM_USER 를 지정하세요 (스팀웍스 권한이 있는 스팀 계정)}"
STEAMCMD="${STEAMCMD:-steamcmd}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DESC="${1:-Dungeon Reborn build $(date +%Y%m%d-%H%M)}"
test -f "$HERE/content/windows/DungeonReborn.exe" || { echo "먼저 tools/steam/build_steam.sh 를 실행하세요"; exit 1; }
mkdir -p "$HERE/output"
VDF="$HERE/output/app_build_${STEAM_APP_ID}.vdf"
sed -e "s/__APP_ID__/${STEAM_APP_ID}/g" -e "s/__DEPOT_ID__/${STEAM_DEPOT_ID}/g" -e "s/__DESC__/${DESC//\//-}/g" \
	-e "s#__CONTENT__#${HERE}/content/#g" -e "s#__OUTPUT__#${HERE}/output/#g" "$HERE/app_build.vdf.template" > "$VDF"
echo "업로드: 앱 $STEAM_APP_ID / 디포 $STEAM_DEPOT_ID ($DESC)"
"$STEAMCMD" +login "$STEAM_USER" +run_app_build "$VDF" +quit
