# 안드로이드(터치) 조작: 왼쪽 아무 곳 = 떠다니는 조이스틱(이동), 오른쪽 드래그 = 시점,
# 오른쪽 버튼 = 공격/방어/점프/F/Q/E/앉기, 아래 가운데 = 1~5·횃불·재장전, 왼쪽 위 = 메뉴/가방/지도/걷기.
# 버튼은 키보드와 같은 입력 동작(InputMap 액션)을 눌렀다 떼므로 게임 코드는 PC와 똑같이 동작함
class_name TouchControls
extends Control

const LOOK_MUL := 2.2 # 마우스 감도 대비 터치 시점 회전 배율
const JOY_R := 120.0

var main: Node
# 버튼: id, action, pos, r, label, kind("hold"|"toggle"|"tap"), look(누른 채 드래그하면 시점도 돌림), group("game"|"top")
var buttons: Array = []
var touches := {} # 터치 index -> {kind: "joy"|"look"|"btn", btn, origin, last}
var joy_origin := Vector2.ZERO
var joy_pos := Vector2.ZERO
var joy_index := -1
var toggled := {} # action -> bool (앉기/걷기)
var _last_size := Vector2.ZERO
var _mode := "" # "game" | "panel" | ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _layout() -> void:
	var s := get_viewport_rect().size
	_last_size = s
	var W := s.x
	var H := s.y
	buttons = [
		{"id": "attack", "action": "attack", "pos": Vector2(W - 170, H - 190), "r": 88.0, "label": "공격", "kind": "hold", "look": true, "group": "game"},
		{"id": "block", "action": "secondary", "pos": Vector2(W - 345, H - 105), "r": 62.0, "label": "방어", "kind": "hold", "look": true, "group": "game"},
		{"id": "jump", "action": "jump", "pos": Vector2(W - 110, H - 385), "r": 52.0, "label": "점프", "kind": "hold", "group": "game"},
		{"id": "interact", "action": "interact", "pos": Vector2(W - 345, H - 270), "r": 56.0, "label": "확인", "kind": "hold", "group": "game"},
		{"id": "q", "action": "skill_q", "pos": Vector2(W - 490, H - 95), "r": 50.0, "label": "1스킬", "kind": "hold", "look": true, "group": "game"},
		{"id": "e", "action": "skill_e", "pos": Vector2(W - 500, H - 230), "r": 50.0, "label": "2스킬", "kind": "hold", "look": true, "group": "game"},
		{"id": "crouch", "action": "crouch", "pos": Vector2(W - 110, H - 530), "r": 44.0, "label": "앉기", "kind": "toggle", "group": "game"},
		{"id": "walk", "action": "walk", "pos": Vector2(W - 250, H - 460), "r": 40.0, "label": "걷기", "kind": "toggle", "group": "game"},
		{"id": "menu", "action": "menu", "pos": Vector2(60, 60), "r": 38.0, "label": "☰", "kind": "tap", "group": "top"},
		{"id": "inv", "action": "inventory", "pos": Vector2(150, 60), "r": 38.0, "label": "가방", "kind": "tap", "group": "top"},
		{"id": "map", "action": "map", "pos": Vector2(240, 60), "r": 38.0, "label": "지도", "kind": "tap", "group": "game"},
	]
	# 아래 가운데 (HUD 단축칸 바로 위): 무기 1·2, 소모품 3·4·5, 횃불, 재장전
	var row := [["weapon1", "주무기"], ["weapon2", "보조"], ["use3", "소모1"], ["use4", "소모2"], ["use5", "소모3"], ["torch", "횃불"], ["reload", "장전"]]
	var x0 := W * 0.5 - (row.size() - 1) * 40.0
	for i in row.size():
		buttons.append({"id": row[i][0], "action": row[i][0], "pos": Vector2(x0 + i * 80.0, H - 150), "r": 34.0, "label": row[i][1], "kind": "tap", "group": "game"})


func _process(_dt: float) -> void:
	if get_viewport_rect().size != _last_size:
		_layout()
	var m := _current_mode()
	if m != _mode:
		if m != "game":
			_release_all()
		_mode = m
		visible = m != ""
	queue_redraw()


func _current_mode() -> String:
	if main == null or main.mode != "raid" or main.game == null or not main.game.running:
		return ""
	var g = main.game
	if g.result != null:
		return ""
	if g.menu_open or main.hud.is_panel_open():
		return "panel"
	return "game"


func _btn_at(p: Vector2):
	for b in buttons:
		if _mode == "panel" and b.group != "top":
			continue
		if p.distance_to(b.pos) <= b.r * 1.15:
			return b
	return null


