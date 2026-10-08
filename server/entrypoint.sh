#!/bin/sh
# /data 볼륨(호스트 폴더)은 예전 버전에서 root 소유로 만들어졌을 수 있으므로 소유자를 맞춘 뒤
# root 권한을 버리고 game 사용자로 서버를 실행한다
set -e
umask 077
mkdir -p /data/accounts
chown -R game:game /data
chmod 700 /data/accounts /data
# 계정 파일과 통신 암호화 키는 서버 사용자만 읽을 수 있게
find /data -type f -exec chmod 600 {} +
exec setpriv --reuid=game --regid=game --init-groups --inh-caps=-all env HOME=/home/game "$@"
