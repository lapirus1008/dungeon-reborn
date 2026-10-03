# 진입점: 입력 설정, 테마, 로비 <-> 레이드 <-> 결과 전환, 그래픽 설정
extends Node

var lobby: Lobby
var game: Game
var hud: Hud
var results: Control
var overlay: CanvasLayer
var mode := "lobby"
var last_result = null


func _ready() -> void:
	_setup_input()
	get_tree().root.theme = UI.build_theme()
	ThemeDB.fallback_font = UI.font
	overlay = CanvasLayer.new()
	overlay.layer = 50
	add_child(overlay)
	# 토스트 영역
	var tb := VBoxContainer.new()
	tb.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tb.position = Vector2(-250, 120)
	tb.custom_minimum_size = Vector2(500, 0)
	tb.alignment = BoxContainer.ALIGNMENT_BEGIN
	tb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb.theme = UI.theme
	overlay.add_child(tb)
	UI.toast_box = tb
	# 툴팁
	UI.tooltip = PanelContainer.new()
	UI.tooltip.theme = UI.theme
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.03, 0.02, 0.96)
	sb.border_color = Color("#5a4a32")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	UI.tooltip.add_theme_stylebox_override("panel", sb)
	UI.tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.tooltip_label = RichTextLabel.new()
	UI.tooltip_label.bbcode_enabled = true
	UI.tooltip_label.fit_content = true
	UI.tooltip_label.custom_minimum_size = Vector2(250, 0)
	UI.tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.tooltip.add_child(UI.tooltip_label)
	UI.tooltip.visible = false
	overlay.add_child(UI.tooltip)
	apply_quality(SaveData.setting("quality", "mid"))
	_build_results()
	open_lobby()
	var args := OS.get_cmdline_user_args()
	if args.has("--autotest"):
		_autotest.call_deferred()
	elif args.has("--screenshots"):
		_screenshots.call_deferred(args[args.find("--screenshots") + 1])


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
		"sprint": [KEY_SHIFT], "jump": [KEY_SPACE], "skill_q": [KEY_Q], "skill_e": [KEY_E],
		"interact": [KEY_F], "inventory": [KEY_TAB, KEY_I], "map": [KEY_M],
		"potion1": [KEY_1], "potion2": [KEY_2], "menu": [KEY_ESCAPE],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	for pair in [["attack", MOUSE_BUTTON_LEFT], ["secondary", MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
		var mb := InputEventMouseButton.new()
		mb.button_index = pair[1]
		InputMap.action_add_event(pair[0], mb)


# 그래픽 품질: 3D 해상도 배율(FSR), MSAA, 그림자, 글로우, SSAO
func apply_quality(q: String) -> void:
	var vp := get_viewport()
	match q:
		"low":
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			vp.scaling_3d_scale = 0.67
			vp.msaa_3d = Viewport.MSAA_DISABLED
		"high":
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_2X
		_:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			vp.scaling_3d_scale = 0.85
			vp.msaa_3d = Viewport.MSAA_DISABLED
	if game and is_instance_valid(game):
		game.quality = q
		if game.player_light:
			game.player_light.shadow_enabled = q != "low"
		if game.env:
			game.env.environment.glow_enabled = q != "low"
			game.env.environment.ssao_enabled = q == "high"


func open_lobby() -> void:
	mode = "lobby"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	results.visible = false
	if lobby == null:
		lobby = Lobby.new()
		lobby.start_raid.connect(start_raid)
		lobby.theme = UI.theme
		add_child(lobby)
		lobby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby.visible = true
	lobby.refresh()


func start_raid() -> void:
	var s: Dictionary = SaveData.data
	var loadout := {"cls": s.cls, "equipment": s.equipment.duplicate(), "bag": s.bag.duplicate()}
	# 입장 시 소지품은 위험에 노출됨 (탈출해야 돌아옴)
	s.equipment = {"weapon": null, "head": null, "chest": null, "trinket": null}
	s.bag = []
	s.stats.raids += 1
	SaveData.save()
	UI.hide_tip()
	lobby.visible = false
	mode = "raid"
	game = Game.new()
	game.quality = SaveData.setting("quality", "mid")
	game.sensitivity = 0.0022 * float(SaveData.setting("sensitivity", 1.0))
	add_child(game)
	hud = Hud.new()
	add_child(hud)
	hud.menu_resume.connect(_close_menu)
	hud.menu_abandon.connect(func():
		_close_menu()
		game.abandon())
	hud.setting_changed.connect(_on_setting)
	game.raid_ended.connect(_on_raid_ended)
	game.start(loadout, hud)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_setting(key: String, value) -> void:
	SaveData.set_setting(key, value)
	if key == "sensitivity" and game:
		game.sensitivity = 0.0022 * float(value)
	elif key == "quality":
		apply_quality(value)


func _open_menu() -> void:
	game.menu_open = true
	hud.set_menu_visible(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_menu() -> void:
	if game == null:
		return
	game.menu_open = false
	hud.set_menu_visible(false)
	_update_mouse()


func _update_mouse() -> void:
	if mode != "raid" or game == null:
		return
	var free: bool = game.menu_open or hud.is_panel_open() or game.result != null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if free else Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if mode != "raid" or game == null or game.result != null:
		return
	if event.is_action_pressed("menu"):
		if hud.is_panel_open():
			hud.close_panels()
		elif game.menu_open:
			_close_menu()
		else:
			_open_menu()
		_update_mouse()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		if not game.menu_open:
			hud.toggle_inventory()
			_update_mouse()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map"):
		hud.toggle_map()
	elif event.is_action_pressed("interact") and hud.container != null and not game.menu_open:
		# 전리품 창이 열려 있을 때 F는 닫기
		hud.close_container()
		_update_mouse()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not game.menu_open and not hud.is_panel_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_dt: float) -> void:
	if mode == "raid" and game != null and game.result == null:
		# 상자를 열면 패널이 생기므로 마우스 상태 동기화
		var want_free: bool = game.menu_open or hud.is_panel_open()
		if want_free and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif not want_free and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and DisplayServer.window_is_focused():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# 툴팁이 마우스를 따라다님
	if UI.tooltip.visible:
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport().get_visible_rect().size
		var ts := UI.tooltip.size
		UI.tooltip.position = Vector2(minf(mp.x + 16, vs.x - ts.x - 8), minf(mp.y + 12, vs.y - ts.y - 8))


# ------------------------------------------------------------------ 결과
var res_title: Label
var res_sub: Label
var res_stats: RichTextLabel
var res_items: GridContainer


func _build_results() -> void:
	results = ColorRect.new()
	(results as ColorRect).color = Color(0, 0, 0, 0.7)
	results.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results.theme = UI.theme
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results.add_child(c)
	var p := UI.panel_box(Vector2(640, 0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	res_title = UI.label("", 48)
	res_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res_sub = UI.label("", 15, UI.MUTED)
	res_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res_stats = RichTextLabel.new()
	res_stats.bbcode_enabled = true
	res_stats.fit_content = true
	res_items = GridContainer.new()
	res_items.columns = 10
	res_items.add_theme_constant_override("h_separation", 5)
	res_items.add_theme_constant_override("v_separation", 5)
	v.add_child(res_title)
	v.add_child(res_sub)
	v.add_child(res_stats)
	var ic := CenterContainer.new()
	ic.add_child(res_items)
	v.add_child(ic)
	v.add_child(UI.big_button("로비로 돌아가기", _on_results_continue))
	c.add_child(p)
	results.visible = false
	overlay.add_child(results)


func _on_raid_ended(r: Dictionary) -> void:
	last_result = r
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.close_panels()
	res_title.text = "탈출 성공!" if r.success else "사망"
	res_title.add_theme_color_override("font_color", Color("#6ad0ff") if r.success else Color("#e04030"))
	res_sub.text = ("모든 전리품을 보관함으로 옮겼습니다 (심연 %d층)" % r.depth) if r.success else ("%s에게 쓰러졌습니다. 소지품을 모두 잃었습니다." % r.killer)
	res_stats.text = "[center]⏱ 생존 시간 [b]%d분 %d초[/b]   💀 몬스터 처치 [b]%d[/b]   ⚔ 모험가 처치 [b]%d[/b]   💰 %s 가치 [b]%d[/b][/center]" % [int(r.time / 60.0), int(r.time) % 60, r.kills, r.pvp_kills, "획득" if r.success else "손실", r.value]
	UI.clear(res_items)
	for it in r.items:
		var s := UI.slot(it)
		if not r.success:
			s.modulate = Color(0.45, 0.45, 0.45)
		res_items.add_child(s)
	results.visible = true


func _on_results_continue() -> void:
	var r = last_result
	var s: Dictionary = SaveData.data
	if r != null:
		s.stats.kills += r.kills
		s.stats.pvp_kills += r.pvp_kills
		if r.success:
			s.stats.extracts += 1
			s.stats.best_haul = maxi(int(s.stats.best_haul), int(r.value))
			s.equipment = r.equipment.duplicate()
			var sold := 0
			for it in r.bag:
				if s.stash.size() < SaveData.STASH_SIZE:
					s.stash.append(it)
				else:
					s.gold += it.value
					sold += it.value
			if sold > 0:
				UI.toast("보관함이 가득 차 남은 물건을 %dg에 판매했습니다" % sold)
		else:
			s.stats.deaths += 1
		SaveData.save()
	last_result = null
	if game:
		game.queue_free()
		game = null
	if hud:
		hud.queue_free()
		hud = null
	open_lobby()


# ------------------------------------------------------------------ 스크린샷 (godot -- --screenshots <폴더>)
func _shot(dir: String, name: String) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("[shot] ", name)


func _screenshots(dir: String) -> void:
	await get_tree().create_timer(0.5).timeout
	await _shot(dir, "1_lobby")
	var args := OS.get_cmdline_user_args()
	var cls := "mage"
	if args.has("--cls"):
		cls = args[args.find("--cls") + 1]
	SaveData.data.cls = cls
	SaveData.data.equipment.weapon = Data.make_item(Data.STARTER_WEAPON[cls])
	start_raid()
	game.force_act = true
	await get_tree().create_timer(1.0).timeout
	var g := game
	var p := g.player
	p.invuln = 999.0
	for a in g.actors:
		if a.kind == "monster" or a.kind == "bot":
			a.stun = 999.0
	# 횃불이 보이는 방향으로
	var t: Dictionary = g.dungeon.torches[0]
	p.pos = g.dungeon.resolve_circle(t.pos - t.n * 7.0, p.radius)
	p.pos.y = 0.0
	p.yaw = Actor.yaw_to(t.pos.x - p.pos.x, t.pos.z - p.pos.z) + 0.4
	p.pitch = 0.05
	await get_tree().create_timer(0.5).timeout
	await _shot(dir, "2_dungeon")
	# 몬스터 앞
	var m = null
	for a in g.actors:
		if a.kind == "monster" and a.type == "skeleton":
			m = a
			break
	if m != null:
		p.pos = g.dungeon.resolve_circle(m.pos + Vector3(3.5, 0, 0.5), p.radius)
		p.yaw = Actor.yaw_to(m.pos.x - p.pos.x, m.pos.z - p.pos.z)
		p.pitch = -0.05
		await get_tree().create_timer(0.4).timeout
		await _shot(dir, "3_monster")
	# 보호막 사용
	p.cast_shield()
	await get_tree().create_timer(0.3).timeout
	p.invuln = 0.0
	m = null
	for a in g.actors:
		if a.kind == "monster":
			m = a
			break
	if m != null:
		m.stun = 0.0
		m.take_damage(1.0, p)
	p.take_damage(20.0, m)
	await get_tree().create_timer(0.1).timeout
	await _shot(dir, "4_shield")
	# 포탈과 인벤토리
	g.spawn_portal("exit")
	var po = g.portals[g.portals.size() - 1]
	p.pos = g.dungeon.resolve_circle(po.pos + Vector3(0, 0, 6), p.radius)
	p.yaw = Actor.yaw_to(po.pos.x - p.pos.x, po.pos.z - p.pos.z)
	p.pitch = 0.1
	await get_tree().create_timer(0.6).timeout
	await _shot(dir, "5_portal")
	hud.toggle_inventory()
	await get_tree().create_timer(0.3).timeout
	await _shot(dir, "6_inventory")
	hud.toggle_inventory()
	hud.toggle_map()
	await get_tree().create_timer(0.3).timeout
	await _shot(dir, "7_map")
	get_tree().quit()


# ------------------------------------------------------------------ 자동 테스트 (godot -- --autotest)
func _autotest() -> void:
	print("[autotest] 시작")
	var out := []
	for cls in ["fighter", "ranger", "mage"]:
		SaveData.data.cls = cls
		var w := ""
		match cls:
			"fighter":
				w = "rusty_sword"
			"ranger":
				w = "short_bow"
			_:
				w = "oak_staff"
		SaveData.data.equipment.weapon = Data.make_item(w)
		start_raid()
		game.force_act = true
		await get_tree().process_frame
		var g := game
		var p := g.player
		# 몬스터 옆으로 이동해 공격
		var m = null
		for a in g.actors:
			if a.kind == "monster" and not a.def.boss:
				m = a
				break
		var hp0: float = m.hp
		p.pos = g.dungeon.resolve_circle(m.pos + Vector3(2, 0, 0), p.radius)
		for i in 120:
			var dx: float = m.pos.x - p.pos.x
			var dz: float = m.pos.z - p.pos.z
			p.yaw = Actor.yaw_to(dx, dz)
			var c: Vector3 = m.center()
			p.pitch = atan2(c.y - (p.pos.y + Player.EYE), sqrt(dx * dx + dz * dz))
			if cls != "ranger" or i % 40 < 30:
				Input.action_press("attack")
			else:
				Input.action_release("attack")
			await get_tree().process_frame
		Input.action_release("attack")
		out.append("%s: 몬스터 %s 체력 %.0f -> %.0f (생존 %s), 플레이어 체력 %.0f, FPS %d" % [cls, m.name, hp0, m.hp, m.alive, p.hp, Engine.get_frames_per_second()])
		if cls == "mage":
			Input.action_press("secondary")
			await get_tree().process_frame
			Input.action_release("secondary")
			await get_tree().process_frame
			out.append("  보호막: %.0f, 남은시간 %.1f, 구체 표시 %s" % [p.shield, p.shield_t, g.shield_bubble.visible])
		# 탈출
		g.spawn_portal("exit")
		var po = g.portals[g.portals.size() - 1]
		p.invuln = 999.0
		p.pos = po.pos
		for i in 260:
			p.pos = po.pos
			await get_tree().process_frame
			if g.result != null:
				break
		out.append("  탈출 결과: %s" % (str(g.result.success) if g.result != null else "없음"))
		while results.visible == false and game != null:
			await get_tree().process_frame
		_on_results_continue()
		await get_tree().process_frame
	# 긴 시뮬레이션: 봇/몬스터 상호작용
	start_raid()
	await get_tree().process_frame
	game.player.invuln = 1e9
	var t0 := Time.get_ticks_msec()
	for i in 60 * 120:
		game.player.invuln = 1e9
		game._process(1.0 / 60.0)
		if i % 600 == 0:
			await get_tree().process_frame
	var ms := float(Time.get_ticks_msec() - t0) / (60 * 120)
	var bots := 0
	for a in game.actors:
		if a.kind == "bot" and a.alive:
			bots += 1
	out.append("시뮬레이션 120초: 생존 봇 %d, 상자 열림 %d/%d, 액터 %d, 프레임당 로직 %.2fms" % [bots, game.chests.filter(func(c): return c.opened).size(), game.chests.size(), game.actors.size(), ms])
	for line in out:
		print("[autotest] ", line)
	print("[autotest] 완료")
	get_tree().quit()
