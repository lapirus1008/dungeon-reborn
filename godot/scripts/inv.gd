# 격자 인벤토리 규칙 (가방/보관함/상자 공용)
# 아이템은 {x, y, r(회전)} 위치를 가지며 크기는 Data.item_size (예: 상의 2x3=6칸, 투구 2x2=4칸)
# 오프라인/호스트/온라인 서버 모두 이 규칙으로 이동을 검사한다 (서버 권한)
class_name Inv
extends RefCounted

const STASH := Vector2i(12, 10)
const CONT_W := 6
# 직업마다 가방 크기가 다르다 (가벼운 직업은 넓게, 마법사는 좁게)
# 가방 크기 (가로 10칸): 인간 종족 7줄, 언데드 종족 6줄
const HUMAN_BAG := Vector2i(10, 7)
const UNDEAD_BAG := Vector2i(10, 6)
const BAG := {
	"fighter": HUMAN_BAG, "rogue": HUMAN_BAG, "priest": HUMAN_BAG, "pyromancer": HUMAN_BAG, "swordmaster": HUMAN_BAG, "druid": HUMAN_BAG,
	"deathknight": UNDEAD_BAG, "cryomancer": UNDEAD_BAG,
}


static func bag_size(cls: String) -> Vector2i:
	return BAG.get(cls, HUMAN_BAG)


static func rect_of(it: Dictionary) -> Rect2i:
	return Rect2i(int(it.get("x", 0)), int(it.get("y", 0)), Data.item_size(it).x, Data.item_size(it).y)


static func index_of(list: Array, id: String) -> int:
	for i in list.size():
		if list[i].id == id:
			return i
	return -1


# 위치 (x, y), 회전 r 로 놓을 수 있는지 (ignore_id: 같은 아이템 자신은 무시)
static func fits(list: Array, grid: Vector2i, it: Dictionary, x: int, y: int, r: bool, ignore_id := "") -> bool:
	var sz: Array = Data.base_of(it).get("size", [1, 1])
	var w: int = sz[1] if r else sz[0]
	var h: int = sz[0] if r else sz[1]
	if x < 0 or y < 0 or x + w > grid.x or y + h > grid.y:
		return false
	var rc := Rect2i(x, y, w, h)
	for o in list:
		if o.id == ignore_id or o.id == it.id:
			continue
		if rect_of(o).intersects(rc):
			return false
	return true


# 빈 자리 찾기 (위에서부터, 안 들어가면 회전해서). 없으면 {}
static func find_space(list: Array, grid: Vector2i, it: Dictionary, prefer_r := false) -> Dictionary:
	for r in ([prefer_r, not prefer_r] if Data.base_of(it).get("size", [1, 1])[0] != Data.base_of(it).get("size", [1, 1])[1] else [false]):
		for y in grid.y:
			for x in grid.x:
				if fits(list, grid, it, x, y, r):
					return {"x": x, "y": y, "r": r}
	return {}


# 같은 종류의 겹칠 수 있는 아이템(물약, 금화 등)에 먼저 합침. 남은 수량이 있으면 false
static func merge_into(list: Array, it: Dictionary) -> bool:
	var mx := Data.max_stack(it)
	if mx <= 1:
		return false
	for o in list:
		if o.id != it.id and o.base == it.base and int(o.get("count", 1)) < mx:
			var room: int = mx - int(o.get("count", 1))
			var n := mini(room, int(it.get("count", 1)))
			o.count = int(o.get("count", 1)) + n
			it.count = int(it.get("count", 1)) - n
			if it.count <= 0:
				return true
	return false


static func add_auto(list: Array, grid: Vector2i, it: Dictionary) -> bool:
	if merge_into(list, it):
		return true
	var sp := find_space(list, grid, it, it.get("r", false))
	if sp.is_empty():
		return false
	it.x = sp.x
	it.y = sp.y
	it.r = sp.r
	list.append(it)
	return true


# 큰 것부터 다시 배치. 안 들어가는 것은 반환
static func repack(list: Array, grid: Vector2i) -> Array:
	var items := list.duplicate()
	items.sort_custom(func(a, b):
		var sa: Vector2i = Data.item_size(a)
		var sb: Vector2i = Data.item_size(b)
		return sa.x * sa.y > sb.x * sb.y)
	list.clear()
	var overflow := []
	for it in items:
		it.r = false
		if not add_auto(list, grid, it):
			overflow.append(it)
	return overflow


