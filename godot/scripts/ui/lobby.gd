# 로비: 캐릭터(직업별) 선택/생성, 장비·Q/E 스킬, 가방, 보관함, 상인, 기록
class_name Lobby
extends Control

signal start_raid(map: String)

const SHOP := Account.SHOP

var tab := "stash"
var class_box: VBoxContainer
var skill_box: VBoxContainer
var create_cls := "fighter"
var create_name := ""
var create_skills := {} # 새 캐릭터 미리보기에서 고른 Q/E
var center_title: Label
var create_screen: Control
var cs_info: RichTextLabel
var cs_preview: CharPreview
var cs_skills: VBoxContainer
var cs_classes: HBoxContainer
var cs_name: LineEdit
var cs_focus := "" # 오른쪽에서 설명을 보여 줄 스킬/패시브
const CLASS_ROLE := {
	"fighter": "근접 탱커 · 방패로 전열 유지, 양손검으로 광역 공격", "swordmaster": "근접 딜러 · 패링과 영검", "rogue": "암살자 · 은신과 기습",
	"deathknight": "근접 브루저 · 영혼 에너지와 흡혈", "druid": "변신 · 표범 형태와 나무 정령 소환", "pyromancer": "원거리 화염 마법 · 폭발 피해",
	"cryomancer": "원거리 냉기 마법 · 둔화와 제어", "priest": "치유와 보호 · 아군 지원",
}
var creating := false
var equip_view: EquipView
var stats_label: RichTextLabel
var bag_view: GridView
var right_box: VBoxContainer
var gold_label: Label
var relief_btn: Button
var tab_btns := {}
var start_btn: Button
var start_hint: Label
var mp_name := ""
var mp_addr := "127.0.0.1"
var mp_port := Net.PORT
var mp_msg := ""
var mp_pin := ""
var map_panel: Control
var wait_panel: Control
var wait_title: Label
var wait_info: Label
var wait_list: VBoxContainer
var wait_bar: ProgressBar
var wait_map := "" # 오프라인 대기방
var wait_left := 0.0
var wait_total := 10.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.07, 0.045, 0.03)
	add_child(bg)
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.23, 0.14, 0.08, 1))
	g.set_color(1, Color(0.03, 0.02, 0.02, 1))
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.1)
	grad.texture = gt
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(grad)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	# 상단
	var top := HBoxContainer.new()
	var logo := VBoxContainer.new()
	var t1 := RichTextLabel.new()
	t1.bbcode_enabled = true
	t1.fit_content = true
	t1.autowrap_mode = TextServer.AUTOWRAP_OFF
	t1.text = "[font_size=38][color=#c9c0b0]DUNGEON [/color][color=#e2702a]REBORN[/color][/font_size]"
	t1.custom_minimum_size = Vector2(420, 0)
	logo.add_child(t1)
	logo.add_child(UI.label("던전 리본 · 익스트랙션 던전 크롤러", 13, UI.MUTED))
	top.add_child(logo)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	# 던전 입장 버튼은 항상 보이도록 위쪽에
	var sv := VBoxContainer.new()
	sv.custom_minimum_size = Vector2(420, 0)
	start_btn = UI.big_button("⚔ 던전 입장", _open_maps)
	start_btn.tooltip_text = "탈출하지 못하면 장착한 장비와 가방 속 물건을 모두 잃습니다."
	sv.add_child(start_btn)
	start_hint = UI.label("", 12, Color("#8fd0ff"))
	start_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(start_hint)
	top.add_child(sv)
	var sp3 := Control.new()
	sp3.custom_minimum_size = Vector2(16, 0)
	top.add_child(sp3)
	var gold_panel := UI.panel_box()
	gold_label = UI.label("", 22, UI.GOLD)
	gold_panel.add_child(gold_label)
	top.add_child(gold_panel)
	root.add_child(top)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)

	# 왼쪽: 직업
	var left := UI.panel_box()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	left.custom_minimum_size = Vector2(320, 0)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(_scroll(lv))
	lv.add_child(UI.title("캐릭터"))
	class_box = VBoxContainer.new()
	class_box.add_theme_constant_override("separation", 8)
	lv.add_child(class_box)
	var howto := RichTextLabel.new()
	howto.bbcode_enabled = true
	howto.fit_content = true
	howto.text = "[color=#e6dccb][b]조작법[/b][/color]\n[color=#9a8e7a][font_size=13]WASD 이동 · Space 점프\n좌클릭 공격 · 우클릭 보조 · Q/E 스킬\n1·2 무기 세트 선택 · 3·4 소모품 칸 (물약·붕대·플라스크)\nF 상호작용/줍기 · Tab 인벤토리 · M 지도 · Esc 메뉴 (게임은 계속 진행)[/font_size][/color]"
	lv.add_child(howto)
	body.add_child(left)

	# 가운데: 장비/가방
	var center := UI.panel_box()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = Vector2(540, 0)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	center.add_child(_scroll(cv))
	center_title = UI.title("장비 · 능력치")
	cv.add_child(center_title)
	var eq_row := HBoxContainer.new()
	eq_row.add_theme_constant_override("separation", 12)
	equip_view = EquipView.new(32.0)
	equip_view.on_op = _inv_op
	eq_row.add_child(equip_view)
	stats_label = RichTextLabel.new()
	stats_label.bbcode_enabled = true
	stats_label.fit_content = true
	stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_label.custom_minimum_size = Vector2(260, 0)
	eq_row.add_child(stats_label)
	cv.add_child(eq_row)
	skill_box = VBoxContainer.new()
	skill_box.add_theme_constant_override("separation", 4)
	cv.add_child(skill_box)
	var bag_title := UI.title("가방")
	bag_title.text = "가방 (던전에 가져갈 물건 · 직업마다 크기가 다름)"
	cv.add_child(bag_title)
	bag_view = GridView.new("bag", 34.0)
	bag_view.on_op = _inv_op
	bag_view.allow_sell = true
	bag_view.hint = "드래그: 이동 (R 회전) · 우클릭: 장착 · Shift+클릭: 보관함으로 · Ctrl+클릭: 판매"
	cv.add_child(bag_view)
	cv.add_child(UI.label("드래그로 옮기기 · 드래그 중 R 회전 · 우클릭 장착/해제 · Shift+클릭 빠른 이동 · Ctrl+클릭 판매 · 판금/가죽/천 방어구는 모든 직업 착용 가능", 12, UI.MUTED))
	relief_btn = UI.button("🎁 구호 물자 받기 (기본 무기 + 물약)", _on_relief)
	cv.add_child(relief_btn)
	body.add_child(center)

	# 오른쪽: 탭
	var right := UI.panel_box()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.1
	right.custom_minimum_size = Vector2(430, 0)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right.add_child(rv)
	var tabs := HBoxContainer.new()
	for t in [["stash", "보관함"], ["shop", "상인"], ["online", "함께하기"], ["records", "기록"]]:
		var b := UI.button(t[1], func():
			tab = t[0]
			refresh())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		tabs.add_child(b)
		tab_btns[t[0]] = b
	rv.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_box = VBoxContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(right_box)
	rv.add_child(scroll)
	body.add_child(right)
	mp_name = SaveData.setting("mp_name", "모험가%d" % randi_range(10, 99))
	mp_addr = SaveData.setting("mp_addr", "127.0.0.1")
	Net.roster_changed.connect(func(): if visible: refresh())
	SaveData.changed.connect(func(): if visible: refresh())
	Net.status_changed.connect(func(_t): if visible: refresh())
	_build_map_panel()
	_build_wait_panel()
	refresh()


