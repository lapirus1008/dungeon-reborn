# 계정(저장 데이터) 규칙: 로비 조작, 레이드 입장/결과 반영
# 오프라인/호스트는 내 PC의 저장 파일에, 온라인 서버는 서버의 계정 DB에 같은 규칙을 적용한다
class_name Account
extends RefCounted

const STASH_SIZE := 60
const BAG_SIZE := 16

# 상인 목록: 물약/방어구 + 8직업 기본 무기 (가격은 서버가 이 표로 검증)
const SHOP := [
	["health_potion", 30], ["bandage", 12],
	["rusty_sword", 40], ["training_longsword", 40], ["rusty_dagger", 40], ["rusty_greatsword", 40],
	["oak_staff", 40], ["iron_mace", 40], ["leather_cap", 30], ["padded_tunic", 40],
]


static func fresh() -> Dictionary:
	return {
		"cls": "fighter",
		"gold": 150,
		"equipment": {"weapon": Data.make_item("rusty_sword"), "head": null, "chest": Data.make_item("padded_tunic"), "trinket": null},
		"bag": [Data.make_item("health_potion"), Data.make_item("health_potion")],
		"stash": [Data.make_item("rusty_dagger"), Data.make_item("oak_staff"), Data.make_item("iron_mace"), Data.make_item("leather_cap"), Data.make_item("bandage"), Data.make_item("bandage")],
		"stats": {"raids": 0, "extracts": 0, "deaths": 0, "kills": 0, "pvp_kills": 0, "best_haul": 0},
		"settings": {"sensitivity": 1.0, "quality": "mid"},
	}


# 저장 파일/DB에서 읽은 데이터를 현재 버전 형식으로 정리 (빠진 키 채우기, 옛 아이템 변환)
static func normalize(parsed) -> Dictionary:
	var f := fresh()
	if parsed is Dictionary:
		for k in f:
			if parsed.has(k):
				if f[k] is Dictionary and parsed[k] is Dictionary:
					f[k].merge(parsed[k], true)
				else:
					f[k] = parsed[k]
	f["gold"] = int(f["gold"])
	for k in f["stats"]:
		f["stats"][k] = int(f["stats"][k])
	# JSON은 정수를 float로 읽으므로 희귀도를 정수로 정리
	for it in all_items(f):
		it["rarity"] = int(it["rarity"])
		it["value"] = int(it["value"])
		# 이전 버전 아이템(활 등)을 새 무기로 변환
		if Data.LEGACY_ITEM.has(it["base"]):
			it["base"] = Data.LEGACY_ITEM[it["base"]]
	if Data.LEGACY_CLASS.has(f["cls"]):
		f["cls"] = Data.LEGACY_CLASS[f["cls"]]
	if not Data.CLASSES.has(f["cls"]):
		f["cls"] = "fighter"
	# 알 수 없는 아이템 제거
	for s in f["equipment"]:
		var e = f["equipment"][s]
		if e != null and not Data.ITEM_BASES.has(e["base"]):
			f["equipment"][s] = null
	f["stash"] = f["stash"].filter(func(it): return Data.ITEM_BASES.has(it["base"]))
	f["bag"] = f["bag"].filter(func(it): return Data.ITEM_BASES.has(it["base"]))
	# 현재 직업이 쓸 수 없는 무기를 들고 있으면 보관함으로
	var w = f["equipment"]["weapon"]
	if w != null and not Data.can_equip(w, f["cls"]):
		f["stash"].append(w)
		f["equipment"]["weapon"] = null
	return f


static func all_items(d: Dictionary) -> Array:
	var out := []
	for it in d["stash"]:
		out.append(it)
	for it in d["bag"]:
		out.append(it)
	for s in d["equipment"]:
		if d["equipment"][s] != null:
			out.append(d["equipment"][s])
	return out


static func shop_price(base: String) -> int:
	for e in SHOP:
		if e[0] == base:
			return e[1]
	return -1


static func _r(ok: bool, msg := "", sfx := "") -> Dictionary:
	return {"ok": ok, "msg": msg, "sfx": sfx}


