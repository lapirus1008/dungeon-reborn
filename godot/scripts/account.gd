# 계정(저장 데이터) 규칙: 캐릭터, 로비 조작, 레이드 입장/결과 반영
# 오프라인/호스트는 내 PC의 저장 파일에, 온라인 서버는 서버의 계정 DB에 같은 규칙을 적용한다
#
# 계정: 골드/보관함/기록은 공용, 캐릭터마다 직업·장비·가방·Q/E 스킬이 따로 있다 (던전본처럼 직업별 캐릭터)
# s.cls / s.equipment / s.bag / s.skills 는 선택된 캐릭터 데이터를 가리키는 바로가기
class_name Account
extends RefCounted

const MAX_CHARS := 8

# 상인 목록 (가격은 서버가 이 표로 검증)
const SHOP := [
	["health_potion", 30], ["bandage", 12], ["torch", 6], ["bolts", 30, 30], ["fire_flask", 24], ["rock_flask", 24], ["lightning_flask", 30], ["mimic_flask", 40],
	["old_sword", 30], ["old_longsword", 40], ["old_dagger", 25], ["old_mace", 30], ["old_staff", 35], ["old_shield", 30], ["old_crossbow", 40],
	["old_plate_chest", 30], ["old_leather_chest", 25], ["old_cloth_chest", 20],
]


static func empty_equipment() -> Dictionary:
	var e := {}
	for k in Data.ALL_SLOTS:
		e[k] = null
	return e


static func default_skills(cls: String) -> Dictionary:
	return {"q": Data.CLASSES[cls].q[0], "e": Data.CLASSES[cls].e[0]}


# 새 캐릭터 기본 지급품: 직업 무기 + 직업 방어구(일반) + 물약
static func new_character(name: String, cls: String) -> Dictionary:
	var eq := empty_equipment()
	eq.w1 = Data.make_item(Data.STARTER_WEAPON[cls])
	var off: String = Data.STARTER_OFFHAND.get(cls, "")
	if off != "":
		eq.w1o = Data.make_item(off)
	# 두 번째 무기 세트 (2키): 파이터 양손검(소용돌이), 프리스트 지팡이(신의 계시/치료)
	var second: String = {"fighter": "old_longsword", "priest": "old_staff"}.get(cls, "")
	if second != "":
		eq.w2 = Data.make_item(second)
	var at: String = Data.STARTER_ARMOR[cls]
	eq.chest = Data.make_item("old_%s_chest" % at)
	eq.legs = Data.make_item("old_%s_legs" % at)
	eq.feet = Data.make_item("old_%s_feet" % at)
	var pot := Data.make_item("health_potion")
	pot.count = 2
	eq.c3 = pot
	var band := Data.make_item("bandage")
	band.count = 2
	eq.c4 = band
	var bag := []
	eq.c5 = Data.make_item("fire_flask")
	Inv.repack(bag, Inv.bag_size(cls))
	# 소드마스터: 검 슬롯에 영검으로 쓸 검
	if cls == "swordmaster":
		eq.sw1 = Data.make_item("old_sword")
		eq.sw2 = Data.make_item("old_sword")
	return {
		"id": "c%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000],
		"name": name, "cls": cls, "equipment": eq, "bag": bag, "skills": default_skills(cls), "wset": 1,
		"stats": {"raids": 0, "extracts": 0, "deaths": 0},
	}


static func fresh() -> Dictionary:
	var c := new_character("모험가", "fighter")
	var d := {
		"gold": 150,
		"stash": [],
		"characters": [c],
		"active": c.id,
		"stats": {"raids": 0, "extracts": 0, "deaths": 0, "kills": 0, "pvp_kills": 0, "best_haul": 0},
		"settings": {"sensitivity": 1.0, "quality": "mid"},
		"version": 3,
	}
	for b in ["traveler_helmet", "wanderer_mitts", "steel_dagger", "pyro_staff", "pernach", "traveler_shield", "grandmaster_orb"]:
		Inv.add_auto(d.stash, Inv.STASH, Data.make_item(b))
	select(d, c.id)
	return d


# 선택된 캐릭터
static func cur(s: Dictionary) -> Dictionary:
	for c in s.characters:
		if c.id == s.get("active", ""):
			return c
	return s.characters[0] if s.characters.size() else {}


# 바로가기(s.cls 등)를 선택한 캐릭터로 연결
static func select(s: Dictionary, id: String) -> void:
	s.active = id
	var c := cur(s)
	if c.is_empty():
		return
	s.cls = c.cls
	s.equipment = c.equipment
	s.bag = c.bag
	s.skills = c.skills
	s.wset = c.get("wset", 1)
	s.char_name = c.name


