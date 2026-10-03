# 저장 데이터: 보관함, 골드, 장비, 통계, 설정 (autoload: SaveData)
# - 오프라인/호스트: 내 PC의 user://save.json
# - 온라인 서버 로그인 중: 서버 계정 DB가 원본. 로비 조작은 서버로 보내고 결과를 받아 표시 (설정만 로컬)
extends Node

signal changed


# 한 PC에서 여러 개 실행해 함께하기를 시험할 때: -- --profile 이름  (저장 파일 분리)
var PATH := "user://save.json"
var data: Dictionary = {}
var local_data: Dictionary = {}
var online := false # 온라인 서버 계정 사용 중
var account_name := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--profile"):
		PATH = "user://save_%s.json" % args[args.find("--profile") + 1].validate_filename()
	load_save()


func fresh() -> Dictionary:
	return Account.fresh()


func load_save() -> void:
	var parsed = null
	if FileAccess.file_exists(PATH):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	local_data = Account.normalize(parsed)
	if not online:
		data = local_data


func save() -> void:
	# 온라인 계정 데이터는 서버가 저장. 내 PC에는 로컬 저장만 기록
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(Account.serial(local_data)))


func reset() -> void:
	op("reset", [])


# 로비 조작 (Account.apply 규칙). 온라인이면 서버가 처리 후 계정 데이터를 돌려준다
func op(name: String, args: Array = []) -> void:
	if online:
		Net.account_op(name, args)
		return
	var r := Account.apply(data, name, args)
	if r.ok:
		save()
	show_result(r)
	changed.emit()


func show_result(r: Dictionary) -> void:
	if r.get("msg", "") != "":
		UI.toast(r.msg)
	if r.get("sfx", "") != "":
		Sfx.play(r.sfx)


# 서버 계정으로 전환 / 서버가 보낸 최신 계정 데이터 반영
func use_account(nm: String, d: Dictionary) -> void:
	var settings: Dictionary = local_data.settings
	data = Account.normalize(d)
	data.settings = settings
	online = true
	account_name = nm
	changed.emit()


func leave_account() -> void:
	if not online:
		return
	online = false
	account_name = ""
	data = local_data
	changed.emit()


func setting(key: String, default_value = null):
	return local_data["settings"].get(key, default_value)


func set_setting(key: String, value) -> void:
	local_data["settings"][key] = value
	save()
