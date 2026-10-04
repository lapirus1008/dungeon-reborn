# 진입점: 입력 설정, 테마, 로비 <-> 레이드 <-> 결과 전환, 그래픽 설정
extends Node

var lobby: Lobby
var game: Game
var hud: Hud
var results: Control
var overlay: CanvasLayer
var mode := "lobby"
var last_result = null
var pending_loadout = null # 함께하기: 서버에 제출했지만 아직 시작되지 않은 장비
var dedicated := false


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
	# 인벤토리 드래그 (툴팁 아래, 모든 화면 위)
	var drag := InvDrag.new()
	drag.theme = UI.theme
	overlay.add_child(drag)
	overlay.move_child(drag, overlay.get_child_count() - 2)
	Net.prepare_received.connect(_on_net_prepare)
	Net.begin_received.connect(_on_net_begin)
	Net.server_begin.connect(_on_server_begin)
	Net.disconnected.connect(_on_net_disconnected)
	Net.local_loadout_cb = func() -> Dictionary:
		pending_loadout = _take_loadout()
		return pending_loadout
	var args := OS.get_cmdline_user_args()
	if args.has("--server"):
		_run_dedicated(args)
		return
	apply_quality(SaveData.setting("quality", "mid"))
	_build_results()
	open_lobby()
	if args.has("--mptest"):
		_mptest.call_deferred(args[args.find("--mptest") + 1])
	elif args.has("--lobbyshots"):
		_lobbyshots.call_deferred(args[args.find("--lobbyshots") + 1])
	elif args.has("--invshots"):
		_invshots.call_deferred(args[args.find("--invshots") + 1])
	elif args.has("--invtest"):
		for l in _inv_checks():
			print("[invtest] ", l)
		get_tree().quit()
	elif args.has("--autotest"):
		_autotest.call_deferred()
	elif args.has("--screenshots"):
		_screenshots.call_deferred(args[args.find("--screenshots") + 1])


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
		"sprint": [KEY_SHIFT], "jump": [KEY_SPACE], "skill_q": [KEY_Q], "skill_e": [KEY_E],
		"interact": [KEY_F], "inventory": [KEY_TAB, KEY_I], "map": [KEY_M],
		"potion1": [KEY_1], "potion2": [KEY_2], "potion3": [KEY_3], "menu": [KEY_ESCAPE],
		"throw": [KEY_G], "swap_weapon": [KEY_X],
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


# 입장 시 소지품은 위험에 노출됨 (탈출해야 돌아옴)
func _take_loadout() -> Dictionary:
	var lo := Account.take_loadout(SaveData.data)
	SaveData.save()
	return lo


# 레이드가 시작되지 못했으면 제출한 장비를 되돌림
func _restore_loadout() -> void:
	if pending_loadout == null:
		return
	Account.restore_loadout(SaveData.local_data, pending_loadout)
	SaveData.save()
	pending_loadout = null


# 레이드 입장. 함께하기: 그 맵의 대기방에 들어가면 서버가 시간을 재다가 함께 시작
# (로비의 대기방 화면이 오프라인 로딩 10초를 보여 준 뒤 이 함수를 부름)
func start_raid(map := "") -> void:
	if map == "":
		map = Data.MAP_ORDER[Data.MAP_ORDER.size() - 1]
	if Net.online():
		Net.join_room(map)
		return
	var loadout := _take_loadout()
	loadout["map"] = map
	_create_game()
	game.start(loadout, hud)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _create_game() -> void:
	UI.hide_tip()
	if lobby != null:
		lobby.visible = false
	results.visible = false
	if game != null and is_instance_valid(game):
		game.queue_free()
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
	game.raid_over.connect(_on_raid_over.bind(game))


# ------------------------------------------------------------------ 함께하기
func _on_net_prepare() -> void:
	# 온라인 서버 계정이면 서버가 계정에서 직접 장비를 꺼낸다
	if mode != "lobby" or SaveData.online:
		return
	pending_loadout = _take_loadout()
	Net.send_loadout(pending_loadout)


func _on_net_begin(info: Dictionary) -> void:
	pending_loadout = null
	_create_game()
	game.start_client(info, hud)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# 서버(호스트/전용): 모인 장비로 레이드 생성
func _on_server_begin(loadouts: Dictionary) -> void:
	var hs := []
	var ids := loadouts.keys()
	ids.sort()
	for id in ids:
		var lo: Dictionary = loadouts[id]
		hs.append({"peer": id, "name": Net.roster.get(id, {}).get("name", "모험가"), "cls": lo.cls, "equipment": lo.equipment, "bag": lo.bag,
			"skills": lo.get("skills", {}), "wset": int(lo.get("wset", 1)), "char": lo.get("char", "")})
	if dedicated:
		game = Game.new()
		add_child(game)
		game.raid_over.connect(_on_raid_over.bind(game))
		game.start_server("server", hs, Net.pvp, null, Net.raid_map)
		print("[server] 레이드 시작: %d명" % hs.size())
		return
	pending_loadout = null
	_create_game()
	game.start_server("host", hs, Net.pvp, hud, Net.raid_map)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_raid_over(g) -> void:
	Net.game = null
	if dedicated:
		print("[server] 레이드 종료")
	# 결과 화면을 이미 넘겨 백그라운드로 돌던 레이드면 정리
	if g != game or mode != "raid" or dedicated:
		if is_instance_valid(g):
			g.queue_free()
		if g == game:
			game = null
	if lobby != null and lobby.visible:
		lobby.refresh()


