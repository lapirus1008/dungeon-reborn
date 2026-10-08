# Dungeon Reborn 온라인(클라우드) 전용 서버 이미지
# 빌드: docker build -f server/Dockerfile -t dungeon-reborn-server .
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.5.1
# 공식 릴리스의 SHA512-SUMS.txt 값 (내려받은 엔진이 바뀌지 않았는지 확인)
ARG GODOT_SHA512=5bccbed65a94b82c7c319fdb15719ee8113a6e503976cc54e16f1c61fe95f3d74e5e40b8449b5bb89ff7f424574c20af01a4f5ef08b389e4dc338b245185b0b9
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget unzip libfontconfig1 \
 && rm -rf /var/lib/apt/lists/* \
 && wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -O /tmp/godot.zip \
 && echo "${GODOT_SHA512}  /tmp/godot.zip" | sha512sum -c - \
 && unzip -q /tmp/godot.zip -d /tmp \
 && mv "/tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
 && chmod 755 /usr/local/bin/godot \
 && rm /tmp/godot.zip \
 && apt-get purge -y wget unzip && apt-get autoremove -y

# 서버는 root가 아닌 전용 사용자로 실행
RUN useradd --system --uid 10001 --create-home --home-dir /home/game --shell /usr/sbin/nologin game

WORKDIR /game
COPY godot/ /game/
# 리소스 가져오기(임포트)를 이미지 빌드 때 미리 해 둠. 게임 파일은 읽기 전용(root 소유)
RUN godot --headless --path /game --import >/dev/null 2>&1 || true
COPY server/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

# 계정 DB(계정별 JSON)와 통신 암호화 키는 /data 볼륨에 저장 -> 컨테이너를 바꿔도 유지
VOLUME /data
EXPOSE 7777/udp
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["godot", "--headless", "--path", "/game", "--", "--server", "--port", "7777", "--accounts", "/data/accounts"]