# 로비 조작. 결과 {ok, msg(토스트), sfx}. 인덱스 등은 서버에서 그대로 검증되도록 모두 범위 확인
static func apply(s: Dictionary, op: String, args: Array) -> Dictionary:
	match op:
		"select_class":
			var cid: String = str(args[0]) if args.size() else ""
			if not Data.CLASSES.has(cid) or s.cls == cid:
				return _r(false)
			s.cls = cid
			var msg := ""
			var w = s.equipment.weapon
			if w != null and not Data.can_equip(w, cid):
				s.stash.append(w)
				s.equipment.weapon = null
				msg = "무기가 보관함으로 이동했습니다"
			# 보관함에 맞는 무기가 있고 무기 칸이 비었으면 자동 장착
			if s.equipment.weapon == null:
				for i in s.stash.size():
					if Data.base_of(s.stash[i]).slot == "weapon" and Data.can_equip(s.stash[i], cid):
						s.equipment.weapon = s.stash[i]
						s.stash.remove_at(i)
						break
			return _r(true, msg, "ui")
		"unequip":
			var slot := str(args[0]) if args.size() else ""
			if not s.equipment.has(slot) or s.equipment[slot] == null:
				return _r(false)
			if s.stash.size() >= STASH_SIZE:
				return _r(false, "보관함이 가득 찼습니다")
			s.stash.append(s.equipment[slot])
			s.equipment[slot] = null
			return _r(true)
		"bag_to_stash":
			var i := _idx(args)
			if i < 0 or i >= s.bag.size():
				return _r(false)
			if s.stash.size() >= STASH_SIZE:
				return _r(false, "보관함이 가득 찼습니다")
			s.stash.append(s.bag[i])
			s.bag.remove_at(i)
			return _r(true)
		"stash_click":
			var i := _idx(args)
			if i < 0 or i >= s.stash.size():
				return _r(false)
			var it: Dictionary = s.stash[i]
			var b := Data.base_of(it)
			if Data.can_equip(it, s.cls):
				var prev = s.equipment[b.slot]
				s.equipment[b.slot] = it
				s.stash.remove_at(i)
				if prev != null:
					s.stash.append(prev)
				return _r(true)
			if b.slot == "weapon":
				return _r(false, "%s 전용 무기입니다" % Data.class_names(b.classes))
			if s.bag.size() >= BAG_SIZE:
				return _r(false, "가방이 가득 찼습니다")
			s.stash.remove_at(i)
			s.bag.append(it)
			return _r(true)
		"sell":
			var i := _idx(args)
			if i < 0 or i >= s.stash.size():
				return _r(false)
			var it: Dictionary = s.stash[i]
			s.stash.remove_at(i)
			s.gold += int(it.value)
			return _r(true, "%s 판매: +%dg" % [Data.base_of(it).name, it.value], "coin")
		"sell_treasure":
			var sum := 0
			var keep := []
			for it in s.stash:
				if Data.base_of(it).slot == "treasure":
					sum += int(it.value)
				else:
					keep.append(it)
			if sum == 0:
				return _r(false, "판매할 보물이 없습니다")
			s.stash = keep
			s.gold += sum
			return _r(true, "보물 판매: +%dg" % sum, "coin")
		"sort_stash":
			var order := {"weapon": 0, "head": 1, "chest": 2, "trinket": 3, "consumable": 4, "treasure": 5}
			s.stash.sort_custom(func(a, b):
				var oa: int = order[Data.base_of(a).slot]
				var ob: int = order[Data.base_of(b).slot]
				if oa != ob:
					return oa < ob
				if a.rarity != b.rarity:
					return a.rarity > b.rarity
				return a.value > b.value)
			return _r(true)
		"buy":
			var base := str(args[0]) if args.size() else ""
			var price := shop_price(base)
			if price < 0 or not Data.ITEM_BASES.has(base) or s.gold < price:
				return _r(false)
			if s.stash.size() >= STASH_SIZE:
				return _r(false, "보관함이 가득 찼습니다")
			s.gold -= price
			s.stash.append(Data.make_item(base, 0))
			return _r(true, "%s 구매" % Data.ITEM_BASES[base].name, "coin")
		"relief":
			if not needs_relief(s):
				return _r(false)
			s.stash.append(Data.make_item(Data.STARTER_WEAPON[s.cls]))
			s.stash.append(Data.make_item("health_potion"))
			return _r(true, "구호 물자를 받았습니다")
		"reset":
			var keep_settings: Dictionary = s.settings
			var f := fresh()
			s.clear()
			s.merge(f)
			s.settings = keep_settings
			return _r(true, "초기화했습니다")
	return _r(false)


static func _idx(args: Array) -> int:
	if args.is_empty() or not (args[0] is int or args[0] is float):
		return -1
	return int(args[0])


# 무기가 없고 살 돈도 없을 때만 구호 물자
static func needs_relief(s: Dictionary) -> bool:
	if s.equipment.weapon != null or s.gold >= 40:
		return false
	for it in s.stash:
		if Data.base_of(it).slot == "weapon" and Data.can_equip(it, s.cls):
			return false
	return true


# 입장 시 소지품은 위험에 노출됨 (탈출해야 돌아옴)
static func take_loadout(s: Dictionary) -> Dictionary:
	var lo := {"cls": s.cls, "equipment": s.equipment.duplicate(), "bag": s.bag.duplicate()}
	s.equipment = {"weapon": null, "head": null, "chest": null, "trinket": null}
	s.bag = []
	s.stats.raids += 1
	return lo


# 레이드가 시작되지 못했으면 장비를 되돌림
static func restore_loadout(s: Dictionary, lo: Dictionary) -> void:
	for k in lo.equipment:
		if lo.equipment[k] != null:
			if s.equipment[k] == null:
				s.equipment[k] = lo.equipment[k]
			else:
				s.stash.append(lo.equipment[k])
	s.bag.append_array(lo.bag)
	s.stats.raids = maxi(0, s.stats.raids - 1)


# 레이드 결과 반영. 보관함이 가득 차면 남은 물건은 판매. 안내 문구 반환
static func apply_result(s: Dictionary, r: Dictionary) -> String:
	s.stats.kills += int(r.kills)
	s.stats.pvp_kills += int(r.pvp_kills)
	if not r.success:
		s.stats.deaths += 1
		return ""
	s.stats.extracts += 1
	s.stats.best_haul = maxi(int(s.stats.best_haul), int(r.value))
	s.equipment = r.equipment.duplicate()
	var sold := 0
	for it in r.bag:
		if s.stash.size() < STASH_SIZE:
			s.stash.append(it)
		else:
			s.gold += int(it.value)
			sold += int(it.value)
	if sold > 0:
		return "보관함이 가득 차 남은 물건을 %dg에 판매했습니다" % sold
	return ""