func _on_net_disconnected(reason: String) -> void:
	_restore_loadout()
	UI.toast(reason)
	if mode == "raid" and game != null and game.net == "client":
		# 레이드 중 끊기면 사망과 같음 (소지품 손실)
		if game.result == null and not SaveData.online:
			SaveData.data.stats.deaths += 1
			SaveData.save()
		Net.game = null
		game.queue_free()
		game = null
		if hud:
			hud.queue_free()
			hud = null
		open_lobby()
	elif lobby != null and lobby.visible:
		lobby.refresh()


# 전용 서버: godot --headless -- --server [--port 7777]
func _run_dedicated(args: PackedStringArray) -> void:
	dedicated = true
	var port := Net.PORT
	if args.has("--port"):
		port = int(args[args.find("--port") + 1])
	# 계정 DB 위치 (기본: user://accounts). --no-accounts 면 각자 PC 저장 파일 사용
	var acc_dir := ProjectSettings.globalize_path("user://accounts")
	if args.has("--accounts"):
		acc_dir = args[args.find("--accounts") + 1]
	if args.has("--no-accounts"):
		acc_dir = ""
	var err := Net.host(port, "서버", true, acc_dir)
	if err != "":
		printerr(err)
		get_tree().quit(1)
		return
	if args.has("--pvp"):
		Net.pvp = true
	print("[server] Dungeon Reborn 전용 서버 - UDP 포트 %d, 계정 %s. 가장 먼저 접속한 사람이 레이드를 시작합니다." % [port, "서버 저장" if acc_dir != "" else "각자 PC 저장"])


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
	# 온라인 서버 계정은 서버가 이미 결과를 반영해 보내 줌
	if r != null and not SaveData.online:
		var msg := Account.apply_result(SaveData.data, r)
		if msg != "":
			UI.toast(msg)
		SaveData.save()
	last_result = null
	if game:
		if game.net == "host" and game.running:
			# 친구들이 아직 던전에 있으면 레이드는 뒤에서 계속 진행
			game.hud = null
			game.visible = false
			if game.camera:
				game.camera.current = false
		else:
			if game.net != "offline":
				Net.game = null
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
	var args := OS.get_cmdline_user_args()
	var cls := "priest"
	if args.has("--cls"):
		cls = args[args.find("--cls") + 1]
	var map := "sinners_end_1"
	if args.has("--map"):
		map = args[args.find("--map") + 1]
	_test_char(cls)
	lobby.refresh()
	await get_tree().create_timer(0.3).timeout
	await _shot(dir, "1_lobby")
	lobby._open_maps()
	await get_tree().create_timer(0.3).timeout
	await _shot(dir, "1b_maps")
	lobby._enter_map(map)
	await get_tree().create_timer(2.5).timeout
	await _shot(dir, "1c_waiting_room")
	lobby._leave_wait()
	start_raid(map)
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
		if a.kind == "monster" and not a.def.boss and a.type != "pest" and a.pos.distance_to(p.pos) < 60.0:
			m = a
			break
	if m != null:
		p.pos = g.dungeon.resolve_circle(m.pos + Vector3(3.5, 0, 0.5), p.radius)
		p.yaw = Actor.yaw_to(m.pos.x - p.pos.x, m.pos.z - p.pos.z)
		p.pitch = -0.05
		await get_tree().create_timer(0.4).timeout
		await _shot(dir, "3_monster")
	if args.has("--skills"):
		await _skill_shots(dir, g, p, m)
		get_tree().quit()
		return
	# 보호막 사용 (프리스트 수호)
	Skills.use_e(p, p.aim())
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
	# 바닥에 버린 아이템: 아이템 모양 + 등급 빛줄기
	var fw := Actor.fwd(p.yaw)
	var side := Vector3(cos(p.yaw), 0, -sin(p.yaw))
	var drops := ["old_sword", "traveler_armor", "soldier_bascinet", "knight_sword", "the_17th_key"]
	for i in drops.size():
		g.drop_item(p.pos + fw * 3.2 + side * (i - 2) * 1.1, Data.make_item(drops[i]))
	p.pitch = -0.25
	await get_tree().create_timer(0.4).timeout
	await _shot(dir, "5b_ground_items")
	hud.toggle_inventory()
	await get_tree().create_timer(0.3).timeout
	await _shot(dir, "6_inventory")
	hud.toggle_inventory()
	hud.toggle_map()
	await get_tree().create_timer(0.3).timeout
	await _shot(dir, "7_map")
	get_tree().quit()


