# 장비창 (던전본 배치)
#  세트1(주/보조, 1키) · 머리 · 세트2(주/보조, 2키) / 상의 · 목걸이
#  횃불(G) · 반지 · 하의 · 반지 · 소모품 3/4/5 / 장갑(하의 왼쪽 아래) · 신발(하의 오른쪽 아래) / 검 슬롯 4칸(소드마스터)
# 드래그로 장착/교체 · 우클릭: 해제 · Shift+클릭: 버리기(던전) / 보관함으로
# store가 "equip"가 아니면 (쓰러진 상대의 장비) 꺼내기만 가능
class_name EquipView
extends Control

# 칸 위치와 크기 (칸 단위, 8 x 8)
const LAYOUT := {
	"w1": Rect2i(0, 0, 1, 3), "w1o": Rect2i(1, 0, 1, 3),
	"head": Rect2i(3, 0, 2, 2),
	"w2": Rect2i(6, 0, 1, 3), "w2o": Rect2i(7, 0, 1, 3),
	"chest": Rect2i(3, 2, 2, 3), "necklace": Rect2i(5, 2, 1, 1),
	"torch": Rect2i(0, 5, 1, 2),
	"ring1": Rect2i(2, 5, 1, 1), "legs": Rect2i(3, 5, 2, 3), "ring2": Rect2i(5, 5, 1, 1),
	"hands": Rect2i(1, 6, 2, 2), "feet": Rect2i(5, 6, 2, 2),
	"c3": Rect2i(7, 5, 1, 1), "c4": Rect2i(7, 6, 1, 1), "c5": Rect2i(7, 7, 1, 1),
	"sw1": Rect2i(2, 8, 1, 1), "sw2": Rect2i(3, 8, 1, 1), "sw3": Rect2i(4, 8, 1, 1), "sw4": Rect2i(5, 8, 1, 1),
}
const GRID_W := 8
const GRID_H := 8

var equipment: Dictionary = {}
var cls := "fighter"
var wset := 1
var cell := 36.0
var on_op: Callable
var hint := "우클릭: 해제 · 드래그: 옮기기"
var drop_outside := false
var store := "equip"
var _hover := ""


func _init(cell_px := 36.0) -> void:
	cell = cell_px
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(GRID_W, GRID_H) * cell
	size = custom_minimum_size


func _enter_tree() -> void:
	InvDrag.register(self)


func _exit_tree() -> void:
	InvDrag.unregister(self)


# 양손 무기를 든 세트는 주무기 칸이 보조 칸까지 차지
func _two_handed(set_slot: String) -> bool:
	var it = equipment.get(set_slot)
	return it != null and Data.base_of(it).slot == "weapon" and Data.base_of(it).cat in Data.TWO_HANDED


func _slots() -> Array:
	var out := []
	for s in LAYOUT:
		if s.begins_with("sw") and cls != "swordmaster":
			continue
		if s in ["w1o", "w2o"] and _two_handed(s.left(2)):
			continue
		out.append(s)
	return out


func set_equipment(eq: Dictionary, c: String, ws := 1) -> void:
	equipment = eq
	cls = c
	wset = ws
	custom_minimum_size = Vector2(GRID_W, GRID_H + (1 if cls == "swordmaster" else 0)) * cell
	size = custom_minimum_size
	for ch in get_children():
		ch.queue_free()
	for s in _slots():
		var r := _rect(s)
		var it = equipment.get(s)
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.position = r.position
		l.size = r.size
		if it != null:
			l.text = Data.base_of(it).icon
			l.add_theme_font_size_override("font_size", int(minf(r.size.x, r.size.y) * 0.5))
			if int(it.get("count", 1)) > 1:
				# 수량은 칸 오른쪽 아래 작게
				var n := Label.new()
				n.mouse_filter = Control.MOUSE_FILTER_IGNORE
				n.text = str(int(it.count))
				n.add_theme_font_size_override("font_size", 10)
				n.add_theme_color_override("font_outline_color", Color.BLACK)
				n.add_theme_constant_override("outline_size", 4)
				n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				n.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
				n.position = r.position
				n.size = r.size - Vector2(2, 0)
				add_child(n)
		else:
			l.text = _short_name(s, r)
			l.add_theme_font_size_override("font_size", 10)
			l.add_theme_color_override("font_color", UI.MUTED)
		add_child(l)
	queue_redraw()