# 아이템 목록을 담을 만큼 세로로 늘어나는 상자 격자 (가로 CONT_W)
static func pack_container(items: Array) -> Dictionary:
	var h := 4
	while true:
		var list := []
		var ok := true
		var sorted := items.duplicate()
		sorted.sort_custom(func(a, b):
			var sa: Vector2i = Data.item_size(a)
			var sb: Vector2i = Data.item_size(b)
			return sa.x * sa.y > sb.x * sb.y)
		for it in sorted:
			it.r = false
			if not add_auto(list, Vector2i(CONT_W, h), it):
				ok = false
				break
		if ok or h > 60:
			return {"items": list, "gw": CONT_W, "gh": h}
		h += 2
	return {}


# ------------------------------------------------------------------ 이동
# ctx: {cls, equipment, stores: {이름: {list, grid}}}
# src/dst: 저장소 이름("bag", "stash", "cont") 또는 "equip" (장비 칸은 slot 인자)
# x < 0 이면 빈 자리 자동 탐색. 같은 종류의 겹치는 아이템 위에 놓으면 합쳐짐
static func move(ctx: Dictionary, src: String, id: String, dst: String, x: int, y: int, r: bool, slot := "") -> Dictionary:
	var it = _peek(ctx, src, id)
	if it == null:
		return {"ok": false}
	if dst == "equip":
		return _equip(ctx, src, it, slot)
	if not ctx.stores.has(dst) or ctx.stores[dst].has("eq"):
		return {"ok": false}
	var st: Dictionary = ctx.stores[dst]
	if src == dst and x >= 0 and int(it.get("x", -1)) == x and int(it.get("y", -1)) == y and bool(it.get("r", false)) == r:
		return {"ok": false}
	# 겹치기: 놓는 칸에 같은 종류 아이템이 있으면 수량 합치기
	if x >= 0 and Data.max_stack(it) > 1:
		for o in st.list:
			if o.id != it.id and o.base == it.base and rect_of(o).has_point(Vector2i(x, y)):
				var mx := Data.max_stack(it)
				var n := mini(mx - int(o.get("count", 1)), int(it.get("count", 1)))
				if n <= 0:
					return {"ok": false, "msg": "더 이상 겹칠 수 없습니다"}
				o.count = int(o.get("count", 1)) + n
				it.count = int(it.get("count", 1)) - n
				if it.count <= 0:
					_take(ctx, src, it.id)
				return {"ok": true}
	var pos := {}
	if x >= 0:
		if not fits(st.list, st.grid, it, x, y, r, it.id if src == dst else ""):
			return {"ok": false, "msg": "그 자리에 놓을 수 없습니다"}
		pos = {"x": x, "y": y, "r": r}
	else:
		var others: Array = st.list.filter(func(o): return o.id != it.id)
		if src != dst and merge_into(others, it):
			_take(ctx, src, it.id)
			return {"ok": true}
		pos = find_space(others, st.grid, it, it.get("r", false))
		if pos.is_empty():
			return {"ok": false, "msg": "%s에 자리가 없습니다" % store_name(dst)}
	_take(ctx, src, it.id)
	it.erase("loaded") # 석궁을 가방/상자로 내리면 장전이 풀림
	it.x = pos.x
	it.y = pos.y
	it.r = pos.r
	st.list.append(it)
	return {"ok": true}


static func store_name(n: String) -> String:
	match n:
		"bag":
			return "가방"
		"stash":
			return "보관함"
		"cont":
			return "상자"
	return n


static func _peek(ctx: Dictionary, src: String, id: String):
	if src == "equip":
		for s in Data.ALL_SLOTS:
			var e = ctx.equipment.get(s)
			if e != null and e.id == id:
				return e
		return null
	if not ctx.stores.has(src):
		return null
	if ctx.stores[src].has("eq"):
		# 쓰러진 상대의 장비 칸 (꺼내기만 가능)
		var eqs: Dictionary = ctx.stores[src].eq
		for s in eqs:
			if eqs[s] != null and eqs[s].id == id:
				return eqs[s]
		return null
	var i := index_of(ctx.stores[src].list, id)
	return ctx.stores[src].list[i] if i >= 0 else null