# 직업 스킬 효과 스크린샷 + 8직업 AI 모델 나란히
func _skill_shots(dir: String, g, p, m) -> void:
	p.res = p.res_max()
	if p.cls == "druid":
		Skills.use_e(p, p.aim())
		await get_tree().create_timer(0.5).timeout
		await _shot(dir, "4_e")
		p.res = p.res_max()
		Skills.use_q(p, p.aim())
		await get_tree().create_timer(0.4).timeout
		await _shot(dir, "5_q")
	else:
		Skills.use_q(p, p.aim())
		await get_tree().create_timer(0.35 if p.cls != "cryomancer" else 0.8).timeout
		await _shot(dir, "4_q")
		p.res = p.res_max()
		p.spin_t = 0.0
		Skills.use_e(p, p.aim())
		await get_tree().create_timer(0.4 if p.cls != "rogue" else 1.8).timeout
		await _shot(dir, "5_e")
	# 8직업 AI 모험가 모델
	for a in g.actors:
		if a.kind == "bot":
			a.set_visible(false)
			a.alive = false
	var f := Actor.fwd(p.yaw)
	var r := Vector3(cos(p.yaw), 0, -sin(p.yaw))
	var i := 0
	for c in Data.CLASS_ORDER:
		var b := Bot.new(g, p.pos + f * 5.0 + r * (i - 3.5) * 1.1, 1, c)
		b.yaw = p.yaw + PI
		b.stun = 999.0
		g.actors.append(b)
		i += 1
	p.frozen = 0.0
	p.stealth = 0.0
	await get_tree().create_timer(0.5).timeout
	await _shot(dir, "6_classes")


# ------------------------------------------------------------------ 자동 테스트 (godot -- --autotest)
# 테스트용: 현재 캐릭터를 해당 직업의 새 캐릭터(기본 장비)로 교체
func _test_char(cls: String) -> void:
	var d: Dictionary = SaveData.data
	var c := Account.new_character("테스트", cls)
	var cur := Account.cur(d)
	c.id = cur.id
	d.characters[d.characters.find(cur)] = c
	Account.select(d, c.id)