# 패널 내용이 화면보다 길면 패널 안에서 스크롤 (창 밖으로 밀려나지 않도록)
func _scroll(content: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	return sc


func save() -> Dictionary:
	return SaveData.data


func persist() -> void:
	SaveData.save()


func refresh() -> void:
	var s := save()
	gold_label.text = ("☁ %s · " % SaveData.account_name if SaveData.online else "") + "💰 %d 골드" % s.gold
	UI.clear(class_box)
	_render_chars()
	_refresh_create_screen()

	# 장비 / 능력치 / 가방 (새 캐릭터를 만드는 중이면 고른 직업의 시작 장비 미리보기)
	var view := _view_char()
	UI.tip_cls = view.cls
	center_title.text = "장비 · 능력치" if not creating else "새 캐릭터 미리보기: %s %s (시작 장비)" % [Data.CLASSES[view.cls].icon, Data.CLASSES[view.cls].name]
	equip_view.on_op = _inv_op if not creating else func(_o, _a): pass
	bag_view.on_op = equip_view.on_op
	equip_view.set_equipment(view.equipment, view.cls, int(view.get("wset", 1)))
	var st := Data.compute_stats(view.cls, view.equipment, int(view.get("wset", 1)))
	var risk := []
	for sl in Data.GEAR_SLOTS:
		if view.equipment[sl] != null:
			risk.append(view.equipment[sl])
	risk.append_array(view.bag)
	var txt := UI.stats_text(view.cls, st)
	if Data.active_weapons(view.equipment, int(view.get("wset", 1))).is_empty():
		txt += "\n[color=#e0a050][font_size=13]⚠ 사용 중인 세트에 무기 없음 - 맨손(공격력 x0.85)으로 싸웁니다[/font_size][/color]"
	txt += "\n"
	txt += "[color=#9a8e7a][font_size=12]위험 부담 장비 가치: 💰 %d[/font_size][/color]" % Data.items_value(risk)
	stats_label.text = txt
	bag_view.set_items(view.bag, Inv.bag_size(view.cls))
	_render_skills(view)

	for k in tab_btns:
		tab_btns[k].button_pressed = k == tab
	UI.clear(right_box)
	match tab:
		"stash":
			_render_stash()
		"shop":
			_render_shop()
		"online":
			_render_online()
		_:
			_render_records()

	relief_btn.visible = Account.needs_relief(s) and not creating
	_update_start()
	_wrap_long(self)


# 던전 입장 버튼: 맵 선택 -> 대기방
func _update_start() -> void:
	start_hint.text = "탈출하지 못하면 장착한 장비와 가방 속 물건을 모두 잃습니다"
	start_btn.disabled = false
	start_btn.text = "⚔ 던전 입장 (맵 선택)"
	if creating:
		start_btn.disabled = true
		start_hint.text = "새 캐릭터를 만들거나 취소한 뒤 입장할 수 있습니다"
		return
	if Net.online():
		var mine: Dictionary = Net.roster.get(Net.my_id(), {})
		if mine.get("state", "lobby") == "raid":
			start_btn.text = "⏳ 레이드 진행 중"
			start_btn.disabled = true
		else:
			start_hint.text = "같은 맵을 고른 사람끼리 대기방에서 모여 함께 입장합니다"


# ------------------------------------------------------------------ 맵 선택 / 대기방
func _overlay() -> Control:
	var o := ColorRect.new()
	(o as ColorRect).color = Color(0, 0, 0, 0.72)
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	o.visible = false
	add_child(o)
	return o


func _build_map_panel() -> void:
	map_panel = _overlay()
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_panel.add_child(c)
	var p := UI.panel_box(Vector2(760, 0))
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(UI.title("맵 선택"))
	for mid in Data.MAP_ORDER:
		var m: Dictionary = Data.MAPS[mid]
		var card := _card(false)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := UI.label(m.icon, 36)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(ic)
		var t := RichTextLabel.new()
		t.bbcode_enabled = true
		t.fit_content = true
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var names := []
		for k in m.monsters:
			names.append(Data.MONSTERS[k].name)
		t.text = "[font_size=20][color=#d9b45a][b]%s[/b][/color][/font_size]\n[font_size=13][color=#c9c0b0]%s[/color]\n[color=#9a8e7a]출현: %s · 보스: %s[/color][/font_size]" % [m.name, m.desc, ", ".join(names), Data.MONSTERS[m.boss].name]
		hb.add_child(t)
		card.add_child(hb)
		var id2: String = mid
		_on_click(card, func(): _enter_map(id2))
		v.add_child(card)
	var locked := _card(false)
	locked.modulate = Color(1, 1, 1, 0.45)
	locked.mouse_default_cursor_shape = Control.CURSOR_ARROW
	locked.add_child(UI.label("🪦  죄인의 끝 2층 — 준비 중 (지도 자료가 들어오면 추가됩니다)", 15, UI.MUTED))
	v.add_child(locked)
	v.add_child(UI.label("맵을 고르면 대기방으로 들어갑니다. 같은 맵을 고른 모험가끼리 최소 10초 ~ 최대 60초 동안 모인 뒤, 각자 정해진 시작 지점에서 출발합니다.", 12, UI.MUTED))
	var close := UI.button("닫기", func(): map_panel.visible = false, 13)
	v.add_child(close)


func _build_wait_panel() -> void:
	wait_panel = _overlay()
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wait_panel.add_child(c)
	var p := UI.panel_box(Vector2(520, 0))
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	wait_title = UI.title("대기방")
	v.add_child(wait_title)
	wait_info = UI.label("", 15)
	v.add_child(wait_info)
	wait_bar = ProgressBar.new()
	wait_bar.custom_minimum_size = Vector2(480, 14)
	wait_bar.show_percentage = false
	wait_bar.max_value = 1.0
	wait_bar.step = 0.0
	v.add_child(wait_bar)
	wait_list = VBoxContainer.new()
	v.add_child(wait_list)
	v.add_child(UI.label("최소 10초 · 최대 60초 동안 같은 맵을 고른 모험가를 기다린 뒤 함께 입장합니다. 입장하면 장착한 장비와 가방은 위험에 노출됩니다.", 12, UI.MUTED))
	v.add_child(UI.button("대기방 나가기", _leave_wait, 13))


func _open_maps() -> void:
	map_panel.visible = true


func _enter_map(mid: String) -> void:
	map_panel.visible = false
	Sfx.play("ui")
	if Net.online():
		Net.join_room(mid)
	else:
		wait_map = mid
		wait_total = Net.ROOM_MIN
		wait_left = wait_total
	wait_panel.visible = true
	_update_wait(0.0)


func _leave_wait() -> void:
	if Net.online():
		Net.leave_room()
	wait_map = ""
	wait_panel.visible = false


func _process(dt: float) -> void:
	if wait_panel == null or not visible:
		return
	if Net.online():
		wait_panel.visible = Net.my_room() != ""
	if wait_panel.visible:
		_update_wait(dt)


func _update_wait(dt: float) -> void:
	var mid := wait_map
	var members := []
	var left := 0.0
	var total := Net.ROOM_MAX
	if Net.online():
		mid = Net.my_room()
		if mid == "":
			return
		left = Net.room_left(mid)
		total = Net.ROOM_MIN if Net._nobody_else(mid) else Net.ROOM_MAX
		for id in Net.rooms[mid].members:
			members.append(Net.roster.get(id, {"name": "?", "cls": "fighter"}))
		if Net.is_client():
			# 서버 갱신 사이에는 직접 시간을 흘림
			Net.rooms[mid].t += dt
	else:
		if mid == "":
			wait_panel.visible = false
			return
		wait_left -= dt
		left = wait_left
		total = wait_total
		var cur := Account.cur(save())
		members.append({"name": cur.get("name", "나"), "cls": save().cls})
		if wait_left <= 0.0:
			wait_map = ""
			wait_panel.visible = false
			start_raid.emit(mid)
			return
	var m: Dictionary = Data.MAPS[mid]
	wait_title.text = "%s %s 대기방" % [m.icon, m.name]
	var stage := "던전을 불러오는 중" if left > total * 0.5 else ("모험가를 기다리는 중" if Net.online() else "입장 준비 중")
	wait_info.text = "%s... %d초 (%d명)" % [stage, ceili(left), members.size()]
	wait_bar.value = 1.0 - left / maxf(1.0, total)
	if wait_list.get_child_count() != members.size():
		UI.clear(wait_list)
		for r in members:
			var c: Dictionary = Data.CLASSES.get(r.get("cls", "fighter"), Data.CLASSES.fighter)
			wait_list.add_child(UI.label("%s %s — %s" % [c.icon, r.get("name", "?"), c.name], 15))


func _render_online() -> void:
	var v := right_box
	v.add_child(UI.title("친구와 함께하기"))
	if not Net.online():
		var info := RichTextLabel.new()
		info.bbcode_enabled = true
		info.fit_content = true
		info.text = "[font_size=13][color=#9a8e7a]한 명이 [b]호스트[/b]가 되고, 나머지는 호스트의 주소로 [b]접속[/b]합니다.\n같은 와이파이/공유기면 호스트 PC의 내부 IP(예: 192.168.0.x), 인터넷이면 공인 IP + 포트포워딩(UDP %d) 또는 Tailscale 같은 가상 LAN 주소를 쓰세요.[/color][/font_size]" % Net.PORT
		v.add_child(info)
		var nh := HBoxContainer.new()
		nh.add_child(UI.label("이름", 14, UI.MUTED))
		var name_edit := LineEdit.new()
		name_edit.text = mp_name
		name_edit.max_length = 16
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_edit.text_changed.connect(func(t): mp_name = t)
		nh.add_child(name_edit)
		nh.add_child(UI.label("포트", 14, UI.MUTED))
		var port_edit := LineEdit.new()
		port_edit.text = str(mp_port)
		port_edit.custom_minimum_size = Vector2(80, 0)
		port_edit.text_changed.connect(func(t): mp_port = int(t) if t.is_valid_int() else Net.PORT)
		nh.add_child(port_edit)
		v.add_child(nh)
		v.add_child(UI.button("🏠 호스트 열기 (내 PC가 서버)", _mp_host))
		var jh := HBoxContainer.new()
		var addr_edit := LineEdit.new()
		addr_edit.text = mp_addr
		addr_edit.placeholder_text = "호스트 주소 (예: 192.168.0.10)"
		addr_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		addr_edit.text_changed.connect(func(t): mp_addr = t.strip_edges())
		jh.add_child(addr_edit)
		jh.add_child(UI.button("🔗 접속", _mp_join))
		v.add_child(jh)
		var ph := HBoxContainer.new()
		ph.add_child(UI.label("PIN", 14, UI.MUTED))
		var pin_edit := LineEdit.new()
		pin_edit.secret = true
		pin_edit.text = mp_pin
		pin_edit.max_length = 32
		pin_edit.placeholder_text = "온라인 서버 계정용 (친구 호스트면 비워 두기)"
		pin_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pin_edit.text_changed.connect(func(t): mp_pin = t)
		ph.add_child(pin_edit)
		v.add_child(ph)
		v.add_child(UI.label("☁ 온라인 서버(클라우드)에 접속하면 이름+PIN이 계정이 되고, 보관함·골드·장비가 서버에 저장됩니다. 처음 접속하면 새 계정이 만들어집니다. 다른 곳에서 쓰는 비밀번호는 쓰지 마세요.", 12, UI.MUTED))
	else:
		var role := "호스트" if Net.mode == "host" else ("전용 서버 운영" if Net.mode == "server" else "접속함")
		v.add_child(UI.label("%s · %s" % [role, Net.status], 13, Color("#8fd0ff")))
		if SaveData.online:
			v.add_child(UI.label("☁ 온라인 계정 '%s' — 보관함/장비/골드는 서버에 저장됩니다 (이 PC의 저장 파일은 그대로)" % SaveData.account_name, 13, Color("#9fe0a0")))
		v.add_child(UI.title("대기실 (%d명)" % Net.roster.size()))
		var ids := Net.roster.keys()
		ids.sort()
		for id in ids:
			var r: Dictionary = Net.roster[id]
			var c: Dictionary = Data.CLASSES.get(r.cls, Data.CLASSES["fighter"])
			var room := ""
			for mm in Net.rooms:
				if id in Net.rooms[mm].members:
					room = " · %s 대기방" % Data.MAPS[mm].name
			var tag := room
			var me := " (나)" if id == Net.my_id() else ""
			var st := "  ⚔ 레이드 중" if r.state == "raid" else ""
			v.add_child(UI.label("%s %s%s%s — %s%s" % [c.icon, r.name, me, tag, c.name, st], 15, UI.GOLD if id == Net.my_id() else UI.TEXT))
		var pv := CheckBox.new()
		pv.text = "개인전 (함께 들어간 친구도 적) — 끄면 파티(아군)"
		pv.button_pressed = Net.pvp
		pv.disabled = not Net.is_server()
		pv.focus_mode = Control.FOCUS_NONE
		pv.toggled.connect(func(on): Net.set_pvp(on))
		v.add_child(pv)
		v.add_child(UI.label("탈출하지 못하면 소지품을 잃는 규칙은 같습니다. 쓰러진 친구의 소지품은 시체 가방으로 떨어집니다.", 12, UI.MUTED))
		v.add_child(UI.button("나가기 (연결 종료)", func():
			Net.leave()
			refresh(), 13))
	if mp_msg != "":
		v.add_child(UI.label(mp_msg, 13, Color("#ff8a6a")))


func _mp_save_settings() -> void:
	SaveData.set_setting("mp_name", mp_name)
	SaveData.set_setting("mp_addr", mp_addr)


func _mp_host() -> void:
	_mp_save_settings()
	mp_msg = Net.host(mp_port, mp_name)
	refresh()


func _mp_join() -> void:
	_mp_save_settings()
	if mp_addr == "":
		mp_msg = "호스트 주소를 입력하세요"
	else:
		mp_msg = Net.join(mp_addr, mp_port, mp_name, mp_pin)
	refresh()


func _render_stash() -> void:
	var s := save()
	var gv := GridView.new("stash", 32.0)
	gv.on_op = _inv_op
	gv.allow_sell = true
	gv.hint = "드래그: 이동 (R 회전) · 우클릭: 장착 · Shift+클릭: 가방으로 · Ctrl+클릭: 판매"
	right_box.add_child(gv)
	gv.set_items(s.stash, Inv.STASH)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(UI.button("정렬", _sort_stash, 13))
	row.add_child(UI.button("보물 모두 판매", _sell_treasure, 13))
	right_box.add_child(row)


# 인벤토리 조작 (드래그/우클릭/Shift/Ctrl) -> 계정 규칙
func _inv_op(op: String, args: Array) -> void:
	UI.hide_tip()
	SaveData.op(op, args)


func _render_shop() -> void:
	var s := save()
	for entry in SHOP:
		var base: String = entry[0]
		var price: int = entry[1]
		if not Data.ITEM_BASES.has(base):
			continue
		var b: Dictionary = Data.ITEM_BASES[base]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(UI.slot(Data.make_item(base, 0)))
		var kind: String
		match str(b.slot):
			"weapon":
				kind = "%s · %s" % [Data.WEAPON_NAMES.get(b.cat, b.cat), Data.class_names(Data.weapon_classes(b.cat))]
			"consumable":
				kind = "소모품"
			"head", "chest", "hands", "legs", "feet":
				kind = "%s %s" % [Data.ARMOR_TYPES.get(b.get("cat", ""), ""), Data.SLOT_NAMES[b.slot]]
			_:
				kind = Data.SLOT_NAMES.get(b.slot, "")
		var nm := RichTextLabel.new()
		nm.bbcode_enabled = true
		nm.fit_content = true
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.custom_minimum_size = Vector2(200, 0)
		nm.text = "%s\n[font_size=12][color=#9a8e7a]%s[/color][/font_size]" % [b.name, kind]
		row.add_child(nm)
		var bb := UI.button("%dg 구매" % price, func(): _buy(base, price), 13)
		bb.disabled = s.gold < price
		row.add_child(bb)
		right_box.add_child(row)
	# 판매대: 가방/보관함에서 끌어다 놓으면 판매
	var zone := DropZone.new()
	zone.on_op = _inv_op
	zone.custom_minimum_size = Vector2(0, 70)
	var zl := UI.label("💰 판매대 — 가방이나 보관함의 물건을 여기로 끌어다 놓으면 판매", 14, UI.GOLD)
	zl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	zone.add_child(zl)
	right_box.add_child(zone)
	right_box.add_child(UI.label("보관함은 '보관함' 탭에서 볼 수 있습니다. Ctrl+클릭으로도 판매할 수 있습니다.", 12, UI.MUTED))


func _render_records() -> void:
	var st: Dictionary = save().stats
	var rate := roundi(float(st.extracts) / st.raids * 100.0) if st.raids > 0 else 0
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.text = "입장 횟수 [b]%d[/b]\n탈출 성공 [b]%d[/b]\n사망 [b]%d[/b]\n탈출률 [b]%d%%[/b]\n몬스터 처치 [b]%d[/b]\n모험가 처치 [b]%d[/b]\n최고 수익 [b]💰 %d[/b]" % [st.raids, st.extracts, st.deaths, rate, st.kills, st.pvp_kills, st.best_haul]
	right_box.add_child(r)
	right_box.add_child(UI.button("저장 데이터 초기화", _confirm_reset, 13))


func _confirm_reset() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "모든 진행 상황을 삭제할까요?"
	dlg.ok_button_text = "삭제"
	dlg.cancel_button_text = "취소"
	dlg.confirmed.connect(func(): SaveData.reset())
	add_child(dlg)
	dlg.popup_centered()


# 로비 조작은 SaveData.op -> Account 규칙 (온라인 서버면 서버가 처리)
func _select_char(id: String) -> void:
	if save().get("active", "") == id:
		return
	SaveData.op("select_char", [id])
	Net.update_class(save().cls)


func _card(sel: bool) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#2a2014") if sel else Color("#1a1510")
	sb.border_color = UI.GOLD if sel else UI.LINE
	sb.set_border_width_all(2 if sel else 1)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", sb)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return card


func _on_click(c: Control, f: Callable) -> void:
	c.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			f.call())


