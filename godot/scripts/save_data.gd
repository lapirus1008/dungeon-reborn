# 저장 데이터: 보관함, 골드, 장비, 통계, 설정 (autoload: SaveData)
extends Node

# 한 PC에서 여러 개 실행해 함께하기를 시험할 때: -- --profile 이름  (저장 파일 분리)
var PATH := "user://save.json"
const STASH_SIZE := 60
const BAG_SIZE := 16

var data: Dictionary = {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--profile"):
		PATH = "user://save_%s.json" % args[args.find("--profile") + 1].validate_filename()
	load_save()


func fresh() -> Dictionary:
	return {
		"cls": "fighter",
		"gold": 150,
		"equipment": {"weapon": Data.make_item("rusty_sword"), "head": null, "chest": Data.make_item("padded_tunic"), "trinket": null},
		"bag": [Data.make_item("health_potion"), Data.make_item("health_potion")],
		"stash": [Data.make_item("rusty_dagger"), Data.make_item("oak_staff"), Data.make_item("iron_mace"), Data.make_item("leather_cap"), Data.make_item("bandage"), Data.make_item("bandage")],
		"stats": {"raids": 0, "extracts": 0, "deaths": 0, "kills": 0, "pvp_kills": 0, "best_haul": 0},
		"settings": {"sensitivity": 1.0, "quality": "mid"},
	}


func load_save() -> void:
	var f := fresh()
	if FileAccess.file_exists(PATH):
		var txt := FileAccess.get_file_as_string(PATH)
		var parsed = JSON.parse_string(txt)
		if parsed is Dictionary:
			for k in f:
				if parsed.has(k):
					if f[k] is Dictionary and parsed[k] is Dictionary:
						f[k].merge(parsed[k], true)
					else:
						f[k] = parsed[k]
	# JSON은 정수를 float로 읽으므로 희귀도를 정수로 정리
	for it in _all_items(f):
		it["rarity"] = int(it["rarity"])
		it["value"] = int(it["value"])
		# 이전 버전 아이템(활 등)을 새 무기로 변환
		if Data.LEGACY_ITEM.has(it["base"]):
			it["base"] = Data.LEGACY_ITEM[it["base"]]
	if Data.LEGACY_CLASS.has(f["cls"]):
		f["cls"] = Data.LEGACY_CLASS[f["cls"]]
	if not Data.CLASSES.has(f["cls"]):
		f["cls"] = "fighter"
	# 현재 직업이 쓸 수 없는 무기를 들고 있으면 보관함으로
	var w = f["equipment"]["weapon"]
	if w != null and not Data.can_equip(w, f["cls"]):
		f["stash"].append(w)
		f["equipment"]["weapon"] = null
	# 알 수 없는 아이템 제거
	f["stash"] = f["stash"].filter(func(it): return Data.ITEM_BASES.has(it["base"]))
	f["bag"] = f["bag"].filter(func(it): return Data.ITEM_BASES.has(it["base"]))
	data = f


func _all_items(d: Dictionary) -> Array:
	var out := []
	for it in d["stash"]:
		out.append(it)
	for it in d["bag"]:
		out.append(it)
	for s in d["equipment"]:
		if d["equipment"][s] != null:
			out.append(d["equipment"][s])
	return out


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func reset() -> void:
	data = fresh()
	save()


func setting(key: String, default_value = null):
	return data["settings"].get(key, default_value)


func set_setting(key: String, value) -> void:
	data["settings"][key] = value
	save()