static func set_gear(s: Dictionary, eq: Dictionary, bag: Array) -> void:
	var c := cur(s)
	c.equipment = eq
	c.bag = bag
	select(s, c.id)


# 저장용: 바로가기 제외
static func serial(s: Dictionary) -> Dictionary:
	var d := s.duplicate()
	for k in ["cls", "equipment", "bag", "skills", "wset", "char_name"]:
		d.erase(k)
	return d


static func _fix_item(it: Dictionary) -> void:
	it["rarity"] = int(it.get("rarity", 0))
	it["value"] = int(it.get("value", 1))
	it["count"] = int(it.get("count", 1))
	if not it.has("affixes"):
		it["affixes"] = []
	if not it.has("fixed"):
		it["fixed"] = []
	for a in it.affixes + it.fixed:
		if a.get("k", "") in Data.ATTRS or a.get("k", "") in ["all", "ms", "set", "regen_ooc", "life_on_kill", "armor"]:
			a["v"] = int(a["v"])
	if it.has("x"):
		it["x"] = int(it["x"])
		it["y"] = int(it["y"])
		it["r"] = bool(it.get("r", false))
	if Data.LEGACY_ITEM.has(it["base"]):
		it["base"] = Data.LEGACY_ITEM[it["base"]]
		it["affixes"] = []
		it["rarity"] = int(Data.ITEM_BASES.get(it.base, {}).get("rarity", 0))
		var fresh_item := Data.make_item(it.base)
		it["stats"] = fresh_item.stats
		it["fixed"] = fresh_item.fixed
	if it.get("stats", {}).has("dmg"):
		it.stats.dmg = int(it.stats.dmg)
	if Data.ITEM_BASES.get(it.base, {}).get("slot", "") in ["consumable", "torch", "ammo"]:
		it["rarity"] = 0
		it["count"] = clampi(int(it.count), 1, Data.max_stack(it))


# 예전 무기/장신구 칸 이름 -> 새 칸
const LEGACY_SLOTS := {"weapon": "w1", "trinket": "ring1", "q1": "c3", "q2": "c4", "q3": "c5", "util": "c5", "c3a": "c3", "c4a": "c4", "c3b": "c5", "c3c": "c5", "c4b": "c5", "c4c": "c5"}


static func _norm_char(c: Dictionary) -> Dictionary:
	var cls: String = Data.LEGACY_CLASS.get(c.get("cls", "fighter"), c.get("cls", "fighter"))
	if not Data.CLASSES.has(cls):
		cls = "fighter"
	var out := {"id": str(c.get("id", "c%d" % randi())), "name": str(c.get("name", "모험가")).left(16), "cls": cls,
		"equipment": empty_equipment(), "bag": [], "skills": default_skills(cls), "wset": int(c.get("wset", 1)),
		"stats": c.get("stats", {"raids": 0, "extracts": 0, "deaths": 0})}
	var loose := []
	var eq = c.get("equipment", {})
	if eq is Dictionary:
		for sl in eq:
			var it = eq[sl]
			if it == null or not (it is Dictionary) or not it.has("base"):
				continue
			_fix_item(it)
			if not Data.ITEM_BASES.has(it.base):
				continue
			var slot: String = LEGACY_SLOTS.get(sl, sl)
			var vs := Inv.valid_slots(it, cls)
			if not (slot in vs) and sl in LEGACY_SLOTS:
				# 예전 칸 이름: 이 아이템이 들어갈 수 있는 빈 칸으로
				for v in vs:
					if out.equipment.get(v) == null:
						slot = v
						break
			if slot in vs and out.equipment.get(slot) == null:
				out.equipment[slot] = it
			else:
				loose.append(it)
	for it in c.get("bag", []):
		if it is Dictionary and it.has("base"):
			_fix_item(it)
			if Data.ITEM_BASES.has(it.base):
				out.bag.append(it)
	var sk = c.get("skills", {})
	if sk is Dictionary:
		if sk.get("q", "") in Data.CLASSES[cls].q:
			out.skills.q = sk.q
		if sk.get("e", "") in Data.CLASSES[cls].e:
			out.skills.e = sk.e
	out["_loose"] = loose
	return out