# 캐릭터 목록 (던전본처럼 직업별 캐릭터를 만들어 선택)
func _render_chars() -> void:
	var s := save()
	for c in s.characters:
		var sel: bool = c.id == s.get("active", "")
		var cd: Dictionary = Data.CLASSES[c.cls]
		var card := _card(sel)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := UI.label(cd.icon, 22)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(ic)
		var nv := VBoxContainer.new()
		nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nm := UI.label(c.name, 16, UI.GOLD if sel else UI.TEXT)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cst: Dictionary = c.get("stats", {})
		var sub := UI.label("%s · 입장 %d · 탈출 %d" % [cd.name, int(cst.get("raids", 0)), int(cst.get("extracts", 0))], 12, UI.MUTED)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nv.add_child(nm)
		nv.add_child(sub)
		hb.add_child(nv)
		if s.characters.size() > 1:
			var cid: String = c.id
			var cname: String = c.name
			var del := UI.button("✕", func(): _confirm_delete(cid, cname), 12)
			del.tooltip_text = "캐릭터 삭제"
			hb.add_child(del)
		card.add_child(hb)
		var id2: String = c.id
		_on_click(card, func(): _select_char(id2))
		class_box.add_child(card)
	if s.characters.size() < Account.MAX_CHARS:
		class_box.add_child(UI.button("＋ 새 캐릭터 만들기", func():
			creating = true
			create_name = ""
			create_skills = {}
			refresh(), 14))
	var cur: Dictionary = Data.CLASSES[s.cls]
	class_box.add_child(_class_detail(cur))