func _send(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func _input(ev: InputEvent) -> void:
	if _mode == "":
		return
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_touch_down(ev.index, ev.position)
		else:
			_touch_up(ev.index)
	elif ev is InputEventScreenDrag:
		_touch_move(ev.index, ev.position, ev.relative)


func _touch_down(idx: int, p: Vector2) -> void:
	var b = _btn_at(p)
	if b != null:
		touches[idx] = {"kind": "btn", "btn": b, "last": p}
		match b.kind:
			"hold":
				_send(b.action, true)
			"tap":
				_send(b.action, true)
				_send(b.action, false)
			"toggle":
				var on: bool = not toggled.get(b.action, false)
				toggled[b.action] = on
				_send(b.action, on)
		get_viewport().set_input_as_handled()
		return
	if _mode != "game":
		return # 패널이 열려 있으면 인벤토리 등 화면 조작으로 넘김
	var W := get_viewport_rect().size.x
	if p.x < W * 0.4 and joy_index < 0:
		joy_index = idx
		joy_origin = p
		joy_pos = p
		touches[idx] = {"kind": "joy"}
	else:
		touches[idx] = {"kind": "look", "last": p}
	get_viewport().set_input_as_handled()


func _touch_move(idx: int, p: Vector2, rel: Vector2) -> void:
	var t = touches.get(idx)
	if t == null:
		return
	match t.kind:
		"joy":
			joy_pos = p
			_apply_joy()
		"look":
			_look(rel)
		"btn":
			if t.btn.get("look", false):
				_look(rel)
	get_viewport().set_input_as_handled()


func _touch_up(idx: int) -> void:
	var t = touches.get(idx)
	if t == null:
		return
	touches.erase(idx)
	match t.kind:
		"joy":
			joy_index = -1
			joy_pos = joy_origin
			_apply_joy()
		"btn":
			if t.btn.kind == "hold":
				_send(t.btn.action, false)
	get_viewport().set_input_as_handled()


func _look(rel: Vector2) -> void:
	var g = main.game
	if g == null or g.player == null or not g.player.alive or g.player.done:
		return
	g.player.look(rel, g.sensitivity * LOOK_MUL)


func _apply_joy() -> void:
	var v := (joy_pos - joy_origin) / JOY_R
	if v.length() > 1.0:
		v = v.normalized()
	if joy_index < 0 or v.length() < 0.12:
		v = Vector2.ZERO
	_axis("move_right", maxf(v.x, 0.0))
	_axis("move_left", maxf(-v.x, 0.0))
	_axis("move_back", maxf(v.y, 0.0))
	_axis("move_forward", maxf(-v.y, 0.0))


func _axis(action: String, s: float) -> void:
	if s > 0.0:
		Input.action_press(action, s)
	elif Input.is_action_pressed(action):
		Input.action_release(action)


func _release_all() -> void:
	for idx in touches.keys():
		var t = touches[idx]
		if t.kind == "btn" and t.btn.kind == "hold":
			_send(t.btn.action, false)
	touches.clear()
	joy_index = -1
	joy_pos = joy_origin
	_apply_joy()


func _draw() -> void:
	if _mode == "":
		return
	var font: Font = UI.font
	if _mode == "game" and joy_index >= 0:
		draw_circle(joy_origin, JOY_R, Color(1, 1, 1, 0.08))
		draw_arc(joy_origin, JOY_R, 0.0, TAU, 48, Color(1, 1, 1, 0.3), 2.0)
		var k := (joy_pos - joy_origin).limit_length(JOY_R)
		draw_circle(joy_origin + k, 46.0, Color(1, 1, 1, 0.3))
	var held := {}
	for t in touches.values():
		if t.kind == "btn":
			held[t.btn.id] = true
	for b in buttons:
		if _mode == "panel" and b.group != "top":
			continue
		var on: bool = held.has(b.id) or toggled.get(b.action, false)
		draw_circle(b.pos, b.r, Color(0.9, 0.8, 0.6, 0.35) if on else Color(0.05, 0.05, 0.05, 0.4))
		draw_arc(b.pos, b.r, 0.0, TAU, 40, Color(0.95, 0.88, 0.7, 0.75 if on else 0.45), 2.0)
		var label: String = _label(b)
		var fs := int(clampf(b.r * 0.5, 16.0, 34.0))
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		while w > b.r * 1.7 and fs > 12:
			fs -= 1
			w = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, b.pos + Vector2(-w * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))


# 손에 든 것·바라보는 대상에 따라 버튼 이름이 바뀜 (처음 하는 사람도 알 수 있게)
func _label(b: Dictionary) -> String:
	if b.id == "menu" and _mode == "panel":
		return "✕"
	var g = main.game if main != null else null
	var p = g.player if g != null else null
	if p == null:
		return b.label
	match b.id:
		"attack":
			if p.held == "torch":
				return "휘두름"
			if p.held != "":
				var it = p.equipment.get(p.held)
				if it != null and Data.base_of(it).has("throw"):
					return "던지기"
				return "사용"
		"block":
			if p.held == "torch":
				return "던지기"
			if p.held != "":
				return "넣기"
		"interact":
			var o = g.interact_target
			if o != null:
				match o.kind:
					"door":
						return "닫기" if o.open else "열기"
					"chest":
						return "열기" if not o.opened else "확인"
					"item":
						return "줍기"
					"corpse":
						return "뒤지기"
					"shrine", "stone":
						return "사용"
	return b.label
