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


static func empty_equipment() -> Dictionary:
	var e := {}
	for k in Data.GEAR_SLOTS:
		e[k] = null
	return e


static func fresh() -> Dictionary:
	var eq := empty_equipment()
	eq.weapon = Data.make_item("rusty_sword")
	eq.chest = Data.make_item("padded_tunic")
	eq.feet = Data.make_item("leather_boots")
	var d := {
		"cls": "fighter",
		"gold": 150,
		"equipment": eq,
		"bag": [],
		"stash": [],
		"stats": {"raids": 0, "extracts": 0, "deaths": 0, "kills": 0, "pvp_kills": 0, "best_haul": 0},
		"settings": {"sensitivity": 1.0, "quality": "mid"},
	}
	for b in ["health_potion", "health_potion"]:
		Inv.add_auto(d.bag, Inv.bag_size(d.cls), Data.make_item(b))
	for b in ["rusty_dagger", "oak_staff", "iron_mace", "leather_cap", "leather_gloves", "cloth_pants", "bandage", "bandage"]:
		Inv.add_auto(d.stash, Inv.STASH, Data.make_item(b))
	return d


# 예전 아이템 정리: 장신구(trinket) 칸 -> 반지/목걸이, 옵션 배열
const LEGACY_SLOT_ITEM := {"copper_ring": "ring1", "ruby_ring": "ring1", "wolf_pendant": "necklace", "skull_amulet": "necklace"}


# 저장 파일/DB에서 읽은 데이터를 현재 버전 형식으로 정리 (빠진 키 채우기, 옛 아이템 변환, 격자 위치)
static func normalize(parsed) -> Dictionary:
	var f := fresh()
	if parsed is Dictionary:
		for k in f:
			if parsed.has(k):
				if k == "equipment" and parsed[k] is Dictionary:
					f[k] = empty_equipment()
					for sl in parsed[k]:
						var it = parsed[k][sl]
						if it == null:
							continue
						if sl == "trinket":
							sl = LEGACY_SLOT_ITEM.get(it.get("base", ""), "ring1")
						if f[k].has(sl):
							f[k][sl] = it
				elif f[k] is Dictionary and parsed[k] is Dictionary:
					f[k].merge(parsed[k], true)
				else:
					f[k] = parsed[k]
	f["gold"] = int(f["gold"])
	for k in f["stats"]:
		f["stats"][k] = int(f["stats"][k])
	# JSON은 정수를 float로 읽으므로 정리
	for it in all_items(f):
		it["rarity"] = int(it.get("rarity", 0))
		it["value"] = int(it.get("value", 1))
		if not it.has("affixes"):
			it["affixes"] = []
		for a in it.affixes:
			a["v"] = int(a["v"])
		if it.has("x"):
			it["x"] = int(it["x"])
			it["y"] = int(it["y"])
			it["r"] = bool(it.get("r", false))
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
		if e != null and (not Data.ITEM_BASES.has(e["base"]) or not (s in Data.gear_slots_for(e))):
			f["equipment"][s] = null
			if Data.ITEM_BASES.has(e["base"]):
				f["stash"].append(e)
	f["stash"] = f["stash"].filter(func(it): return Data.ITEM_BASES.has(it["base"]))
	f["bag"] = f["bag"].filter(func(it): return Data.ITEM_BASES.has(it["base"]))
	# 현재 직업이 쓸 수 없는 무기를 들고 있으면 보관함으로
	var w = f["equipment"]["weapon"]
	if w != null and not Data.can_equip(w, f["cls"]):
		f["stash"].append(w)
		f["equipment"]["weapon"] = null
	_fix_grid(f)
	return f


# 위치가 없거나 겹치는 아이템을 다시 배치 (가방 -> 보관함 -> 판매)
static func _fix_grid(f: Dictionary) -> void:
	var sold := 0
	var over := _fix_store(f.bag, Inv.bag_size(f.cls))
	for it in over:
		f.stash.append(it)
	for it in _fix_store(f.stash, Inv.STASH):
		f.gold += int(it.value)
		sold += 1


static func _fix_store(list: Array, grid: Vector2i) -> Array:
	var ok := []
	var loose := []
	for it in list:
		if it.has("x") and Inv.fits(ok, grid, it, int(it.x), int(it.y), bool(it.get("r", false))):
			ok.append(it)
		else:
			loose.append(it)
	list.clear()
	list.append_array(ok)
	var over := []
	for it in loose:
		if not Inv.add_auto(list, grid, it):
			over.append(it)
	return over


static func ctx_of(s: Dictionary) -> Dictionary:
	return {"cls": s.cls, "equipment": s.equipment, "stores": {
		"bag": {"list": s.bag, "grid": Inv.bag_size(s.cls)},
		"stash": {"list": s.stash, "grid": Inv.STASH},
	}}


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


