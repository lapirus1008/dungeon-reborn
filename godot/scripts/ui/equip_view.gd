# 장비창 (인형 배치): 무기/머리/상의/장갑/하의/신발/목걸이/반지 2
# 드래그로 장착/교체 · 우클릭: 해제 · Shift+클릭: 다른 칸(보관함/상자)으로
class_name EquipView
extends Control

# 칸 위치와 크기 (칸 단위)
const LAYOUT := {
	"weapon": Rect2i(0, 2, 2, 4), "head": Rect2i(2, 0, 2, 2), "necklace": Rect2i(4, 1, 1, 1),
	"chest": Rect2i(2, 2, 2, 3), "hands": Rect2i(4, 2, 2, 2), "ring1": Rect2i(4, 4, 1, 1), "ring2": Rect2i(5, 4, 1, 1),
	"legs": Rect2i(2, 5, 2, 3), "feet": Rect2i(4, 6, 2, 2),
}

var equipment: Dictionary = {}
var cls := "fighter"
var cell := 36.0
var on_op: Callable
var hint := "우클릭: 해제 · 드래그: 옮기기"
var drop_outside := false
var _hover := ""


func _init(cell_px := 36.0) -> void:
	cell = cell_px
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(6, 8) * cell
	size = custom_minimum_size


func _enter_tree() -> void:
	InvDrag.register(self)


func _exit_tree() -> void:
	InvDrag.unregister(self)


func set_equipment(eq: Dictionary, c: String) -> void:
	equipment = eq
	cls = c
	for ch in get_children():
		ch.queue_free()
	for s in LAYOUT:
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
			l.add_theme_font_size_override("font_size", int(minf(r.size.x, r.size.y) * 0.55))
		else:
			l.text = Data.SLOT_NAMES[s]
			l.add_theme_font_size_override("font_size", 11)
			l.add_theme_color_override("font_color", UI.MUTED)
		add_child(l)
	queue_redraw()


func _rect(s: String) -> Rect2:
	var r: Rect2i = LAYOUT[s]
	return Rect2(Vector2(r.position) * cell, Vector2(r.size) * cell).grow(-2)


func slot_at(local: Vector2) -> String:
	for s in LAYOUT:
		if _rect(s).has_point(local):
			return s
	return ""


func _draw() -> void:
	var drag_ok := []
	if InvDrag.is_active() and Data.can_equip(InvDrag.inst.item, cls):
		drag_ok = Data.gear_slots_for(InvDrag.inst.item)
	for s in LAYOUT:
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
	if s == "":
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
			on_op.call("quick", ["equip", it.id])
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.shift_pressed:
				on_op.call("transfer", ["equip", it.id])
			else:
				var r := _rect(s)
				InvDrag.begin(it, "equip", self, Vector2(0.5, 0.5), cell)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != "":
		_hover = ""
		UI.hide_tip()
		queue_redraw()