func _class_detail(cur: Dictionary) -> RichTextLabel:
	var detail := RichTextLabel.new()
	detail.bbcode_enabled = true
	detail.fit_content = true
	detail.custom_minimum_size = Vector2(300, 0)
	var t := "[font_size=18][color=#d9b45a][b]%s %s[/b][/color][/font_size]\n[font_size=13][color=#9a8e7a]%s[/color][/font_size]\n" % [cur.icon, cur.name, cur.desc]
	t += "[font_size=12][color=#9a8e7a]무기: %s[/color][/font_size]\n" % ", ".join(cur.weapons.map(func(w): return Data.WEAPON_NAMES.get(w, w)))
	if cur.res != "":
		t += "[font_size=12][color=#8fd0ff]자원: %s[/color][/font_size]\n" % Data.RES_NAMES[cur.res]
	var keys := {"lmb": "좌클릭", "rmb": "우클릭", "lmb_p": "표범 좌클릭", "rmb_p": "표범 우클릭"}
	for k in keys:
		if cur.skills.has(k):
			var sk: Dictionary = cur.skills[k]
			t += "[font_size=13][color=#d9b45a]%s[/color] [b]%s[/b]\n[color=#9a8e7a]   %s[/color][/font_size]\n" % [keys[k], sk.name, sk.desc]
	detail.text = t
	return detail