func _autotest() -> void:
	print("[autotest] 시작")
	var out := []
	# 데이터 검사: 상점/기본 무기가 모두 존재하는 아이템인지 (상점 진입 오류 방지)
	var missing := []
	for e in Account.SHOP:
		if not Data.ITEM_BASES.has(e[0]):
			missing.append(e[0])
	for c in Data.STARTER_WEAPON:
		if not Data.ITEM_BASES.has(Data.STARTER_WEAPON[c]):
			missing.append(Data.STARTER_WEAPON[c])
	out.append("데이터 검사: 없는 아이템 %s" % (str(missing) if missing.size() else "없음"))
	out.append_array(_inv_checks())
	for cls in Data.CLASS_ORDER:
		_test_char(cls)
		start_raid()
		game.force_act = true
		await get_tree().process_frame
		var g := game
		var p := g.player
		# 몬스터 옆으로 이동해 기본 공격
		var m = null
		for a in g.actors:
			if a.kind == "monster" and not a.def.boss:
				m = a
				break
		var hp0: float = m.hp
		p.pos = g.dungeon.resolve_circle(m.pos + Vector3(2, 0, 0), p.radius)
		m.stun = 2.0
		for i in 150:
			var dx: float = m.pos.x - p.pos.x
			var dz: float = m.pos.z - p.pos.z
			p.yaw = Actor.yaw_to(dx, dz)
			var c: Vector3 = m.center()
			p.pitch = atan2(c.y - (p.pos.y + Player.EYE), sqrt(dx * dx + dz * dz))
			Input.action_press("attack")
			await get_tree().process_frame
		Input.action_release("attack")
		var line := "%s: 기본 공격 %s 체력 %.0f -> %.0f" % [Data.CLASSES[cls].name, m.name, hp0, m.hp]
		# Q, E 스킬 (자원 가득 채운 뒤)
		p.res = p.res_max() if p.res_max() > 0.0 else 0.0
		p.stamina = 100.0
		# 드루이드는 인간 형태에서 E(트렌트)를 먼저 확인
		var e_first: bool = cls == "druid"
		var e_ok := false
		if e_first:
			e_ok = Skills.use_e(p, p.aim())
		var q_ok := Skills.use_q(p, p.aim())
		if not q_ok and p.equipment.w2 != null:
			# 스킬 조건(양손/지팡이)이 맞지 않으면 무기 세트 2로 바꿔서 다시
			p.swing = null
			p.spin_t = 0.0
			p.swap_weapon_set()
			p.cd.q = 0.0
			q_ok = Skills.use_q(p, p.aim())
		for i in 30:
			await get_tree().process_frame
		p.res = p.res_max() if p.res_max() > 0.0 else 0.0
		p.frozen = 0.0
		if not e_first:
			e_ok = Skills.use_e(p, p.aim())
		for i in 120:
			await get_tree().process_frame
		line += " | Q %s, E %s" % ["O" if q_ok else "X", "O" if e_ok else "X"]
		if cls == "druid":
			line += " | 표범 %s, 트렌트 %d" % [p.panther, g.actors.filter(func(a): return a.kind == "summon").size()]
		if cls == "rogue":
			line += " | 은신 %.1f초" % p.stealth
		if cls == "priest":
			line += " | 보호막 %.0f" % p.shield
		out.append(line)
		print("[autotest] ", line)
		# 탈출
		g.spawn_portal("exit")
		var po = g.portals[g.portals.size() - 1]
		p.invuln = 999.0
		p.frozen = 0.0
		var et := 0.0
		while et < 6.0 and g.result == null:
			p.pos = po.pos
			await get_tree().process_frame
			et += get_process_delta_time()
		out.append("  탈출 결과: %s" % (str(g.result.success) if g.result != null else "없음"))
		while results.visible == false and game != null:
			await get_tree().process_frame
		_on_results_continue()
		await get_tree().process_frame
	# 스태미나: 바닥난 뒤 Shift를 계속 눌러도 30까지 회복 후에만 달리기
	_test_char("fighter")
	start_raid()
	game.force_act = true
	await get_tree().process_frame
	var pl := game.player
	pl.invuln = 999.0
	Input.action_press("sprint")
	Input.action_press("move_forward")
	var toggles := 0
	var was := false
	var min_st := 100.0
	for i in 60 * 12:
		await get_tree().process_frame
		if pl.sprinting != was:
			toggles += 1
			was = pl.sprinting
		min_st = minf(min_st, pl.stamina)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	out.append("스태미나 12초 연속 달리기: 달리기/걷기 전환 %d회 (짧은 반복이면 수십 회), 최저 %.0f" % [toggles, min_st])
	game.abandon()
	while results.visible == false:
		await get_tree().process_frame
	_on_results_continue()
	await get_tree().process_frame
	# 긴 시뮬레이션: 8직업 봇/몬스터 상호작용
	start_raid()
	await get_tree().process_frame
	game.player.invuln = 1e9
	var t0 := Time.get_ticks_msec()
	var classes := {}
	for a in game.actors:
		if a.kind == "bot":
			classes[a.cls] = true
	for i in 60 * 150:
		game.player.invuln = 1e9
		game._process(1.0 / 60.0)
		if i % 600 == 0:
			await get_tree().process_frame
	var ms := float(Time.get_ticks_msec() - t0) / (60 * 150)
	var bots := 0
	for a in game.actors:
		if a.kind == "bot" and a.alive:
			bots += 1
	out.append("시뮬레이션 150초: 봇 직업 %s, 생존 봇 %d, 상자 열림 %d/%d, 프레임당 로직 %.2fms" % [classes.keys(), bots, game.chests.filter(func(c): return c.opened).size(), game.chests.size(), ms])
	for line in out:
		print("[autotest] ", line)
	print("[autotest] 완료")
	get_tree().quit()


# ------------------------------------------------------------------ 함께하기 자동 테스트
# 호스트:   godot --headless -- --mptest host --profile h
# 클라이언트: godot --headless -- --mptest client --profile c
func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot_dir() -> String:
	var args := OS.get_cmdline_user_args()
	return args[args.find("--shots") + 1] if args.has("--shots") else ""


func _mptest(role: String) -> void:
	var port := 7790
	print("[mptest] 역할: ", role)
	_test_char("fighter" if role == "host" else "pyromancer")
	Inv.add_auto(SaveData.data.bag, Inv.bag_size(SaveData.data.cls), Data.make_item("health_potion"))
	if role == "host":
		await _mptest_host(port)
	elif role == "account":
		await _mptest_account(port)
	else:
		await _mptest_client(port)
	print("[mptest] 완료")
	get_tree().quit()