static func slot_of(eq: Dictionary, id: String) -> String:
	for s in Data.ALL_SLOTS:
		var e = eq.get(s)
		if e != null and e.id == id:
			return s
	return ""


static func _take(ctx: Dictionary, src: String, id: String) -> void:
	if src == "equip":
		var s := slot_of(ctx.equipment, id)
		if s != "":
			ctx.equipment[s] = null
		return
	if ctx.stores[src].has("eq"):
		var eqs: Dictionary = ctx.stores[src].eq
		for s in eqs:
			if eqs[s] != null and eqs[s].id == id:
				eqs[s] = null
		return
	var list: Array = ctx.stores[src].list
	var i := index_of(list, id)
	if i >= 0:
		list.remove_at(i)


# 이 아이템을 이 직업이 넣을 수 있는 장비 칸
static func valid_slots(it: Dictionary, cls: String) -> Array:
	if not Data.can_equip(it, cls):
		return []
	var out := Data.gear_slots_for(it, cls)
	if cls != "swordmaster":
		out = out.filter(func(s): return not s.begins_with("sw"))
	if cls != "rogue":
		var b := Data.base_of(it)
		if b.slot == "weapon" and b.cat == "dagger":
			out = out.filter(func(s): return not s.ends_with("o"))
	return out


static func _is_2h(it) -> bool:
	return it != null and Data.base_of(it).slot == "weapon" and Data.base_of(it).cat in Data.TWO_HANDED


# 빈 자리를 찾아 넣기 (저장소에 넣을 수 없으면 실패)
static func _stash_back(ctx: Dictionary, store: String, it: Dictionary) -> bool:
	if not ctx.stores.has(store):
		return false
	var st: Dictionary = ctx.stores[store]
	var sp := find_space(st.list, st.grid, it)
	if sp.is_empty():
		return false
	it.x = sp.x
	it.y = sp.y
	it.r = sp.r
	st.list.append(it)
	return true