# 새 캐릭터: 직업 + 이름
# ------------------------------------------------------------------ 직업 선택 화면 (던전본 캐릭터 생성)
#  왼쪽: 직업 설명 · 역할 · 사용 가능 무기 / 가운데: 캐릭터 모습 / 오른쪽: 스킬 · 패시브 · 능력치 / 아래: 8직업 + 이름 + 선택
func _build_create_screen() -> void:
	create_screen = ColorRect.new()
	(create_screen as ColorRect).color = Color(0.03, 0.025, 0.02, 0.97)
	create_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	create_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(create_screen)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 28)
	create_screen.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)
	var t := UI.label("직업을 선택하세요", 18, UI.MUTED)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	var lp := UI.panel_box(Vector2(380, 0))
	cs_info = RichTextLabel.new()
	cs_info.bbcode_enabled = true
	cs_info.fit_content = true
	cs_info.custom_minimum_size = Vector2(350, 0)
	lp.add_child(cs_info)
	row.add_child(lp)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cs_preview = CharPreview.new(Vector2(520, 600))
	center.add_child(cs_preview)
	row.add_child(center)
	var rp := UI.panel_box(Vector2(400, 0))
	var rs := ScrollContainer.new()
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cs_skills = VBoxContainer.new()
	cs_skills.add_theme_constant_override("separation", 8)
	cs_skills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rs.add_child(cs_skills)
	rp.add_child(rs)
	row.add_child(rp)
	cs_classes = HBoxContainer.new()
	cs_classes.alignment = BoxContainer.ALIGNMENT_CENTER
	cs_classes.add_theme_constant_override("separation", 8)
	v.add_child(cs_classes)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 10)
	bottom.add_child(UI.label("이름", 15, UI.MUTED))
	cs_name = LineEdit.new()
	cs_name.max_length = 12
	cs_name.placeholder_text = "2~12자"
	cs_name.custom_minimum_size = Vector2(240, 0)
	cs_name.text_changed.connect(func(tx): create_name = tx)
	cs_name.text_submitted.connect(func(_tx): _create())
	bottom.add_child(cs_name)
	var ok := UI.big_button("선택", _create)
	ok.custom_minimum_size = Vector2(240, 0)
	bottom.add_child(ok)
	bottom.add_child(UI.button("취소", func():
		creating = false
		refresh(), 14))
	v.add_child(bottom)


