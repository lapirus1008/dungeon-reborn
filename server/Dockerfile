# Dungeon Reborn 온라인(클라우드) 전용 서버 이미지
# 빌드: docker build -f server/Dockerfile -t dungeon-reborn-server .
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.5.1
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget unzip libfontconfig1 \
 && rm -rf /var/lib/apt/lists/* \
 && wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -O /tmp/godot.zip \
 && unzip -q /tmp/godot.zip -d /tmp \
 && mv "/tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
 && chmod +x /usr/local/bin/godot \
 && rm /tmp/godot.zip

WORKDIR /game
COPY godot/ /game/
# 리소스 가져오기(임포트)를 이미지 빌드 때 미리 해 둠
RUN godot --headless --path /game --import >/dev/null 2>&1 || true

# 계정 DB(계정별 JSON)는 /data 볼륨에 저장 -> 컨테이너를 바꿔도 유지
VOLUME /data
EXPOSE 7777/udp
CMD ["godot", "--headless", "--path", "/game", "--", "--server", "--port", "7777", "--accounts", "/data/accounts"]
