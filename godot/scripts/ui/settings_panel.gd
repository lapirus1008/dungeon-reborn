# 설정 창 (로비 · 레이드 메뉴 공용): 화면 / 소리 / 조작 / 키 바꾸기
# 바뀐 값은 setting_changed(key, value)로 알리고, 실제 적용은 Main._on_setting 이 함 (저장도 거기서)
class_name SettingsPanel
extends Control

signal setting_changed(key: String, value)
signal closed

# 바꿀 수 있는 키 (화면에 보이는 이름)
const BINDABLE := [
	["move_forward", "앞으로"], ["move_back", "뒤로"], ["move_left", "왼쪽"], ["move_right", "오른쪽"],
	["jump", "점프"], ["walk", "천천히 걷기"], ["crouch", "앉기"], ["interact", "상호작용 / 줍기"],
	["skill_q", "스킬 Q"], ["skill_e", "스킬 E"], ["reload", "재장전 / 지팡이 충전"], ["torch", "횃불"],
	["weapon1", "무기 세트 1"], ["weapon2", "무기 세트 2"], ["use3", "소모품 3"], ["use4", "소모품 4"], ["use5", "소모품 5"],
	["inventory", "인벤토리"], ["map", "지도"],
]
const WINDOW_MODES := [["borderless", "전체 화면 (테두리 없는 창)"], ["fullscreen", "전체 화면 (독점)"], ["windowed", "창 모드"]]
const FPS_MODES := [
	["adaptive", "적응형 VSync (권장)"], ["vsync", "VSync 켜기"], ["144", "VSync 끄기 · 최대 144"],
	["60", "VSync 끄기 · 최대 60"], ["unlimited", "VSync 끄기 · 제한 없음"],
]

var _waiting_action := "" # 키 바꾸기: 다음에 누르는 키를 기다리는 동작
var _key_buttons := {}
var _tabs: TabContainer


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var p := UI.panel_box(Vector2(640, 560))
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(UI.title("설정"))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_tabs)
	_tabs.add_child(_display_tab())
	_tabs.add_child(_sound_tab())
	_tabs.add_child(_control_tab())
	_tabs.add_child(_keys_tab())
	for i in _tabs.get_tab_count():
		_tabs.set_tab_title(i, ["화면", "소리", "조작", "키 바꾸기"][i])
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(UI.button("닫기 (Esc)", close))
	v.add_child(row)
	visible = false


func open() -> void:
	visible = true
	_refresh_keys()


func close() -> void:
	_waiting_action = ""
	visible = false
	closed.emit()


func _page() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	return v


func _row(parent: Control, label: String, ctrl: Control, hint := "") -> void:
	var h := HBoxContainer.new()
	var l := UI.label(label, 14, UI.MUTED)
	l.custom_minimum_size = Vector2(170, 0)
	h.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctrl)
	parent.add_child(h)
	if hint != "":
		parent.add_child(UI.label(hint, 12, UI.MUTED))


func _option(items: Array, key: String, default_value: String) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(it[1])
	o.selected = maxi(0, items.map(func(t): return t[0]).find(str(SaveData.setting(key, default_value))))
	o.item_selected.connect(func(i): setting_changed.emit(key, items[i][0]))
	return o


func _slider(key: String, mn: float, mx: float, step: float, default_value: float, fmt := "%.0f%%", mul := 100.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value = float(SaveData.setting(key, default_value))
	var val := UI.label(fmt % (s.value * mul), 14)
	val.custom_minimum_size = Vector2(60, 0)
	s.value_changed.connect(func(x):
		val.text = fmt % (x * mul)
		setting_changed.emit(key, x))
	h.add_child(s)
	h.add_child(val)
	return h


func _check(key: String, default_value: bool, text: String) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = bool(SaveData.setting(key, default_value))
	cb.toggled.connect(func(on): setting_changed.emit(key, on))
	return cb


func _display_tab() -> Control:
	var v := _page()
	_row(v, "화면 모드", _option(WINDOW_MODES, "window", "borderless"))
	_row(v, "그래픽 품질", _option([["low", "낮음 (빠름)"], ["mid", "보통"], ["high", "높음 (선명)"]], "quality", "low" if UI.touch else "high"),
		"높음: 그림자·안개·반사광을 모두 켬 · 낮음: 3D 해상도를 낮추고 효과를 줄임")
	v.add_child(_check("render_auto", true, "3D 해상도를 품질에 맞춰 자동으로"))
	_row(v, "3D 해상도", _slider("render_scale", 0.5, 1.0, 0.05, 1.0),
		"자동을 끄면 적용 · 낮추면 빨라지고 흐려짐 (FSR 업스케일)")
	_row(v, "프레임", _option(FPS_MODES, "fps", "adaptive"))
	_row(v, "시야각 (FOV)", _slider("fov", 60.0, 100.0, 1.0, 75.0, "%.0f°", 1.0))
	v.add_child(_check("show_fps", false, "화면 왼쪽 위에 FPS 표시 (F3: 자세히)"))
	return v


func _sound_tab() -> Control:
	var v := _page()
	_row(v, "전체 소리", _slider("vol_master", 0.0, 1.0, 0.05, 0.8))
	_row(v, "효과음", _slider("vol_sfx", 0.0, 1.0, 0.05, 1.0))
	_row(v, "화면 흔들림·타격 효과", _slider("shake", 0.0, 1.0, 0.1, 1.0))
	v.add_child(_check("mute_unfocused", true, "게임 창이 뒤로 가면 소리 끄기"))
	return v


func _control_tab() -> Control:
	var v := _page()
	_row(v, "마우스 감도", _slider("sensitivity", 0.3, 3.0, 0.05, 1.0, "%.2f", 1.0))
	v.add_child(_check("invert_y", false, "마우스 상하 반전"))
	v.add_child(UI.label("좌클릭 공격 (누르고 있으면 차지 → 다 차면 떼서 강공격) · 우클릭 방어\n키는 '키 바꾸기' 탭에서 바꿀 수 있습니다.", 13, UI.MUTED))
	return v


func _keys_tab() -> Control:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := _page()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	v.add_child(UI.label("바꿀 키를 누른 뒤 새 키를 누르세요 (Esc: 취소)", 13, UI.MUTED))
	for b in BINDABLE:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(160, 30)
		var action: String = b[0]
		btn.pressed.connect(func():
			_waiting_action = action
			_refresh_keys())
		_key_buttons[action] = btn
		_row(v, b[1], btn)
	v.add_child(UI.button("기본값으로", func():
		setting_changed.emit("keys", {})
		_refresh_keys()))
	return sc


static func key_name(action: String) -> String:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			return OS.get_keycode_string(k)
	return "-"


func _refresh_keys() -> void:
	for action in _key_buttons:
		_key_buttons[action].text = "새 키를 누르세요..." if action == _waiting_action else key_name(action)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if _waiting_action != "":
			if event.physical_keycode != KEY_ESCAPE:
				var keys: Dictionary = SaveData.setting("keys", {}).duplicate()
				keys[_waiting_action] = int(event.physical_keycode)
				setting_changed.emit("keys", keys)
			_waiting_action = ""
			_refresh_keys()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
