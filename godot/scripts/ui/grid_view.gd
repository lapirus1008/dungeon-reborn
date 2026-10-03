# 격자 인벤토리 화면 (가방/보관함/상자)
# 왼쪽 드래그: 옮기기 · 드래그 중 R: 회전 · 우클릭: 장착/해제/사용 · Shift+클릭: 빠른 이동 · Ctrl+클릭: 판매(로비)
class_name GridView
extends Control

const BG := Color(0.05, 0.04, 0.03, 0.92)
const LINE := Color(0.23, 0.19, 0.13)

var store := "bag"
var grid := Vector2i(9, 5)
var items: Array = []
var cell := 40.0
var on_op: Callable # (op, args)
var hint := ""
var drop_outside := false # 던전: 패널 밖에 놓으면 버리기
var allow_sell := false
var _hover_id := ""


func _init(store_name := "bag", cell_px := 40.0) -> void:
	store = store_name
	cell = cell_px
	mouse_filter = Control.MOUSE_FILTER_STOP


func _enter_tree() -> void:
	InvDrag.register(self)


func _exit_tree() -> void:
	InvDrag.unregister(self)


func set_items(list: Array, g: Vector2i) -> void:
	items = list
	grid = g
	custom_minimum_size = Vector2(g) * cell
	size = custom_minimum_size
	for c in get_children():
		c.queue_free()
	for it in items:
		var r := _rect(it)
		var l := Label.new()
		l.text = Data.base_of(it).icon
		l.add_theme_font_size_override("font_size", int(minf(r.size.x, r.size.y) * 0.55))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.position = r.position
		l.size = r.size
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
	queue_redraw()


func _rect(it: Dictionary) -> Rect2:
	var sz: Vector2i = Data.item_size(it)
	return Rect2(Vector2(int(it.get("x", 0)), int(it.get("y", 0))) * cell, Vector2(sz) * cell)


func item_at(local: Vector2):
	for it in items:
		if _rect(it).grow(-1).has_point(local):
			return it
	return null


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	for x in grid.x + 1:
		draw_line(Vector2(x * cell, 0), Vector2(x * cell, grid.y * cell), LINE)
	for y in grid.y + 1:
		draw_line(Vector2(0, y * cell), Vector2(grid.x * cell, y * cell), LINE)
	for it in items:
		var r := _rect(it).grow(-2)
		var col: Color = Data.RARITIES[int(it.get("rarity", 0))].color
		var dragging: bool = InvDrag.is_active() and InvDrag.inst.item.id == it.id
		draw_rect(r, Color(col.r, col.g, col.b, 0.06 if dragging else (0.22 if it.id == _hover_id else 0.13)))
		draw_rect(r, Color(col.r, col.g, col.b, 0.35 if dragging else 0.95), false, 2.0)
	# 드래그 중: 놓일 자리 미리 보기 (초록 = 가능, 빨강 = 불가)
	if InvDrag.is_active() and get_global_rect().has_point(get_global_mouse_position()):
		var d := InvDrag.inst
		var p := _cell_of(d.top_left(cell))
		var sz := d.size_cells()
		var ok := Inv.fits(items, grid, d.item, p.x, p.y, d.rot, d.item.id if d.src == store else "")
		draw_rect(Rect2(Vector2(p) * cell, Vector2(sz) * cell), Color(0.3, 0.9, 0.4, 0.25) if ok else Color(0.95, 0.25, 0.2, 0.25))


func _cell_of(global_top_left: Vector2) -> Vector2i:
	var l := global_top_left - global_position
	return Vector2i(roundi(l.x / cell), roundi(l.y / cell))


func drop_target(_gp: Vector2, d) -> Dictionary:
	var p := _cell_of(d.top_left(cell))
	return {"dst": store, "x": p.x, "y": p.y}


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var it = item_at(ev.position)
		var id: String = it.id if it != null else ""
		if id != _hover_id:
			_hover_id = id
			queue_redraw()
			if it != null and not InvDrag.is_active():
				UI.show_tip(UI.item_tip(it, hint))
			else:
				UI.hide_tip()
	elif ev is InputEventMouseButton and ev.pressed:
		var it = item_at(ev.position)
		if it == null:
			return
		accept_event()
		if ev.button_index == MOUSE_BUTTON_RIGHT:
			UI.hide_tip()
			on_op.call("quick", [store, it.id])
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.shift_pressed:
				on_op.call("transfer", [store, it.id])
			elif ev.ctrl_pressed and allow_sell:
				on_op.call("sell", [store, it.id])
			else:
				var r := _rect(it)
				InvDrag.begin(it, store, self, (ev.position - r.position) / cell, cell)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover_id != "":
		_hover_id = ""
		UI.hide_tip()
		queue_redraw()