# 장착: 같은 칸에 있던 장비는 원래 아이템이 있던 저장소로. 양손 무기는 보조 칸을 비움
static func _equip(ctx: Dictionary, src: String, it: Dictionary, slot: String) -> Dictionary:
	var slots := valid_slots(it, ctx.cls)
	if slots.is_empty():
		var b := Data.base_of(it)
		if b.slot == "weapon":
			return {"ok": false, "msg": "%s 전용 무기입니다" % Data.class_names(Data.weapon_classes(b.cat))}
		return {"ok": false, "msg": "장착할 수 없는 물건입니다"}
	var eq: Dictionary = ctx.equipment
	var from := slot_of(eq, it.id) if src == "equip" else ""
	if slot == "" and Data.base_of(it).slot == "consumable":
		# 소모품 우클릭: 같은 종류 칸에 겹치기 → 빈 칸 → 다 차 있으면 첫 번째 칸(3)과 교체
		for q in slots:
			var o = eq.get(q)
			if o != null and o.id != it.id and o.base == it.base and int(o.get("count", 1)) < Data.max_stack(it):
				slot = q
				break
		if slot == "":
			for q in slots:
				if eq.get(q) == null:
					slot = q
					break
		if slot == "":
			slot = slots[0]
	if slot == "":
		# 활성 세트 우선, 빈 칸 우선
		var ws := int(ctx.get("wset", 1))
		var order := slots.duplicate()
		order.sort_custom(func(a, b): return (1 if a.begins_with("w%d" % ws) else 0) > (1 if b.begins_with("w%d" % ws) else 0))
		slot = order[0]
		for s in order:
			if eq.get(s) == null and s != from:
				slot = s
				break
	if not (slot in slots):
		return {"ok": false, "msg": "%s 칸에는 넣을 수 없습니다" % Data.SLOT_NAMES.get(slot, slot)}
	if from == slot:
		return {"ok": false}
	# 양손 무기를 든 세트의 보조 칸에는 넣을 수 없음
	if slot.length() == 3 and slot.ends_with("o") and _is_2h(eq.get(slot.left(2))):
		return {"ok": false, "msg": "양손 무기를 들고 있습니다"}
	var back := src if src != "equip" and not ctx.stores[src].get("eq") is Dictionary else ("bag" if ctx.stores.has("bag") else "stash")
	# 양손 무기: 보조 칸의 장비를 저장소로
	if _is_2h(it) and slot in ["w1", "w2"]:
		var off = eq.get(slot + "o")
		if off != null and off.id != it.id:
			if not _stash_back(ctx, back, off):
				return {"ok": false, "msg": "보조 장비를 넣을 자리가 없습니다"}
			eq[slot + "o"] = null
	var prev = eq.get(slot)
	# 같은 소모품/투척 도구는 수량을 합침
	if prev != null and prev.id != it.id and prev.base == it.base and Data.max_stack(it) > 1:
		var n := mini(Data.max_stack(it) - int(prev.get("count", 1)), int(it.get("count", 1)))
		if n <= 0:
			return {"ok": false, "msg": "더 이상 겹칠 수 없습니다"}
		prev.count = int(prev.get("count", 1)) + n
		it.count = int(it.get("count", 1)) - n
		if it.count <= 0:
			_take(ctx, src, it.id)
		return {"ok": true}
	if src != "equip" and ctx.stores[src].has("eq"):
		# 상대 장비 칸에서 바로 내 장비로: 내 기존 장비는 가방으로
		if prev != null:
			if not _stash_back(ctx, back if back != src else "bag", prev):
				return {"ok": false, "msg": "기존 장비를 넣을 자리가 없습니다"}
			eq[slot] = null
		_take(ctx, src, it.id)
		it.erase("x")
		it.erase("y")
		it.r = false
		eq[slot] = it
		return {"ok": true}
	if src == "equip":
		# 장비 칸끼리 교환 (예: 반지 1 <-> 반지 2, 세트 1 <-> 세트 2)
		if prev != null and not (from in valid_slots(prev, ctx.cls)):
			if not _stash_back(ctx, back, prev):
				return {"ok": false, "msg": "기존 장비를 넣을 자리가 없습니다"}
			prev = null
		eq[slot] = it
		eq[from] = prev
		return {"ok": true}
	var st: Dictionary = ctx.stores[src]
	var others: Array = st.list.filter(func(o): return o.id != it.id)
	var pos := {}
	if prev != null:
		var ox := int(it.get("x", 0))
		var oy := int(it.get("y", 0))
		if fits(others, st.grid, prev, ox, oy, false):
			pos = {"x": ox, "y": oy, "r": false}
		elif fits(others, st.grid, prev, ox, oy, true):
			pos = {"x": ox, "y": oy, "r": true}
		else:
			pos = find_space(others, st.grid, prev)
		if pos.is_empty():
			return {"ok": false, "msg": "%s에 기존 장비를 넣을 자리가 없습니다" % store_name(src)}
	_take(ctx, src, it.id)
	it.erase("x")
	it.erase("y")
	it.r = false
	eq[slot] = it
	if prev != null:
		prev.x = pos.x
		prev.y = pos.y
		prev.r = pos.r
		st.list.append(prev)
	return {"ok": true}


# 오른쪽 클릭: 장착/해제 (그 외에는 order 순서대로 옮길 곳을 찾음)
static func quick(ctx: Dictionary, src: String, id: String, order: Array) -> Dictionary:
	var it = _peek(ctx, src, id)
	if it == null:
		return {"ok": false}
	if src == "equip":
		for dst in order:
			if ctx.stores.has(dst):
				var r := move(ctx, src, id, dst, -1, 0, false)
				if r.ok:
					return r
		return {"ok": false, "msg": "장비를 넣을 자리가 없습니다"}
	if not valid_slots(it, ctx.cls).is_empty():
		return _equip(ctx, src, it, "")
	return transfer(ctx, src, id, order)


# 다른 저장소로 바로 옮기기 (order 중 src가 아닌 첫 번째로)
static func transfer(ctx: Dictionary, src: String, id: String, order: Array) -> Dictionary:
	var last := {"ok": false}
	for dst in order:
		if dst == src or not ctx.stores.has(dst):
			continue
		last = move(ctx, src, id, dst, -1, 0, false)
		if last.ok:
			return last
	return last


# 정리: 크기순 재배치
static func sort_store(list: Array, grid: Vector2i) -> Array:
	return repack(list, grid)