func _mptest_host(port: int) -> void:
	var err := Net.host(port, "호스트")
	if err != "":
		print("[mptest] 실패: ", err)
		return
	var t := 0.0
	while Net.roster.size() < 2 and t < 30.0:
		await _wait(0.2)
		t += 0.2
	print("[mptest] 대기실 인원 ", Net.roster.size())
	start_raid("sinners_end_1")
	t = 0.0
	while (game == null or not game.running) and t < 30.0:
		await _wait(0.1)
		t += 0.1
	var g := game
	g.force_act = true
	g.player.invuln = 999.0
	var r = null
	for p in g.players:
		if p.peer_id > 1:
			r = p
	print("[mptest] 레이드 플레이어 %d명, 원격 %s" % [g.players.size(), r.name if r != null else "없음"])
	r.invuln = 999.0
	var start_pos: Vector3 = r.pos
	await _wait(3.0)
	print("[mptest] 원격 입력 수신 %s, 이동 거리 %.1fm" % [r.has_net, r.pos.distance_to(start_pos)])
	# 원격 플레이어를 몬스터 옆으로 (서버 강제 위치 -> 클라이언트 동기화 확인)
	var m = null
	for a in g.actors:
		if a.kind == "monster" and not a.def.boss and a.alive:
			m = a
			break
	m.stun = 30.0
	m.invuln = 0.0
	var hp0: float = m.hp
	r.pos = g.dungeon.resolve_circle(m.pos + Vector3(2.2, 0, 0), r.radius)
	r.forced_t = 1.5
	await _wait(2.5)
	var shots := _shot_dir()
	if shots != "":
		# 호스트 화면: 친구(원격 플레이어)가 몬스터를 공격하는 모습
		var hp_pos: Vector3 = r.pos + Vector3(0, 0, 4.5)
		g.player.pos = g.dungeon.resolve_circle(hp_pos, g.player.radius)
		g.player.yaw = Actor.yaw_to(r.pos.x - g.player.pos.x, r.pos.z - g.player.pos.z) + 0.25
		g.player.pitch = -0.08
		await _wait(0.4)
		await _shot(shots, "mp_host_view")
	await _wait(2.0)
	print("[mptest] 원격 플레이어 공격: 몬스터 체력 %.0f -> %.0f (공격자 %s), 원격 마나 %.0f" % [hp0, m.hp, m.last_attacker.name if m.last_attacker != null else "없음", r.res])
	# 상자 열기
	var c = null
	for ch in g.chests:
		if not ch.opened:
			c = ch
			break
	var bag0: int = r.bag.size()
	r.pos = g.dungeon.resolve_circle(c.pos + Vector3(1.2, 0, 0), r.radius)
	r.yaw = Actor.yaw_to(c.pos.x - r.pos.x, c.pos.z - r.pos.z)
	r.forced_t = 1.0
	t = 0.0
	while not c.opened and t < 8.0:
		await _wait(0.1)
		t += 0.1
	await _wait(2.0)
	print("[mptest] 상자 열림 %s, 원격 가방 %d -> %d" % [c.opened, bag0, r.bag.size()])
	# 탈출
	g.spawn_portal("exit")
	var po = g.portals[g.portals.size() - 1]
	t = 0.0
	while not r.done and t < 8.0:
		r.pos = po.pos
		r.forced_t = 0.5
		await get_tree().process_frame
		t += get_process_delta_time()
	print("[mptest] 원격 플레이어 탈출 %s (성공 %s)" % [r.done, r.extracted])
	await _wait(1.0)
	# 호스트 탈출 -> 결과 -> 레이드 종료
	t = 0.0
	while not results.visible and t < 8.0:
		g.player.pos = po.pos
		await get_tree().process_frame
		t += get_process_delta_time()
	print("[mptest] 호스트 결과 화면 %s (%s), 레이드 종료 %s" % [results.visible, last_result.success if last_result != null else "?", g.over])
	_on_results_continue()
	await _wait(0.5)
	print("[mptest] 대기실 복귀: 레이드 진행 중 %s, 보관함 %d" % [Net.raid_running(), SaveData.data.stash.size()])
	await _wait(1.0)


