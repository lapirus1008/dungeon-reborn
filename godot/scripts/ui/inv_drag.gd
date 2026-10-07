# 인벤토리 드래그 앤 드롭 (가방/보관함/상자/장비칸/판매대 공용)
# 드래그 중 R: 회전, 우클릭/Esc: 취소, 패널 밖에 놓기: 버리기(던전)
class_name InvDrag
extends Control

static var inst: InvDrag
static var targets: Array = [] # drop_target(global_pos, drag) 을 가진 Control 들

var active := false
var item: Dictionary = {}
var src := ""
var src_view = null
var rot := false
var grab := Vector2(0.5, 0.5) # 아이템 안에서 잡은 위치 (칸 단위)
var cell := 40.0
var icon_label: Label
# 터치: 제자리에서 짧게 탭하면(드래그 없이) 우클릭과 같은 빠른 장착/사용, 두 번째 손가락 탭 = 회전
var start_pos := Vector2.ZERO
var start_t := 0


func _ready() -> void:
	inst = self
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_label = Label.new()
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_label.visible = false
	add_child(icon_label)


static func register(t: Control) -> void:
	if not targets.has(t):
		targets.append(t)


static func unregister(t: Control) -> void:
	targets.erase(t)


static func is_active() -> bool:
	return inst != null and inst.active


static func begin(it: Dictionary, from: String, view, grab_cells: Vector2, cell_px: float) -> void:
	if inst == null:
		return
	inst.active = true
	inst.item = it
	inst.src = from
	inst.src_view = view
	inst.rot = bool(it.get("r", false))
	inst.grab = grab_cells
	inst.cell = cell_px
	inst.start_pos = inst.get_global_mouse_position()
	inst.start_t = Time.get_ticks_msec()
	inst.icon_label.text = Data.base_of(it).icon
	inst.icon_label.add_theme_font_size_override("font_size", int(cell_px * 0.6))
	inst.icon_label.visible = true
	UI.hide_tip()
	inst.queue_redraw()


func size_cells() -> Vector2i:
	var sz: Array = Data.base_of(item).get("size", [1, 1])
	return Vector2i(sz[1], sz[0]) if rot else Vector2i(sz[0], sz[1])


# 놓일 아이템의 왼쪽 위 (화면 좌표, 대상 칸 크기 기준)
func top_left(target_cell: float) -> Vector2:
	return get_global_mouse_position() - grab * target_cell


func _process(_dt: float) -> void:
	if active:
		queue_redraw()
		for t in targets:
			if is_instance_valid(t) and t.is_visible_in_tree():
				t.queue_redraw()


func _draw() -> void:
	if not active:
		return
	var sz := size_cells()
	var r := Rect2(top_left(cell) - global_position, Vector2(sz) * cell)
	var col: Color = Data.RARITIES[int(item.get("rarity", 0))].color
	draw_rect(r, Color(col.r, col.g, col.b, 0.25))
	draw_rect(r, col, false, 2.0)
	icon_label.position = r.position
	icon_label.size = r.size


func _input(ev: InputEvent) -> void:
	if not active:
		return
	if ev is InputEventScreenTouch and ev.pressed and ev.index > 0:
		rot = not rot
		grab = Vector2(grab.y, grab.x)
		Sfx.play("ui")
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.physical_keycode == KEY_R:
			# 회전: 잡은 위치도 함께 돌림
			rot = not rot
			grab = Vector2(grab.y, grab.x)
			Sfx.play("ui")
			get_viewport().set_input_as_handled()
		elif ev.physical_keycode == KEY_ESCAPE:
			cancel()
			get_viewport().set_input_as_handled()
	elif ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
			cancel()
			get_viewport().set_input_as_handled()
		elif ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
			_finish(get_global_mouse_position())
			get_viewport().set_input_as_handled()


func cancel() -> void:
	active = false
	icon_label.visible = false
	queue_redraw()


func _finish(mp: Vector2) -> void:
	var it := item
	var from := src
	var view = src_view
	var r := rot
	cancel()
	if UI.touch and mp.distance_to(start_pos) < 14.0 and Time.get_ticks_msec() - start_t < 350:
		if view != null and is_instance_valid(view):
			view.on_op.call("quick", [from, it.id])
		return
	for t in targets:
		if not is_instance_valid(t) or not t.is_visible_in_tree():
			continue
		if not t.get_global_rect().has_point(mp):
			continue
		var d: Dictionary = t.drop_target(mp, self)
		if d.is_empty():
			continue
		if d.dst == "sell":
			t.on_op.call("sell", [from, it.id])
		else:
			t.on_op.call("move", [from, it.id, d.dst, d.get("x", -1), d.get("y", -1), r, d.get("slot", "")])
		return
	# 아무 칸에도 놓지 않음: 던전이면 바닥에 버리기 (원본 뷰가 허용할 때)
	if view != null and is_instance_valid(view) and view.drop_outside and not _over_any_panel(mp):
		view.on_op.call("drop", [from, it.id])


# 인벤토리 패널 위에 놓았으면 버리지 않음 (빈 여백에 실수로 놓는 경우)
func _over_any_panel(mp: Vector2) -> bool:
	for t in targets:
		if is_instance_valid(t) and t.is_visible_in_tree():
			var p = t.get_parent()
			while p != null and not (p is PanelContainer):
				p = p.get_parent()
			if p != null and (p as Control).get_global_rect().has_point(mp):
				return true
	return false