func _refresh_create_screen() -> void:
	if not creating:
		if create_screen != null:
			create_screen.visible = false
		return
	if create_screen == null:
		_build_create_screen()
	create_screen.visible = true
	var c: Dictionary = Data.CLASSES[create_cls]
	var pc := Account.new_character("미리보기", create_cls)
	cs_preview.set_char(create_cls, Data.weapon_model(create_cls, pc.equipment, 1), true)
	if cs_name.text != create_name:
		cs_name.text = create_name
	var t := "[center][font_size=40]%s[/font_size]\n[font_size=26][color=#d9b45a][b]%s[/b][/color][/font_size][/center]\n" % [c.icon, c.name]
	t += "[font_size=14][color=#c9c0b0]%s[/color][/font_size]\n\n" % c.desc
	t += "[font_size=15][color=#d9b45a]역할[/color][/font_size]\n[font_size=14]%s[/font_size]\n\n" % CLASS_ROLE.get(create_cls, "")
	t += "[font_size=15][color=#d9b45a]특징[/color][/font_size]\n[font_size=14]"
	for k in ["lmb", "rmb"]:
		var sk: Dictionary = c.skills[k]
		t += "· %s %s: %s\n" % ["좌클릭" if k == "lmb" else "우클릭", sk.name, sk.desc]
	if c.res != "":
		t += "· 자원: %s\n" % Data.RES_NAMES[c.res]
	t += "· 가방: %d칸 (%s 종족)\n" % [Inv.bag_size(create_cls).x * Inv.bag_size(create_cls).y, "언데드" if Inv.bag_size(create_cls) == Inv.UNDEAD_BAG else "인간"]
	t += "[/font_size]\n[font_size=15][color=#d9b45a]사용 가능한 무기[/color][/font_size]\n[font_size=14]%s[/font_size]" % " · ".join(c.weapons.map(func(w): return Data.WEAPON_NAMES.get(w, w)))
	cs_info.text = t
	# 오른쪽: 스킬 (Q/E 고르기) · 패시브 · 능력치
	UI.clear(cs_skills)
	for slot in ["q", "e"]:
		cs_skills.add_child(UI.label("스킬 %s" % slot.to_upper(), 15, UI.GOLD))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		for sid in c[slot]:
			var sk: Dictionary = Data.SKILLS[sid]
			var sel: bool = create_skills.get(slot, c[slot][0]) == sid
			var card := _card(sel)
			card.custom_minimum_size = Vector2(0, 40)
			var l := UI.label("%s %s" % [sk.get("icon", ""), sk.name], 13, UI.GOLD if sel else UI.TEXT)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(l)
			var sl: String = slot
			var id2: String = sid
			_on_click(card, func():
				create_skills[sl] = id2
				cs_focus = "s:" + id2
				refresh())
			card.mouse_entered.connect(func(): UI.show_tip(UI.skill_tip(id2)))
			card.mouse_exited.connect(func(): UI.hide_tip())
			hb.add_child(card)
		cs_skills.add_child(hb)
	var focus := cs_focus
	if focus == "" or not (focus.substr(2) in c.q or focus.substr(2) in c.e or focus.begins_with("p:")):
		focus = "s:" + create_skills.get("q", c.q[0])
	if focus.begins_with("s:"):
		var fs: Dictionary = Data.SKILLS[focus.substr(2)]
		var d := RichTextLabel.new()
		d.bbcode_enabled = true
		d.fit_content = true
		d.text = "[font_size=15][color=#d9b45a]%s %s[/color][/font_size]  [font_size=12][color=#9a8e7a]재사용 %.0f초[/color][/font_size]\n[font_size=13]%s[/font_size]" % [fs.get("icon", ""), fs.name, fs.cd, fs.desc]
		cs_skills.add_child(d)
	cs_skills.add_child(UI.label("패시브 (능력치 조건을 채우면 자동 활성)", 15, UI.GOLD))
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 6)
	var ps: Array = Data.PASSIVES[create_cls]
	for i in ps.size():
		var pa: Dictionary = ps[i]
		var b := UI.button(pa.name, func():
			cs_focus = "p:%d" % i
			refresh(), 11)
		b.toggle_mode = true
		b.button_pressed = focus == "p:%d" % i
		ph.add_child(b)
	var pw := HFlowContainer.new()
	for ch in ph.get_children():
		ph.remove_child(ch)
		pw.add_child(ch)
	cs_skills.add_child(pw)
	if focus.begins_with("p:"):
		var pa: Dictionary = ps[int(focus.substr(2))]
		var req := []
		for k in pa.req:
			req.append("%s %d" % [Data.ATTR_NAMES[k], pa.req[k]])
		var d := RichTextLabel.new()
		d.bbcode_enabled = true
		d.fit_content = true
		d.text = "[font_size=15][color=#d9b45a]%s[/color][/font_size]  [font_size=12][color=#9a8e7a]조건: %s[/color][/font_size]\n[font_size=13]%s[/font_size]" % [pa.name, ", ".join(req), pa.desc]
		cs_skills.add_child(d)
	cs_skills.add_child(UI.label("기본 능력치", 15, UI.GOLD))
	var ah := HBoxContainer.new()
	ah.add_theme_constant_override("separation", 6)
	var base: Dictionary = Data.CLASS_ATTRS[create_cls]
	for k in Data.ATTRS:
		var bx := VBoxContainer.new()
		bx.custom_minimum_size = Vector2(52, 0)
		var ic := UI.label(Data.ATTR_ICONS[k], 18)
		ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bx.add_child(ic)
		var val := UI.label(str(base[k]), 15, UI.GOLD if Data.POWER_ATTR[create_cls] == k else UI.TEXT)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bx.add_child(val)
		var nm := UI.label(Data.ATTR_NAMES[k], 11, UI.MUTED)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bx.add_child(nm)
		ah.add_child(bx)
	cs_skills.add_child(ah)
	# 아래: 8직업
	UI.clear(cs_classes)
	for cid in Data.CLASS_ORDER:
		var cc: Dictionary = Data.CLASSES[cid]
		var card := _card(cid == create_cls)
		card.custom_minimum_size = Vector2(110, 86)
		var cv := VBoxContainer.new()
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := UI.label(cc.icon, 30)
		ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(ic)
		var nl := UI.label(cc.name, 13, UI.GOLD if cid == create_cls else UI.TEXT)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(nl)
		card.add_child(cv)
		var id3: String = cid
		_on_click(card, func():
			if create_cls != id3:
				create_skills = {}
				cs_focus = ""
			create_cls = id3
			refresh())
		cs_classes.add_child(card)