func _mptest_client(port: int) -> void:
	await _wait(1.0)
	var err := Net.join("127.0.0.1", port, "친구")
	if err != "":
		print("[mptest] 실패: ", err)
		return
	var t := 0.0
	while Net.roster.is_empty() and t < 10.0:
		await _wait(0.1)
		t += 0.1
	# 같은 맵 대기방에 들어감 (모두 들어가면 10초 뒤 시작)
	await _wait(0.5)
	print("[mptest] 대기방 입장")
	start_raid("sinners_end_1")
	t = 0.0
	while (game == null or not game.running) and t < 30.0:
		await _wait(0.1)
		t += 0.1
	if game == null:
		print("[mptest] 레이드 시작 정보 없음")
		return
	var g := game
	g.force_act = true
	var proxies := g.actors.filter(func(a): return a is NetActor)
	print("[mptest] 클라이언트 입장: 대리 액터 %d, 상자 %d, 던전 방 %d" % [proxies.size(), g.chests.size(), g.dungeon.rooms.size()])
	await _wait(0.5)
	Input.action_press("move_forward")
	await _wait(1.5)
	Input.action_release("move_forward")
	await _wait(1.5)
	# 서버가 몬스터 옆으로 옮겨 줌 -> 가장 가까운 몬스터를 조준해 공격
	var p := g.player
	print("[mptest] 서버 강제 이동 반영 위치 %s" % p.pos)
	var target = null
	var bd := 1e9
	for a in g.actors:
		if a is NetActor and a.kind == "monster" and a.alive and a.pos.distance_to(p.pos) < bd:
			bd = a.pos.distance_to(p.pos)
			target = a
	print("[mptest] 가장 가까운 몬스터 %.1fm" % bd)
	Input.action_press("attack")
	var at := 0.0
	while at < 3.0:
		at += get_process_delta_time()
		if target != null:
			var dx: float = target.pos.x - p.pos.x
			var dz: float = target.pos.z - p.pos.z
			p.yaw = Actor.yaw_to(dx, dz)
			p.pitch = atan2(target.center().y - (p.pos.y + Player.EYE), sqrt(dx * dx + dz * dz))
		await get_tree().process_frame
	Input.action_release("attack")
	var shots := _shot_dir()
	if shots != "":
		Input.action_press("attack")
		await _wait(0.3)
		await _shot(shots, "mp_client_view")
		Input.action_release("attack")
	print("[mptest] 투사체 표시 기록: %d개 진행 중, 대상 체력 %.0f" % [g.net_proj.size(), target.hp if target != null else -1.0])
	# 서버가 상자 옆으로 옮겨 줄 때까지 기다렸다가 상자 열기 (F 길게) -> 모두 가져가기
	t = 0.0
	while t < 10.0:
		var near := false
		for c in g.chests:
			if not c.opened and c.pos.distance_to(p.pos) < 2.0:
				near = true
		if near:
			break
		await _wait(0.1)
		t += 0.1
	Input.action_press("interact")
	await _wait(2.0)
	Input.action_release("interact")
	await _wait(0.5)
	print("[mptest] 상자 창 열림 %s" % (hud.container != null))
	if hud.container != null:
		hud._take_all()
	await _wait(0.8)
	print("[mptest] 클라이언트 가방 %d개" % g.player.bag.size())
	t = 0.0
	while not results.visible and t < 15.0:
		await _wait(0.1)
		t += 0.1
	print("[mptest] 클라이언트 결과: %s, 아이템 %d개" % [last_result.success if last_result != null else "없음", last_result.items.size() if last_result != null else 0])
	var stash0: int = SaveData.data.stash.size()
	_on_results_continue()
	print("[mptest] 보관함 %d -> %d" % [stash0, SaveData.data.stash.size()])
	await _wait(1.0)