# 로비 조작. 결과 {ok, msg(토스트), sfx}. 인덱스/아이디는 서버에서 그대로 검증되도록 모두 확인
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
				s.equipment.weapon = null
				if not Inv.add_auto(s.stash, Inv.STASH, w):
					s.gold += int(w.value)
				msg = "무기가 보관함으로 이동했습니다"
			# 보관함에 맞는 무기가 있고 무기 칸이 비었으면 자동 장착
			if s.equipment.weapon == null:
				for i in s.stash.size():
					if Data.base_of(s.stash[i]).slot == "weapon" and Data.can_equip(s.stash[i], cid):
						s.equipment.weapon = s.stash[i]
						s.stash.remove_at(i)
						break
			# 직업마다 가방 크기가 달라서 다시 배치 (넘치면 보관함)
			for it in Inv.repack(s.bag, Inv.bag_size(cid)):
				if Inv.add_auto(s.stash, Inv.STASH, it):
					msg = "가방에 안 들어가는 물건은 보관함으로 옮겼습니다"
				else:
					s.gold += int(it.value)
			return _r(true, msg, "ui")
		"move":
			# [src, id, dst, x, y, r, slot]
			if args.size() < 6:
				return _r(false)
			var r := Inv.move(ctx_of(s), str(args[0]), str(args[1]), str(args[2]), int(args[3]), int(args[4]), bool(args[5]), str(args[6]) if args.size() > 6 else "")
			return _r(r.ok, r.get("msg", ""), "ui" if r.ok else "")
		"quick":
			if args.size() < 2:
				return _r(false)
			var src := str(args[0])
			var r := Inv.quick(ctx_of(s), src, str(args[1]), ["bag", "stash"] if src != "bag" else ["stash"])
			return _r(r.ok, r.get("msg", ""), "ui" if r.ok else "")
		"transfer":
			if args.size() < 2:
				return _r(false)
			var src := str(args[0])
			var r := Inv.transfer(ctx_of(s), src, str(args[1]), ["stash", "bag"] if src != "stash" else ["bag"])
			return _r(r.ok, r.get("msg", ""), "ui" if r.ok else "")
		"sell":
			if args.size() < 2:
				return _r(false)
			var src := str(args[0])
			if src != "stash" and src != "bag":
				return _r(false)
			var list: Array = s[src]
			var i := Inv.index_of(list, str(args[1]))
			if i < 0:
				return _r(false)
			var it: Dictionary = list[i]
			list.remove_at(i)
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
			for it in Inv.repack(s.stash, Inv.STASH):
				s.gold += int(it.value)
			return _r(true)
		"buy":
			var base := str(args[0]) if args.size() else ""
			var price := shop_price(base)
			if price < 0 or not Data.ITEM_BASES.has(base) or s.gold < price:
				return _r(false)
			var it := Data.make_item(base, 0)
			if not Inv.add_auto(s.stash, Inv.STASH, it):
				return _r(false, "보관함이 가득 찼습니다")
			s.gold -= price
			return _r(true, "%s 구매" % Data.ITEM_BASES[base].name, "coin")
		"relief":
			if not needs_relief(s):
				return _r(false)
			Inv.add_auto(s.stash, Inv.STASH, Data.make_item(Data.STARTER_WEAPON[s.cls]))
			Inv.add_auto(s.stash, Inv.STASH, Data.make_item("health_potion"))
			return _r(true, "구호 물자를 받았습니다")
		"reset":
			var keep_settings = s.get("settings", {})
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
	s.equipment = empty_equipment()
	s.bag = []
	s.stats.raids += 1
	return lo


# 레이드가 시작되지 못했으면 장비를 되돌림
static func restore_loadout(s: Dictionary, lo: Dictionary) -> void:
	for k in lo.equipment:
		if lo.equipment[k] != null:
			if s.equipment.get(k) == null:
				s.equipment[k] = lo.equipment[k]
			elif not Inv.add_auto(s.stash, Inv.STASH, lo.equipment[k]):
				s.gold += int(lo.equipment[k].value)
	for it in lo.bag:
		if not Inv.add_auto(s.bag, Inv.bag_size(s.cls), it) and not Inv.add_auto(s.stash, Inv.STASH, it):
			s.gold += int(it.value)
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
	s.equipment = empty_equipment()
	for k in r.equipment:
		if s.equipment.has(k):
			s.equipment[k] = r.equipment[k]
	# 가방은 들고 나온 배치 그대로, 들어가지 않으면 보관함, 그래도 안 되면 판매
	var sold := 0
	s.bag = []
	for it in r.bag:
		var ok = it.has("x") and Inv.fits(s.bag, Inv.bag_size(s.cls), it, int(it.x), int(it.y), bool(it.get("r", false)))
		if ok:
			s.bag.append(it)
		elif not Inv.add_auto(s.stash, Inv.STASH, it):
			s.gold += int(it.value)
			sold += int(it.value)
	if sold > 0:
		return "보관함이 가득 차 남은 물건을 %dg에 판매했습니다" % sold
	return ""