func _create() -> void:
	var nm := create_name.strip_edges()
	if not Account.valid_name(nm):
		UI.toast("이름은 2~12자로 정해 주세요")
		return
	creating = false
	SaveData.op("create_char", [nm, create_cls])
	if save().cls == create_cls:
		for k in create_skills:
			SaveData.op("set_skill", [k, create_skills[k]])
	create_skills = {}
	Net.update_class(save().cls)
	refresh()


func _confirm_delete(id: String, nm: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "캐릭터 '%s'를 삭제할까요?\n장착한 장비와 가방 속 물건도 함께 사라집니다." % nm
	dlg.ok_button_text = "삭제"
	dlg.cancel_button_text = "취소"
	dlg.confirmed.connect(func():
		SaveData.op("delete_char", [id])
		Net.update_class(save().cls))
	add_child(dlg)
	dlg.popup_centered()


# 인벤토리의 Q/E 스킬 선택 (던전에 들어가기 전에 고름)
# 지금 가운데에 보여 줄 캐릭터: 선택한 캐릭터, 또는 만들고 있는 새 캐릭터의 시작 장비
func _view_char() -> Dictionary:
	var s := save()
	if not creating:
		return {"cls": s.cls, "equipment": s.equipment, "bag": s.bag, "skills": s.skills, "wset": s.get("wset", 1)}
	var pc := Account.new_character("미리보기", create_cls)
	for k in create_skills:
		if create_skills[k] in Data.CLASSES[create_cls][k]:
			pc.skills[k] = create_skills[k]
	return pc


# 너비 제한 없는 긴 글은 줄바꿈 (창이 화면 밖으로 넓어지지 않도록)
func _wrap_long(n: Node) -> void:
	for c in n.get_children():
		if c is Label and not (c.get_parent() is Button) and c.text.length() > 24 and c.autowrap_mode == TextServer.AUTOWRAP_OFF:
			c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			c.custom_minimum_size.x = maxf(c.custom_minimum_size.x, 120.0)
		_wrap_long(c)


func _render_skills(view: Dictionary) -> void:
	var s := view
	UI.clear(skill_box)
	var cur: Dictionary = Data.CLASSES[s.cls]
	var top := HBoxContainer.new()
	top.add_child(UI.label("스킬 선택", 15, UI.GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	skill_box.add_child(top)
	for slot in ["q", "e"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var kl := UI.label(slot.to_upper(), 16, UI.GOLD)
		kl.custom_minimum_size = Vector2(22, 0)
		row.add_child(kl)
		for sid in cur[slot]:
			var sk: Dictionary = Data.SKILLS[sid]
			var sel: bool = s.skills.get(slot, "") == sid
			var card := _card(sel)
			card.custom_minimum_size = Vector2(0, 34)
			var l := UI.label("%s %s" % [sk.get("icon", ""), sk.name], 13, UI.GOLD if sel else UI.TEXT)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(l)
			var sl: String = slot
			var id2: String = sid
			_on_click(card, func():
				if creating:
					create_skills[sl] = id2
					refresh()
				elif save().skills.get(sl, "") != id2:
					SaveData.op("set_skill", [sl, id2]))
			card.mouse_entered.connect(func(): UI.show_tip(UI.skill_tip(id2)))
			card.mouse_exited.connect(func(): UI.hide_tip())
			row.add_child(card)
		skill_box.add_child(row)


func _sell_treasure() -> void:
	SaveData.op("sell_treasure")


func _sort_stash() -> void:
	SaveData.op("sort_stash")


func _buy(base: String, _price: int) -> void:
	SaveData.op("buy", [base])


func _on_relief() -> void:
	SaveData.op("relief")
