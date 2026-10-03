# 격자 인벤토리 규칙 (가방/보관함/상자 공용)
# 아이템은 {x, y, r(회전)} 위치를 가지며 크기는 Data.item_size (예: 상의 2x3=6칸, 투구 2x2=4칸)
# 오프라인/호스트/온라인 서버 모두 이 규칙으로 이동을 검사한다 (서버 권한)
class_name Inv
extends RefCounted

const STASH := Vector2i(12, 10)
const CONT_W := 6
# 직업마다 가방 크기가 다르다 (가벼운 직업은 넓게, 마법사는 좁게)
const BAG := {
	"fighter": Vector2i(9, 5), "swordmaster": Vector2i(9, 5), "rogue": Vector2i(10, 6), "deathknight": Vector2i(9, 5),
	"druid": Vector2i(9, 5), "pyromancer": Vector2i(8, 5), "cryomancer": Vector2i(8, 5), "priest": Vector2i(9, 5),
}


static func bag_size(cls: String) -> Vector2i:
	return BAG.get(cls, Vector2i(9, 5))


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


static func add_auto(list: Array, grid: Vector2i, it: Dictionary) -> bool:
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
# src/dst: 저장소 이름("bag", "stash", "cont") 또는 "equip" (dst의 slot은 x 자리에 문자열로 오지 않으므로 별도 인자)
# x < 0 이면 빈 자리 자동 탐색
static func move(ctx: Dictionary, src: String, id: String, dst: String, x: int, y: int, r: bool, slot := "") -> Dictionary:
	var it = _peek(ctx, src, id)
	if it == null:
		return {"ok": false}
	if dst == "equip":
		return _equip(ctx, src, it, slot)
	if not ctx.stores.has(dst):
		return {"ok": false}
	var st: Dictionary = ctx.stores[dst]
	if src == dst and x >= 0 and int(it.get("x", -1)) == x and int(it.get("y", -1)) == y and bool(it.get("r", false)) == r:
		return {"ok": false}
	var pos := {}
	if x >= 0:
		if not fits(st.list, st.grid, it, x, y, r, it.id if src == dst else ""):
			return {"ok": false, "msg": "그 자리에 놓을 수 없습니다"}
		pos = {"x": x, "y": y, "r": r}
	else:
		var others: Array = st.list.filter(func(o): return o.id != it.id)
		pos = find_space(others, st.grid, it, it.get("r", false))
		if pos.is_empty():
			return {"ok": false, "msg": "%s에 자리가 없습니다" % store_name(dst)}
	_take(ctx, src, it.id)
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
		for s in Data.GEAR_SLOTS:
			var e = ctx.equipment.get(s)
			if e != null and e.id == id:
				return e
		return null
	if not ctx.stores.has(src):
		return null
	var i := index_of(ctx.stores[src].list, id)
	return ctx.stores[src].list[i] if i >= 0 else null


static func _take(ctx: Dictionary, src: String, id: String) -> void:
	if src == "equip":
		for s in Data.GEAR_SLOTS:
			var e = ctx.equipment.get(s)
			if e != null and e.id == id:
				ctx.equipment[s] = null
		return
	var list: Array = ctx.stores[src].list
	var i := index_of(list, id)
	if i >= 0:
		list.remove_at(i)


# 장착: 같은 칸에 있던 장비는 원래 아이템이 있던 저장소로 (자리가 없으면 실패)
static func _equip(ctx: Dictionary, src: String, it: Dictionary, slot: String) -> Dictionary:
	if not Data.can_equip(it, ctx.cls):
		var b := Data.base_of(it)
		if b.slot == "weapon":
			return {"ok": false, "msg": "%s 전용 무기입니다" % Data.class_names(b.classes)}
		return {"ok": false, "msg": "장착할 수 없는 물건입니다"}
	var slots := Data.gear_slots_for(it)
	if slot == "":
		slot = slots[0]
		for s in slots:
			if ctx.equipment.get(s) == null:
				slot = s
				break
	if not (slot in slots):
		return {"ok": false, "msg": "%s 칸에는 넣을 수 없습니다" % Data.SLOT_NAMES.get(slot, slot)}
	if src == "equip":
		# 반지 1 <-> 반지 2 교환
		var from := ""
		for s in Data.GEAR_SLOTS:
			var e = ctx.equipment.get(s)
			if e != null and e.id == it.id:
				from = s
		if from == slot:
			return {"ok": false}
		var other = ctx.equipment.get(slot)
		ctx.equipment[slot] = it
		ctx.equipment[from] = other
		return {"ok": true}
	var prev = ctx.equipment.get(slot)
	var st: Dictionary = ctx.stores[src]
	var others: Array = st.list.filter(func(o): return o.id != it.id)
	var pos := {}
	if prev != null:
		# 꺼낸 자리 근처에 우선 (원래 자리에 그대로 들어가면 그 자리)
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
	ctx.equipment[slot] = it
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
	if Data.is_gear(it) and Data.can_equip(it, ctx.cls):
		return _equip(ctx, src, it, "")
	return transfer(ctx, src, id, order)


# Shift+클릭: 다른 저장소로 바로 옮기기 (order 중 src가 아닌 첫 번째로)
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