func _short_name(s: String, r: Rect2) -> String:
	var n: String = Data.SLOT_NAMES[s]
	# 세로로 긴 1칸 너비 슬롯은 글자를 세로로
	if r.size.x < cell * 1.2 and r.size.y > cell * 1.5:
		return "\n".join(n.replace(" ", "").split(""))
	if r.size.x < cell * 1.2:
		if s.begins_with("c"):
			return n
		return {"sw": "검"}.get(s.left(2), n.left(2))
	return n


func _rect(s: String) -> Rect2:
	var r: Rect2i = LAYOUT[s]
	if s in ["w1", "w2"] and _two_handed(s):
		r = r.merge(LAYOUT[s + "o"])
	return Rect2(Vector2(r.position) * cell, Vector2(r.size) * cell).grow(-2)


func slot_at(local: Vector2) -> String:
	for s in _slots():
		if _rect(s).has_point(local):
			return s
	return ""


func _draw() -> void:
	var drag_ok := []
	if InvDrag.is_active() and store == "equip":
		drag_ok = Inv.valid_slots(InvDrag.inst.item, cls)
	# 무기 세트 이름 (사용 중인 세트는 금색 테두리)
	var font := get_theme_default_font()
	for n in [1, 2]:
		var lo: Rect2i = LAYOUT["w%d" % n].merge(LAYOUT["w%do" % n])
		var ar := Rect2(Vector2(lo.position) * cell, Vector2(lo.size) * cell).grow(-2).grow(2)
		var on = n == wset
		if on:
			draw_rect(ar, Color(1.0, 0.82, 0.3, 0.85), false, 2.0)
		draw_string(font, Vector2(ar.position.x, ar.end.y + 13), "세트 %d (%d키)" % [n, n], HORIZONTAL_ALIGNMENT_CENTER, ar.size.x, 11, Color(1.0, 0.82, 0.3) if on else UI.MUTED)
	for s in _slots():
		var r := _rect(s)
		var it = equipment.get(s)
		draw_rect(r, Color(0.05, 0.04, 0.03, 0.92))
		if it != null:
			var col: Color = Data.RARITIES[int(it.get("rarity", 0))].color
			draw_rect(r, Color(col.r, col.g, col.b, 0.22 if s == _hover else 0.13))
			draw_rect(r, col, false, 2.0)
		else:
			draw_rect(r, Color("#3a3022"), false, 1.0)
		if s in drag_ok:
			draw_rect(r, Color(1.0, 0.82, 0.3, 0.9 if get_global_rect().has_point(get_global_mouse_position()) and slot_at(get_local_mouse_position()) == s else 0.5), false, 2.0)


func drop_target(gp: Vector2, _d) -> Dictionary:
	var s := slot_at(gp - global_position)
	if s == "" or store != "equip":
		return {}
	return {"dst": "equip", "slot": s}


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var s := slot_at(ev.position)
		if s != _hover:
			_hover = s
			queue_redraw()
			var it = equipment.get(s) if s != "" else null
			if it != null and not InvDrag.is_active():
				UI.show_tip(UI.item_tip(it, hint))
			else:
				UI.hide_tip()
	elif ev is InputEventMouseButton and ev.pressed:
		var s := slot_at(ev.position)
		var it = equipment.get(s) if s != "" else null
		if it == null:
			return
		accept_event()
		if ev.button_index == MOUSE_BUTTON_RIGHT:
			UI.hide_tip()
			on_op.call("quick", [store, it.id])
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.shift_pressed:
				on_op.call("transfer", [store, it.id])
			else:
				var r := _rect(s)
				InvDrag.begin(it, store, self, Vector2(0.5, 0.5), cell)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != "":
		_hover = ""
		UI.hide_tip()
		queue_redraw()
