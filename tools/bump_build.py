#!/usr/bin/env python3
"""게임 코드를 바꿔 커밋하기 전에 실행: 빌드 번호(날짜-시각)를 새로 써서
서버와 게임이 다른 코드면 접속이 막히게 함.  python3 tools/bump_build.py"""
import datetime, os, re
p = os.path.join(os.path.dirname(__file__), "..", "godot", "scripts", "build_info.gd")
s = open(p, encoding="utf-8").read()
b = datetime.datetime.utcnow().strftime("%Y%m%d-%H%M%S")
s = re.sub(r'const BUILD := ".*"', 'const BUILD := "%s"' % b, s)
open(p, "w", encoding="utf-8").write(s)
print("build", b)
