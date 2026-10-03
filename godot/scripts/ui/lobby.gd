# 로비: 직업 선택, 장비, 가방, 보관함, 상인, 기록
class_name Lobby
extends Control

signal start_raid

const SHOP := Account.SHOP

var tab := "stash"
var class_box: VBoxContainer
var equip_row: HBoxContainer
var stats_label: RichTextLabel
var bag_grid: GridContainer
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
	t1.custom_minimum_size = Vector2(520, 0)
	logo.add_child(t1)
	logo.add_child(UI.label("던전 리본 · 익스트랙션 던전 크롤러", 13, UI.MUTED))
	top.add_child(logo)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
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
	left.custom_minimum_size = Vector2(400, 0)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	lv.add_child(UI.title("직업 선택"))
	class_box = VBoxContainer.new()
	class_box.add_theme_constant_override("separation", 8)
	lv.add_child(class_box)
	var howto := RichTextLabel.new()
	howto.bbcode_enabled = true
	howto.fit_content = true
	howto.text = "[color=#e6dccb][b]조작법[/b][/color]\n[color=#9a8e7a][font_size=13]WASD 이동 · Shift 달리기 · Space 점프\n좌클릭 공격 · 우클릭 보조 · Q/E 스킬\nF 상호작용 · Tab 인벤토리 · M 지도\n1 체력 물약 · 2 붕대 · Esc 메뉴 (게임은 계속 진행)[/font_size][/color]"
	lv.add_child(howto)
	body.add_child(left)

	# 가운데: 장비/가방
	var center := UI.panel_box()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = Vector2(500, 0)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	center.add_child(cv)
	cv.add_child(UI.title("장비"))
	equip_row = HBoxContainer.new()
	equip_row.add_theme_constant_override("separation", 12)
	var eq_margin := MarginContainer.new()
	eq_margin.add_theme_constant_override("margin_top", 16)
	eq_margin.add_child(equip_row)
	cv.add_child(eq_margin)
	stats_label = RichTextLabel.new()
	stats_label.bbcode_enabled = true
	stats_label.fit_content = true
	cv.add_child(stats_label)
	var bag_title := UI.title("가방")
	bag_title.text = "가방 (던전에 가져갈 물건)"
	cv.add_child(bag_title)
	bag_grid = GridContainer.new()
	bag_grid.columns = 8
	bag_grid.add_theme_constant_override("h_separation", 5)
	bag_grid.add_theme_constant_override("v_separation", 5)
	cv.add_child(bag_grid)
	relief_btn = UI.button("🎁 구호 물자 받기 (기본 무기 + 물약)", _on_relief)
	cv.add_child(relief_btn)
	var sp2 := Control.new()
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(sp2)
	start_btn = UI.big_button("⚔ 던전 입장", func(): start_raid.emit())
	cv.add_child(start_btn)
	start_hint = UI.label("", 13, Color("#8fd0ff"))
	start_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(start_hint)
	var warn := UI.label("탈출하지 못하면 장착한 장비와 가방 속 물건을 모두 잃습니다.", 13, Color("#c98a6a"))
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(warn)
	body.add_child(center)

	# 오른쪽: 탭
	var right := UI.panel_box()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.1
	right.custom_minimum_size = Vector2(500, 0)
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
	refresh()


func save() -> Dictionary:
	return SaveData.data


func persist() -> void:
	SaveData.save()