# 온라인 서버 계정 테스트 (전용 서버: --server --port 7790 --accounts <폴더>)
func _mptest_account(port: int) -> void:
	if OS.get_cmdline_user_args().has("--port"):
		port = int(OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--port") + 1])
	var nm := "계정테스트%d" % (randi() % 1000)
	var login := func(pin: String) -> bool:
		Net.join("127.0.0.1", port, nm, pin)
		var t := 0.0
		while not SaveData.online and Net.online() and t < 8.0:
			await _wait(0.1)
			t += 0.1
		return SaveData.online
	var local_gold: int = SaveData.local_data.gold
	var ok: bool = await login.call("1234")
	print("[mptest] 로그인(새 계정) %s, 서버 골드 %d, 장비 무기 %s" % [ok, SaveData.data.gold, SaveData.data.equipment.w1 != null])
	var g0: int = SaveData.data.gold
	SaveData.op("buy", ["health_potion"])
	SaveData.op("buy", ["short_bow"]) # 없는 물건: 서버가 거부해야 함
	await _wait(1.0)
	print("[mptest] 서버 상점 구매: 골드 %d -> %d (로컬 저장 골드 %d 그대로: %s)" % [g0, SaveData.data.gold, local_gold, SaveData.local_data.gold == local_gold])
	# 레이드 시작 후 접속 끊기 -> 서버가 사망 처리, 장비 손실
	start_raid("clouseau_castle")
	var t := 0.0
	while (game == null or not game.running) and t < 30.0:
		await _wait(0.1)
		t += 0.1
	print("[mptest] 레이드 입장 %s, 입장 후 서버 계정 무기 %s (서버가 꺼냄)" % [game != null, SaveData.data.equipment.w1])
	await _wait(1.0)
	Net.leave()
	if game:
		Net.game = null
		game.queue_free()
		game = null
		hud.queue_free()
		hud = null
	open_lobby()
	await _wait(1.0)
	ok = await login.call("9999")
	print("[mptest] 틀린 PIN 로그인 거부: %s (%s)" % [not ok, Net.status])
	await _wait(0.5)
	ok = await login.call("1234")
	print("[mptest] 재로그인 %s: 사망 %d, 입장 %d, 무기 %s, 골드 %d" % [ok, SaveData.data.stats.deaths, SaveData.data.stats.raids, SaveData.data.equipment.w1, SaveData.data.gold])
	Net.leave()
	await _wait(0.5)


# 격자 인벤토리 규칙 검사
func _inv_checks() -> Array:
	var out := []
	var d := Account.fresh()
	d.bag.clear()
	var ok := func(name: String, cond: bool) -> void:
		out.append("인벤토리 %s: %s" % [name, "O" if cond else "X 실패"])
	# 상의(2x3) 놓기 / 겹침 거부 / 회전
	var chest := Data.make_item("soldier_armor")
	Inv.add_auto(d.stash, Inv.STASH, chest)
	var helm := Data.make_item("soldier_bascinet")
	Inv.add_auto(d.stash, Inv.STASH, helm)
	var r1 := Account.apply(d, "move", ["stash", chest.id, "bag", 0, 0, false])
	var r2 := Account.apply(d, "move", ["stash", helm.id, "bag", 1, 1, false])
	ok.call("6칸 상의 가방 배치 / 겹치면 거부", r1.ok and not r2.ok)
	var r3 := Account.apply(d, "move", ["stash", helm.id, "bag", 2, 0, false])
	var ls := Data.make_item("traveler_longsword")
	Inv.add_auto(d.stash, Inv.STASH, ls)
	var r4 := Account.apply(d, "move", ["stash", ls.id, "bag", 4, 0, true]) # 1x4 를 눕혀서 4x1
	ok.call("4칸 투구 배치 + 회전(1x4→4x1)", r3.ok and r4.ok and Data.item_size(ls) == Vector2i(4, 1))
	# 우클릭 장착: 기존 상의(낡은 판금 상의)는 가방으로
	var r5 := Account.apply(d, "quick", ["bag", chest.id])
	var old_in_bag = d.bag.any(func(it): return it.base == "old_plate_chest")
	ok.call("우클릭 장착/교체", r5.ok and d.equipment.chest.id == chest.id and old_in_bag)
	# 양손검 장착 → 보조 손 방패는 가방으로
	var r5b := Account.apply(d, "move", ["bag", ls.id, "equip", -1, -1, false, "w1"])
	var shield_in_bag = d.bag.any(func(it): return it.base == "old_shield")
	ok.call("양손 무기 장착 시 보조 손 해제", r5b.ok and d.equipment.w1.id == ls.id and d.equipment.w1o == null and shield_in_bag)
	# 반지 두 칸
	var ring_a := Data.make_item("copper_ring")
	var ring_b := Data.make_item("ruby_ring")
	Inv.add_auto(d.bag, Inv.bag_size(d.cls), ring_a)
	Inv.add_auto(d.bag, Inv.bag_size(d.cls), ring_b)
	Account.apply(d, "quick", ["bag", ring_a.id])
	Account.apply(d, "quick", ["bag", ring_b.id])
	ok.call("반지 2칸", d.equipment.ring1 != null and d.equipment.ring2 != null)
	# 다른 직업 무기 장착 거부
	var staff := Data.make_item("pyro_staff")
	Inv.add_auto(d.bag, Inv.bag_size(d.cls), staff)
	var r6 := Account.apply(d, "move", ["bag", staff.id, "equip", -1, -1, false, "w2"])
	ok.call("직업 무기 제한", not r6.ok)
	# 물약 겹치기 (같은 아이템은 한 칸에 쌓임)
	var pot := Data.make_item("health_potion")
	Inv.add_auto(d.bag, Inv.bag_size(d.cls), pot)
	var n0: int = d.equipment.q1.count
	var r6b := Account.apply(d, "move", ["bag", pot.id, "equip", -1, -1, false, "q1"])
	ok.call("소모품 겹치기 (%d→%d)" % [n0, d.equipment.q1.count], r6b.ok and d.equipment.q1.count == n0 + 1 and Inv.index_of(d.bag, pot.id) < 0)
	# 판매
	var g0: int = d.gold
	var r7 := Account.apply(d, "sell", ["bag", staff.id])
	ok.call("판매", r7.ok and d.gold > g0 and Inv.index_of(d.bag, staff.id) < 0)
	# 능력치/패시브: 옵션으로 능력치가 오르면 패시브가 열림
	var st0 := Data.compute_stats("fighter", d.equipment)
	var need := {}
	for i in Data.PASSIVES.fighter.size():
		if not (i in st0.passives):
			for k in Data.PASSIVES.fighter[i].req:
				need = {"k": k, "v": int(Data.PASSIVES.fighter[i].req[k]) - int(st0.attrs[k])}
			break
	var amulet := Data.make_item("bone_necklace")
	amulet.affixes = [need]
	d.equipment.necklace = amulet
	var st1 := Data.compute_stats("fighter", d.equipment)
	ok.call("능력치 옵션 → 패시브 해금 (%s → %s)" % [st0.passives, st1.passives], st1.passives.size() > st0.passives.size())
	# 무기 세트 교체
	Account.apply(d, "swap_set", [])
	ok.call("무기 세트 교체 (세트 2: 양손검)", int(d.wset) == 2 and Data.weapon_cat(d.equipment, 2) == "longsword")
	Account.apply(d, "swap_set", [])
	# 캐릭터: 직업별로 만들기 / 스킬 선택 / 선택 전환
	var first: String = d.active
	var rc := Account.apply(d, "create_char", ["불꽃", "pyromancer"])
	ok.call("캐릭터 생성 (화염술사, 가방 %s)" % Inv.bag_size("pyromancer"), rc.ok and d.cls == "pyromancer" and d.equipment.w1 != null and d.bag.is_empty())
	var rs := Account.apply(d, "set_skill", ["e", Data.CLASSES.pyromancer.e[-1]])
	var bad := Account.apply(d, "set_skill", ["q", "fighter_whirlwind"])
	ok.call("Q/E 스킬 선택 (다른 직업 스킬 거부)", rs.ok and d.skills.e == Data.CLASSES.pyromancer.e[-1] and not bad.ok)
	Account.apply(d, "select_char", [first])
	ok.call("캐릭터 전환 (장비 유지)", d.cls == "fighter" and d.equipment.chest.id == chest.id)
	# 예전 세이브 변환 (단일 캐릭터, 예전 무기 칸)
	var old := {"cls": "fighter", "gold": 10, "equipment": {"weapon": Data.make_item("old_sword"), "head": null, "chest": null, "trinket": Data.make_item("bone_necklace")},
		"bag": [Data.make_item("health_potion"), Data.make_item("health_potion")], "stash": [Data.make_item("soldier_armor"), Data.make_item("golden_crown")]}
	for it in old.bag + old.stash:
		it.erase("affixes")
	var n := Account.normalize(old)
	ok.call("예전 세이브 변환", n.characters.size() == 1 and n.equipment.w1 != null and n.equipment.necklace != null and n.stash.size() >= 2)
	# 상자 격자
	var pk := Inv.pack_container(Data.roll_loot(8, 3.0))
	ok.call("상자 자동 배치 (%dx%d)" % [pk.gw, pk.gh], pk.items.size() == 8)
	return out


# 로비 화면 스크린샷: 일반 / 새 캐릭터 만들기 (godot -- --lobbyshots <폴더>)
func _lobbyshots(dir: String) -> void:
	await _wait(0.5)
	lobby.refresh()
	await _wait(0.3)
	await _shot(dir, "lobby_normal")
	lobby.creating = true
	lobby.create_cls = "druid"
	lobby.refresh()
	await _wait(0.3)
	await _shot(dir, "lobby_create")
	# 화면 오른쪽 끝 버튼이 화면 안에 있는지
	var vp := get_viewport().get_visible_rect().size
	print("[lobbyshots] 화면 %s, 입장 버튼 %s, 탭 오른쪽 끝 %.0f" % [vp, lobby.start_btn.get_global_rect(), lobby.tab_btns["records"].get_global_rect().end.x])
	get_tree().quit()


# 인벤토리 화면 스크린샷 (godot -- --invshots <폴더>)
func _invshots(dir: String) -> void:
	await _wait(0.5)
	var d: Dictionary = SaveData.data
	# 보여 주기용 아이템
	for b in [["knight_armor", 3], ["the_17th_key", 4], ["knight_bascinet", 2], ["ruby_ring", 3], ["golden_crown", 1], ["soldier_gauntlets", 2], ["soldier_chausses", 2]]:
		Inv.add_auto(d.stash, Inv.STASH, Data.make_item(b[0], b[1]))
	lobby.tab = "stash"
	lobby.refresh()
	await _wait(0.3)
	await _shot(dir, "inv_1_lobby")
	# 전설 무기 툴팁
	var leg = null
	for it in d.stash:
		if it.base == "the_17th_key":
			leg = it
	UI.show_tip(UI.item_tip(leg, "드래그: 이동 (R 회전) · 우클릭: 장착"))
	UI.tooltip.position = Vector2(820, 160)
	await _wait(0.2)
	await _shot(dir, "inv_2_tooltip")
	UI.hide_tip()
	# 드래그 중 (가방 위에서 미리 보기)
	var plate = null
	for it in d.stash:
		if it.base == "knight_armor":
			plate = it
	InvDrag.begin(plate, "stash", null, Vector2(0.5, 0.5), 34.0)
	Input.warp_mouse(lobby.bag_view.global_position + Vector2(150, 40))
	await _wait(0.3)
	await _shot(dir, "inv_3_drag")
	InvDrag.inst.cancel()
	# 던전: 인벤토리 + 상자
	start_raid()
	game.force_act = true
	await _wait(1.0)
	var c = game.chests[0]
	game.player.invuln = 999.0
	game.player.pos = game.dungeon.resolve_circle(c.pos + Vector3(1.2, 0, 0), game.player.radius)
	game.player.yaw = Actor.yaw_to(c.pos.x - game.player.pos.x, c.pos.z - game.player.pos.z)
	game.open_chest(c, game.player)
	game.open_container_for(game.player, c)
	await _wait(0.4)
	await _shot(dir, "inv_4_raid")
	get_tree().quit()
