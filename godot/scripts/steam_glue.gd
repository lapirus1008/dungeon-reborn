# 스팀 연동 (선택): GodotSteam 플러그인(addons/godotsteam)이 있고 스팀에서 실행했을 때만 켜짐.
# 플러그인이 없거나 스팀 밖에서 실행하면 available = false 로 조용히 꺼지고, 게임은 지금처럼 이름 + PIN으로 접속.
# 하는 일: 스팀 닉네임 가져오기, 온라인 서버 로그인용 표(웹 API 티켓) 만들기, 스팀 오버레이·콜백 처리
# 설치 방법은 docs/STEAM_RELEASE.md 참고
extends Node

# 스팀웍스에서 받은 앱 ID. 스팀으로 실행하면 스팀이 SteamAppId 환경 변수로 알려 주므로 보통 0으로 둬도 됨
const APP_ID := 0
const IDENTITY := "dungeonreborn" # 서버 Net.STEAM_IDENTITY 와 같아야 함

var available := false
var persona := ""
var steam_id := 0
var app_id := 0
var status := "스팀 연동 꺼짐"
var _steam: Object = null
var _ticket_cb: Callable


func _ready() -> void:
	if DisplayServer.get_name() == "headless" or not Engine.has_singleton("Steam"):
		return
	app_id = int(OS.get_environment("SteamAppId")) if OS.get_environment("SteamAppId") != "" else APP_ID
	if app_id == 0 and FileAccess.file_exists("res://steam_appid.txt"):
		app_id = int(FileAccess.get_file_as_string("res://steam_appid.txt").strip_edges())
	_steam = Engine.get_singleton("Steam")
	var ok := false
	if _steam.has_method("steamInitEx"):
		var r = _steam.call("steamInitEx", false, app_id)
		ok = r is Dictionary and int(r.get("status", 1)) == 0
		if not ok and r is Dictionary:
			status = "스팀 연동 실패: " + str(r.get("verbal", ""))
	elif _steam.has_method("steamInit"):
		var r2 = _steam.call("steamInit", false)
		ok = r2 is Dictionary and int(r2.get("status", 0)) == 1
	if not ok:
		_steam = null
		return
	available = true
	persona = str(_steam.call("getPersonaName"))
	steam_id = int(_steam.call("getSteamID"))
	status = "스팀 연동됨: " + persona
	if _steam.has_signal("get_ticket_for_web_api"):
		_steam.connect("get_ticket_for_web_api", _on_ticket)
	print("[steam] ", status, " (앱 ", app_id, ")")


func _process(_dt: float) -> void:
	if _steam != null:
		_steam.call("run_callbacks")


# 온라인 서버 로그인용 표 (16진 문자열). 실패하면 "" — cb(hex) 로 돌려줌
func request_ticket(cb: Callable) -> void:
	if not available or not _steam.has_method("getAuthTicketForWebApi"):
		cb.call("")
		return
	_ticket_cb = cb
	_steam.call("getAuthTicketForWebApi", IDENTITY)
	# 응답이 없으면 5초 뒤 포기
	get_tree().create_timer(5.0).timeout.connect(func():
		if _ticket_cb.is_valid():
			var c := _ticket_cb
			_ticket_cb = Callable()
			c.call(""))


func _on_ticket(_handle, result, _size, buffer) -> void:
	if not _ticket_cb.is_valid():
		return
	var c := _ticket_cb
	_ticket_cb = Callable()
	if int(result) != 1:
		c.call("")
		return
	var bytes := PackedByteArray(buffer) if buffer is Array else (buffer as PackedByteArray)
	c.call(bytes.hex_encode())
