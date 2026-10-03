# 저장 데이터: 보관함, 골드, 장비, 통계, 설정 (autoload: SaveData)
extends Node

const PATH := "user://save.json"
const STASH_SIZE := 60
const BAG_SIZE := 16

var data: Dictionary = {}


func _ready() -> void:
	load_save()


func fresh() -> Dictionary:
	return {
		"cls": "fighter",
		"gold": 150,
		"equipment": {"weapon": Data.make_item("rusty_sword"), "head": null, "chest": Data.make_item("padded_tunic"), "trinket": null},
		"bag": [Data.make_item("health_potion"), Data.make_item("health_potion")],
		"stash": [Data.make_item("short_bow"), Data.make_item("oak_staff"), Data.make_item("leather_cap"), Data.make_item("bandage"), Data.make_item("bandage")],
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