func refresh() -> void:
	var s := save()
	gold_label.text = ("☁ %s · " % SaveData.account_name if SaveData.online else "") + "💰 %d 골드" % s.gold
	# 직업 카드: 2열 작은 카드 + 선택한 직업 상세 설명
	UI.clear(class_box)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	class_box.add_child(grid)
	for cid in Data.CLASS_ORDER:
		var c: Dictionary = Data.CLASSES[cid]
		var card := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		var sel: bool = s.cls == cid
		sb.bg_color = Color("#2a2014") if sel else Color("#1a1510")
		sb.border_color = UI.GOLD if sel else UI.LINE
		sb.set_border_width_all(2 if sel else 1)
		sb.set_corner_radius_all(5)
		sb.set_content_margin_all(8)
		card.add_theme_stylebox_override("panel", sb)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := UI.label(c.icon, 22)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nm := UI.label(c.name, 16, UI.GOLD if sel else UI.TEXT)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(ic)
		hb.add_child(nm)
		card.add_child(hb)
		var id2: String = cid
		card.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_select_class(id2))
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		grid.add_child(card)
	var cur: Dictionary = Data.CLASSES[s.cls]
	var detail := RichTextLabel.new()
	detail.bbcode_enabled = true
	detail.fit_content = true
	detail.custom_minimum_size = Vector2(300, 0)
	var keys := {"lmb": "좌클릭", "rmb": "우클릭", "q": "Q", "e": "E", "lmb_p": "표범 좌클릭", "rmb_p": "표범 우클릭", "e_p": "표범 E"}
	var t := "[font_size=18][color=#d9b45a][b]%s %s[/b][/color][/font_size]\n[font_size=13][color=#9a8e7a]%s[/color][/font_size]\n" % [cur.icon, cur.name, cur.desc]
	if cur.res != "":
		t += "[font_size=12][color=#8fd0ff]자원: %s[/color][/font_size]\n" % Data.RES_NAMES[cur.res]
	for k in ["lmb", "rmb", "q", "e", "lmb_p", "rmb_p", "e_p"]:
		if cur.skills.has(k):
			var sk: Dictionary = cur.skills[k]
			var cdt := (" · %d초" % sk.cd) if sk.cd >= 2.0 else ""
			t += "[font_size=13][color=#d9b45a]%s[/color] [b]%s[/b]%s\n[color=#9a8e7a]   %s[/color][/font_size]\n" % [keys[k], sk.name, cdt, sk.desc]
	detail.text = t
	class_box.add_child(detail)

	# 장비
	UI.clear(equip_row)
	for slot in Data.GEAR_SLOTS:
		var it = s.equipment[slot]
		var sl: String = slot
		equip_row.add_child(UI.slot(it, func(): _unequip(sl), Callable(), {"label": Data.SLOT_NAMES[slot], "size": 64.0, "tip": "클릭: 장착 해제"}))
	var st := Data.compute_stats(s.cls, s.equipment)
	var risk := []
	for sl in Data.GEAR_SLOTS:
		if s.equipment[sl] != null:
			risk.append(s.equipment[sl])
	risk.append_array(s.bag)
	var txt := "[font_size=14]❤ 체력 [b]%d[/b]\n🛡 방어도 [b]%d[/b] [color=#9a8e7a](피해 -%d%%)[/color]\n⚔ 공격력 [b]x%.2f[/b]\n👟 이동속도 [b]%d%%[/b]" % [st.max_hp, st.armor, roundi((1.0 - 100.0 / (100.0 + st.armor)) * 100.0), st.dmg_mul, roundi(st.speed_mul * 100.0)]
	if st.res != "":
		txt += "\n🔷 %s [b]%d[/b]" % [Data.RES_NAMES[st.res], st.res_max]
	if s.equipment.weapon == null:
		txt += "\n[color=#e0a050]⚠ 무기 없음 - 기본 무기(공격력 x0.85)로 싸웁니다[/color]"
	txt += "\n[color=#9a8e7a][font_size=12]위험 부담 장비 가치: 💰 %d[/font_size][/color][/font_size]" % Data.items_value(risk)
	stats_label.text = txt

	# 가방
	UI.clear(bag_grid)
	for i in SaveData.BAG_SIZE:
		var it = s.bag[i] if i < s.bag.size() else null
		var idx := i
		bag_grid.add_child(UI.slot(it, func(): _bag_to_stash(idx), Callable(), {"tip": "클릭: 보관함으로"}))

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

	var has_weapon_option := s.equipment.weapon != null
	for it in s.stash:
		if Data.base_of(it).slot == "weapon" and Data.can_equip(it, s.cls):
			has_weapon_option = true
	relief_btn.visible = not has_weapon_option and s.gold < 40
	_update_start()


# 던전 입장 버튼: 함께하기 중에는 리더만 시작
func _update_start() -> void:
	start_hint.text = ""
	start_btn.disabled = false
	if not Net.online():
		start_btn.text = "⚔ 던전 입장"
		return
	if Net.raid_running():
		start_btn.text = "⏳ 레이드 진행 중"
		start_btn.disabled = true
		start_hint.text = "진행 중인 레이드가 끝나면 다시 시작할 수 있습니다"
	elif Net.is_leader():
		start_btn.text = "⚔ 함께 입장 (%d명)" % Net.roster.size()
		start_hint.text = "누르면 대기실의 모두가 함께 입장합니다"
	else:
		start_btn.text = "⏳ 리더의 시작을 기다리는 중"
		start_btn.disabled = true
		start_hint.text = "리더가 시작하면 자동으로 입장합니다 (현재 장비/가방을 가지고)"


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
			var tag := " 👑" if id == Net.leader() else ""
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
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	for i in SaveData.STASH_SIZE:
		var it = s.stash[i] if i < s.stash.size() else null
		var hint := ""
		var dim := false
		if it != null:
			var b := Data.base_of(it)
			if Data.can_equip(it, s.cls):
				hint = "클릭: 장착 · 우클릭: 판매"
			elif b.slot == "weapon":
				hint = "다른 직업 무기 · 우클릭: 판매"
				dim = true
			else:
				hint = "클릭: 가방에 넣기 · 우클릭: 판매"
		var idx := i
		grid.add_child(UI.slot(it, func(): _stash_click(idx), func(): _sell(idx), {"tip": hint, "dim": dim}))
	right_box.add_child(grid)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(UI.button("정렬", _sort_stash, 13))
	row.add_child(UI.button("보물 모두 판매", _sell_treasure, 13))
	right_box.add_child(row)


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
		var kind: String = ("%s 무기" % Data.class_names(b.classes)) if b.has("classes") else ("소모품" if b.slot == "consumable" else Data.SLOT_NAMES[b.slot])
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
	right_box.add_child(UI.label("보관함의 아이템은 우클릭으로 판매할 수 있습니다.", 12, UI.MUTED))


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
func _select_class(cid: String) -> void:
	if save().cls == cid:
		return
	SaveData.op("select_class", [cid])
	Net.update_class(cid)


func _unequip(slot: String) -> void:
	SaveData.op("unequip", [slot])


func _bag_to_stash(i: int) -> void:
	SaveData.op("bag_to_stash", [i])


func _stash_click(i: int) -> void:
	SaveData.op("stash_click", [i])


func _sell(i: int) -> void:
	SaveData.op("sell", [i])


func _sell_treasure() -> void:
	SaveData.op("sell_treasure")


func _sort_stash() -> void:
	SaveData.op("sort_stash")


func _buy(base: String, _price: int) -> void:
	SaveData.op("buy", [base])


func _on_relief() -> void:
	SaveData.op("relief")
