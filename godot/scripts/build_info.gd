# 빌드 번호: 서버와 게임이 같은 코드인지 확인하는 데 씀 (tools/bump_build.py 가 커밋 전에 갱신)
# 다르면 접속할 때 "게임 버전이 다릅니다"로 막힘 → 서로 다른 지형/규칙으로 같이 노는 일을 방지
class_name BuildInfo
extends RefCounted

const BUILD := "20261006-131656"