# 저장 파일/DB에서 읽은 데이터를 현재 버전 형식으로 정리
static func normalize(parsed) -> Dictionary:
	var f := fresh()
	if not (parsed is Dictionary):
		return f
	var d := {"gold": int(parsed.get("gold", 150)), "stash": [], "characters": [], "active": "",
		"stats": f.stats.duplicate(), "settings": f.settings.duplicate(), "version": 3}
	if parsed.get("stats") is Dictionary:
		for k in d.stats:
			d.stats[k] = int(parsed.stats.get(k, 0))
	if parsed.get("settings") is Dictionary:
		d.settings.merge(parsed.settings, true)
	for it in parsed.get("stash", []):
		if it is Dictionary and it.has("base"):
			_fix_item(it)
			if Data.ITEM_BASES.has(it.base):
				d.stash.append(it)
	var chars: Array = parsed.get("characters", [])
	if chars.is_empty() and parsed.has("cls"):
		# 예전 세이브: 하나의 캐릭터로 변환
		chars = [{"name": "모험가", "cls": parsed.cls, "equipment": parsed.get("equipment", {}), "bag": parsed.get("bag", [])}]
	for c in chars:
		if c is Dictionary and d.characters.size() < MAX_CHARS:
			var nc := _norm_char(c)
			for it in nc._loose:
				d.stash.append(it)
			nc.erase("_loose")
			d.characters.append(nc)
	if d.characters.is_empty():
		d.characters = f.characters
	d.active = str(parsed.get("active", d.characters[0].id))
	select(d, d.active)
	if cur(d).is_empty():
		select(d, d.characters[0].id)
	for c in d.characters:
		for it in _fix_store(c.bag, Inv.bag_size(c.cls)):
			d.stash.append(it)
	for it in _fix_store(d.stash, Inv.STASH):
		d.gold += int(it.value)
	select(d, d.active)
	return d


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
	return {"cls": s.cls, "equipment": s.equipment, "wset": s.get("wset", 1), "stores": {
		"bag": {"list": s.bag, "grid": Inv.bag_size(s.cls)},
		"stash": {"list": s.stash, "grid": Inv.STASH},
	}}


static func all_items(d: Dictionary) -> Array:
	var out := []
	for it in d.get("stash", []):
		out.append(it)
	for c in d.get("characters", []):
		for it in c.bag:
			out.append(it)
		for k in c.equipment:
			if c.equipment[k] != null:
				out.append(c.equipment[k])
	return out


# 한 번에 사는 수량 (볼트는 30개 묶음)
static func shop_count(base: String) -> int:
	for e in SHOP:
		if e[0] == base:
			return int(e[2]) if e.size() > 2 else 1
	return 1


static func shop_price(base: String) -> int:
	for e in SHOP:
		if e[0] == base:
			return e[1]
	return -1


static func _r(ok: bool, msg := "", sfx := "") -> Dictionary:
	return {"ok": ok, "msg": msg, "sfx": sfx}


static func valid_name(n: String) -> bool:
	var t := n.strip_edges()
	return t.length() >= 2 and t.length() <= 12


# 로비 조작. 결과 {ok, msg(토스트), sfx}. 아이디/인덱스는 서버에서 그대로 검증되도록 모두 확인
static func apply(s: Dictionary, op: String, args: Array) -> Dictionary:
	match op:
		"create_char":
			if args.size() < 2:
				return _r(false)
			var nm := str(args[0]).strip_edges()
			var cls := str(args[1])
			if not Data.CLASSES.has(cls):
				return _r(false)
			if not valid_name(nm):
				return _r(false, "이름은 2~12자로 정해 주세요")
			if s.characters.size() >= MAX_CHARS:
				return _r(false, "캐릭터는 %d명까지 만들 수 있습니다" % MAX_CHARS)
			for c in s.characters:
				if c.name == nm:
					return _r(false, "같은 이름의 캐릭터가 있습니다")
			var nc := new_character(nm, cls)
			s.characters.append(nc)
			select(s, nc.id)
			return _r(true, "%s %s 캐릭터를 만들었습니다" % [Data.CLASSES[cls].name, nm], "ui")
		"select_char":
			var id := str(args[0]) if args.size() else ""
			for c in s.characters:
				if c.id == id:
					select(s, id)
					return _r(true, "", "ui")
			return _r(false)
		"delete_char":
			var id := str(args[0]) if args.size() else ""
			if s.characters.size() <= 1:
				return _r(false, "마지막 캐릭터는 삭제할 수 없습니다")
			for i in s.characters.size():
				if s.characters[i].id == id:
					s.characters.remove_at(i)
					select(s, s.characters[0].id)
					return _r(true, "캐릭터를 삭제했습니다 (장비/가방 포함)")
			return _r(false)
		"set_skill":
			# [q|e, 스킬 id] - 대기실/인벤토리에서 Q/E 스킬 교체
			if args.size() < 2:
				return _r(false)
			var slot := str(args[0])
			var sid := str(args[1])
			if not (slot in ["q", "e"]) or not (sid in Data.CLASSES[s.cls][slot]):
				return _r(false)
			s.skills[slot] = sid
			return _r(true, "%s 스킬: %s" % [slot.to_upper(), Data.SKILLS[sid].name], "ui")
		"swap_set":
			var c := cur(s)
			c.wset = 2 if int(c.get("wset", 1)) == 1 else 1
			select(s, c.id)
			return _r(true, "무기 세트 %d" % c.wset, "ui")
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
			var v := int(it.value) * int(it.get("count", 1))
			s.gold += v
			return _r(true, "%s 판매: +%dg" % [Data.base_of(it).name, v], "coin")
		"sell_treasure":
			var sum := 0
			var keep := []
			for it in s.stash:
				if Data.base_of(it).slot == "treasure":
					sum += int(it.value) * int(it.get("count", 1))
				else:
					keep.append(it)
			if sum == 0:
				return _r(false, "판매할 보물이 없습니다")
			s.stash.clear()
			s.stash.append_array(keep)
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
			var it := Data.make_item(base)
			it.count = shop_count(base)
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
			select(s, s.active)
			return _r(true, "초기화했습니다")
	return _r(false)


# 무기가 없고 살 돈도 없을 때만 구호 물자
static func needs_relief(s: Dictionary) -> bool:
	if s.equipment.get("w1") != null or s.equipment.get("w2") != null or s.gold >= 40:
		return false
	for it in s.stash:
		if Data.base_of(it).slot == "weapon" and Data.can_equip(it, s.cls):
			return false
	return true


# 입장 시 소지품은 위험에 노출됨 (탈출해야 돌아옴)
static func take_loadout(s: Dictionary) -> Dictionary:
	var c := cur(s)
	var lo := {"cls": c.cls, "name": c.name, "char": c.id, "equipment": c.equipment.duplicate(), "bag": c.bag.duplicate(),
		"skills": c.skills.duplicate(), "wset": 1}
	set_gear(s, empty_equipment(), [])
	s.stats.raids += 1
	c.stats.raids = int(c.stats.get("raids", 0)) + 1
	return lo


# 레이드가 시작되지 못했으면 장비를 되돌림
static func restore_loadout(s: Dictionary, lo: Dictionary) -> void:
	var c := cur(s)
	for k in lo.equipment:
		var it = lo.equipment[k]
		if it == null:
			continue
		if c.equipment.get(k) == null:
			c.equipment[k] = it
		elif not Inv.add_auto(s.stash, Inv.STASH, it):
			s.gold += int(it.value)
	for it in lo.bag:
		if not Inv.add_auto(c.bag, Inv.bag_size(c.cls), it) and not Inv.add_auto(s.stash, Inv.STASH, it):
			s.gold += int(it.value)
	s.stats.raids = maxi(0, s.stats.raids - 1)
	select(s, c.id)


# 레이드 결과 반영. 탈출하면 장비와 가방이 캐릭터에게 그대로 돌아옴
static func apply_result(s: Dictionary, r: Dictionary) -> String:
	var c := cur(s)
	for ch in s.characters:
		if ch.id == r.get("char", c.id):
			c = ch
	s.stats.kills += int(r.kills)
	s.stats.pvp_kills += int(r.pvp_kills)
	if not r.success:
		s.stats.deaths += 1
		c.stats.deaths = int(c.stats.get("deaths", 0)) + 1
		return ""
	s.stats.extracts += 1
	c.stats.extracts = int(c.stats.get("extracts", 0)) + 1
	s.stats.best_haul = maxi(int(s.stats.best_haul), int(r.value))
	var eq := empty_equipment()
	for k in r.equipment:
		if eq.has(k):
			eq[k] = r.equipment[k]
	var sold := 0
	var bag := []
	for it in r.bag:
		var ok = it.has("x") and Inv.fits(bag, Inv.bag_size(c.cls), it, int(it.x), int(it.y), bool(it.get("r", false)))
		if ok:
			bag.append(it)
		elif not Inv.add_auto(s.stash, Inv.STASH, it):
			s.gold += int(it.value)
			sold += int(it.value)
	c.equipment = eq
	c.bag = bag
	select(s, s.active)
	if sold > 0:
		return "보관함이 가득 차 남은 물건을 %dg에 판매했습니다" % sold
	return ""
