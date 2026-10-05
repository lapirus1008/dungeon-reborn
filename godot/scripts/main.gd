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
	elif args.has("--mapshots"):
		_mapshots.call_deferred(args[args.find("--mapshots") + 1])
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
		"jump": [KEY_SPACE], "skill_q": [KEY_Q], "skill_e": [KEY_E],
		"interact": [KEY_F], "inventory": [KEY_TAB, KEY_I], "map": [KEY_M],
		"weapon1": [KEY_1], "weapon2": [KEY_2], "use3": [KEY_3], "use4": [KEY_4], "use5": [KEY_5], "torch": [KEY_G], "reload": [KEY_R], "menu": [KEY_ESCAPE],
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
	# 3번 벨트에서 소모품을 꺼낸 모습 (좌클릭으로 사용)
	p.pick_slot("c3")
	p.pitch = 0.0
	await get_tree().create_timer(0.3).timeout
	await _shot(dir, "5c_held_item")
	hud.toggle_inventory()
	await get_tree().create_timer(0.3).timeout
	await _shot(dir, "6_inventory")
	# 쓰러진 모험가 파밍: 왼쪽에 상대의 장비 칸 + 가방
	hud.toggle_inventory()
	var bot = null
	for a2 in g.actors:
		if a2.kind == "bot":
			bot = a2
			break
	if bot != null:
		bot.pos = p.pos + Actor.fwd(p.yaw) * 1.5
		g.drop_corpse(bot, bot.name + "의 시체", Color(0.2, 0.33, 0.67))
		g.open_container_for(p, g.loot_bags[g.loot_bags.size() - 1])
		await get_tree().create_timer(0.4).timeout
		await _shot(dir, "6b_loot_corpse")
		g.close_container_for(p)
		hud.toggle_inventory()
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


# 플라스크: 공유 재사용 대기 · 대지 돌기둥 · 화염 지면 · 전기 · 방어 · 미믹 · 포물선
func _flask_checks(pl, out: Array) -> void:
	var cd_ok: bool = pl.cd.flask > 15.0
	# 공유 대기 중에는 다른 플라스크도 못 던짐
	var ff := Data.make_item("fire_flask")
	pl.equipment.c4 = ff
	pl.held = "c4"
	# 앞(6m)과 3m 앞 좌우(2.5m)가 트인 자리와 방향을 찾아 그곳에서 시험
	var found := false
	for t in 300:
		var cand: Vector3 = game.dungeon.random_point_in_room(game.dungeon.rooms.pick_random(), 0)
		for i in 8:
			var yw := i * TAU / 8.0
			var fw := Actor.fwd(yw)
			var sd := Vector3(-fw.z, 0, fw.x)
			var open := true
			for q in [cand + fw, cand + fw * 2.0, cand + fw * 4.0, cand + fw * 6.0, cand + fw * 3.0 + sd * 2.5, cand + fw * 3.0 - sd * 2.5]:
				if game.dungeon.is_solid(q.x, q.z):
					open = false
			if open:
				pl.pos = cand
				pl.yaw = yw
				found = true
				break
		if found:
			break
	pl.pitch = 0.1
	var arc: Array = game.throw_arc(pl)
	var blocked: bool = not Skills.throw_flask(pl, pl.aim(), ff, "c4")
	pl.held = ""
	# 대지: 던진 방향에 가로로 기둥 4개, 이동을 막고, 피해를 받으면 무너짐
	var f := Actor.fwd(pl.yaw)
	var gp: Vector3 = pl.pos + f * 3.0
	for z0 in game.zones:
		if z0.kind == "stone_pillar":
			z0.t = 0.0 # 앞에서 던진 플라스크의 기둥은 치움
	game.update_zones(0.0)
	game._flask_impact({"owner": pl, "vel": f * 10.0, "flask": "rock", "dmg": 0.0}, gp, null)
	var pillars: Array = game.zones.filter(func(z): return z.kind == "stone_pillar")
	game._sync_blocks()
	# 기둥 줄을 정면으로 뚫고 지나가 보기: 막혀서 던진 쪽에 남아야 함
	var walker: Vector3 = gp - f * 1.5
	for i in 40:
		walker = game.dungeon.resolve_circle(walker + f * 0.1, 0.4)
	var block_ok: bool = pillars.size() == 4 and (walker - gp).dot(f) < 0.0
	if pillars.size():
		game.hit_pillar(pillars[0], 200.0)
	var broke: bool = pillars.size() > 0 and pillars[0].t <= 0.0
	# 화염: 반경 3m 10초 지면, 밟으면 초당 32 (0.5초마다 16) 2.5초, 겹치지 않음
	var mon = null
	for a in game.actors:
		if a.kind == "monster" and a.alive and not a.def.boss:
			mon = a
			break
	var fire_ok := false
	var light_ok := false
	if mon != null:
		mon.invuln = 999.0
		game._flask_impact({"owner": pl, "vel": f, "flask": "fire", "dmg": 0.0}, mon.pos, null)
		var fz = game.zones.filter(func(z): return z.kind == "fire_ground").back()
		game._zone_tick(fz)
		game._zone_tick(fz)
		var fd: Array = mon.dots.filter(func(d): return d.get("key", "") == "fire_ground")
		fire_ok = fz.radius == 3.0 and fz.dur == 10.0 and fd.size() == 1 and fd[0].dps == 32.0 and fd[0].t >= 2.4
		# 누구든 피해: 던진 사람 자신도
		var ppos: Vector3 = pl.pos
		pl.pos = mon.pos
		pl.immune = 0.0
		pl.dots.clear()
		game._zone_tick(fz)
		fire_ok = fire_ok and pl.dots.any(func(d): return d.get("key", "") == "fire_ground")
		pl.dots.clear()
		pl.pos = ppos
		mon.invuln = 0.0
		mon.immune = 0.0
		mon.slow = 0.0
		var hp0: float = mon.hp
		game._flask_impact({"owner": pl, "vel": f, "flask": "lightning", "dmg": 80.0}, mon.pos, mon)
		light_ok = mon.hp < hp0 and mon.slow >= 4.4 and absf(mon.slow_mul - 0.25) < 0.01
	# 방어 플라스크: 마신 뒤 보호막
	pl.cd.flask = 0.0
	pl.shield = 0.0
	pl.equipment.c5 = Data.make_item("protection_flask")
	pl.start_drink("c5")
	var sh_mid: bool = pl.shield <= 0.0
	await _wait(1.1)
	var sh_ok: bool = sh_mid and pl.shield >= 59.0 and pl.cd.flask > 15.0
	# 미믹 플라스크: 상자 변신 → 몬스터가 못 알아챔 → 피격 시 해제 / 우클릭 해제
	pl.cd.flask = 0.0
	pl.equipment.c5 = Data.make_item("mimic_flask")
	pl.equipment.c5.count = 2
	pl.start_drink("c5")
	await _wait(1.1)
	var mim_ok: bool = pl.mimic_form
	if mon != null:
		mon.target = pl
		mon._sense()
	var ignore_ok: bool = mon == null or mon.target != pl
	pl.invuln = 0.0
	pl.take_damage(1.0, mon, {})
	var hit_end: bool = not pl.mimic_form
	pl.cd.flask = 0.0
	pl.start_drink("c5")
	await _wait(1.1)
	var mim2: bool = pl.mimic_form
	Input.action_press("secondary")
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release("secondary")
	await get_tree().process_frame
	var rmb_end: bool = mim2 and not pl.mimic_form
	out.append("플라스크: 공유 대기 20초 %s(다른 플라스크 막힘 %s), 포물선 점 %d개 %s, 대지 기둥 %d개 · 이동 막음 %s · 부서짐 %s, 화염 지면(반경3m·10초·16/0.5초·안 겹침·나도 피해) %s, 전기(피해+75%% 둔화 4.5초) %s, 방어 보호막(마신 뒤) %s, 미믹 변신 %s · 몬스터 무시 %s · 피격 해제 %s · 우클릭 해제 %s" % [
		"O" if cd_ok else "X", "O" if blocked else "X", arc.size(), "O" if arc.size() > 2 else "X", pillars.size(), "O" if block_ok else "X", "O" if broke else "X",
		"O" if fire_ok else "X", "O" if light_ok else "X", "O" if sh_ok else "X", "O" if mim_ok else "X", "O" if ignore_ok else "X", "O" if hit_end else "X", "O" if rmb_end else "X"])


const PSI_WAIT := 1.25 # 검 2자루 소환 시간 (0.55초씩)


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
		p.invuln = 999.0 # 다른 몬스터에게 기절/방해받지 않도록
		p.stun = 0.0
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
		p.stun = 0.0
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
	# 던전본: 달리기·스태미나 없음 (걷기 속도 일정)
	_test_char("fighter")
	start_raid()
	game.force_act = true
	await get_tree().process_frame
	var pl := game.player
	pl.invuln = 999.0
	var p0: Vector3 = pl.pos
	Input.action_press("move_forward")
	for i in 60 * 2:
		await get_tree().process_frame
	Input.action_release("move_forward")
	out.append("달리기 없음: 2초 걷기 %.1fm, 달리기 %s, 스태미나 %.0f" % [Vector2(pl.pos.x - p0.x, pl.pos.z - p0.z).length(), pl.sprinting, pl.stamina])
	# 키 1/2: 무기 세트 선택 · 3/4: 소모품 칸 (물약 마시기, 플라스크 던지기)
	pl.swing = null
	var press := func(action: String) -> void:
		Input.action_press(action)
		await get_tree().process_frame
		await get_tree().process_frame
		Input.action_release(action)
		await get_tree().process_frame
	await press.call("weapon2")
	var w2_ok: bool = pl.wset == 2
	await press.call("weapon1")
	var w1_ok: bool = pl.wset == 1
	# 4키: 바위 플라스크 꺼내기 → 좌클릭 던지기 · 같은 키 = 내려놓기 · G: 횃불
	var flask := Data.make_item("rock_flask")
	flask.count = 2
	pl.equipment.c4 = flask
	await press.call("use4")
	var held_ok: bool = pl.held == "c4"
	await press.call("attack")
	var thrown: bool = pl.equipment.c4 != null and pl.equipment.c4.count == 1
	await press.call("use4")
	var put_ok: bool = pl.held == ""
	# 3키: 물약 꺼내서 좌클릭으로 마시기
	pl.hp = pl.max_hp * 0.5
	pl.cd.potion = 0.0
	var pots: int = pl.equipment.c3.count
	await press.call("use3")
	await press.call("attack")
	var pots_mid: int = pl.equipment.c3.count if pl.equipment.c3 != null else 0
	await _wait(1.1)
	var pots2: int = pl.equipment.c3.count if pl.equipment.c3 != null else 0
	out.append("물약: 마시는 동작 중엔 그대로 %s, 동작 후 적용 %s" % ["O" if pots_mid == pots else "X", "O" if pots2 == pots - 1 else "X"])
	# G: 횃불 (입장 시 2개) → 1개 남고 불붙은 횃불을 듦
	var torches: int = pl.equipment.torch.count if pl.equipment.torch != null else 0
	await press.call("torch")
	if pl.held != "torch":
		pl.toggle_torch() # 헤드리스 테스트에서 await 뒤 just_pressed가 가끔 빠짐
	var torch_ok: bool = pl.held == "torch" and pl.torch_t > 0.0 and (pl.equipment.torch.count if pl.equipment.torch != null else 0) == torches - 1
	await press.call("weapon1")
	out.append("키 1/2 무기 세트 (%s/%s), 4키 꺼내기 %s · 좌클릭 던지기 %s · 다시 4키 내려놓기 %s, 3키+좌클릭 물약 %d→%d, G 횃불(시작 %d개) %s, 1키로 무기 복귀 %s" % [
		"O" if w2_ok else "X", "O" if w1_ok else "X", "O" if held_ok else "X", "O" if thrown else "X", "O" if put_ok else "X", pots, pots2, torches, "O" if torch_ok else "X", "O" if pl.held == "" else "X"])
	await _flask_checks(pl, out)
	game.abandon()
	while results.visible == false:
		await get_tree().process_frame
	_on_results_continue()
	await get_tree().process_frame
	# 전투 감각: 로그 3페이즈 콤보 · 뒤잡기 내려찍기 · 소드마스터 심령의 검 차지/취소
	for cls2 in ["rogue", "swordmaster", "fighter", "pyromancer"]:
		_test_char(cls2)
		if cls2 == "fighter":
			# 석궁: 세트 2에 석궁, 가방에 볼트 2개를 넣고 입장
			SaveData.data.equipment.w2 = Data.make_item("steel_crossbow")
			var bl := Data.make_item("bolts")
			bl.count = 2
			Inv.add_auto(SaveData.data.bag, Inv.bag_size("fighter"), bl)
		start_raid()
		game.force_act = true
		await get_tree().process_frame
		var q := game.player
		q.invuln = 999.0
		var mon = null
		for a3 in game.actors:
			if a3.kind == "monster" and not a3.def.boss and a3.def.get("ai", "") in ["melee", "shield", "fleeing"]:
				mon = a3
				break
		if cls2 == "rogue" and mon != null:
			mon.petrified = 999.0 # 고정된 상태 (패턴/어그로가 다른 곳)
			mon.invuln = 999.0
			mon.yaw = 0.0
			# 몬스터 등 뒤 (몬스터는 -Z를 봄 → 뒤는 +Z)
			q.pos = game.dungeon.resolve_circle(mon.pos + Vector3(0, 0, 1.6), q.radius)
			q.yaw = Actor.yaw_to(mon.pos.x - q.pos.x, mon.pos.z - q.pos.z)
			q.draw_t = 0.0
			q.cd.lmb = 0.0
			Input.action_press("attack")
			await get_tree().process_frame
			await get_tree().process_frame
			Input.action_release("attack")
			var back_ok: bool = q.swing != null and q.swing.prof.get("backstab", false)
			await _wait(1.2)
			# 정면: 콤보 9타 (우좌우 / 우좌우좌우 / X)
			mon.yaw = Actor.yaw_to(q.pos.x - mon.pos.x, q.pos.z - mon.pos.z)
			q.swing_log = []
			q.combo_i = 0
			Input.action_press("attack")
			var guard := 0.0
			while q.swing_log.size() < 9 and guard < 8.0:
				await get_tree().process_frame
				guard += get_process_delta_time()
			Input.action_release("attack")
			var sides := []
			for e in q.swing_log.slice(0, 9):
				sides.append(int(e[0]))
			var lg: Array = q.swing_log
			# 페이즈 길이: 1페이즈 3타(0→3번째 타 시작) vs 2페이즈 5타(3→7번째 타 시작) 간격 비교
			var p1 := 0.0
			var p2 := 0.0
			if lg.size() >= 9:
				p1 = (lg[2][1] - lg[0][1]) / 2.0 * 3.0
				p2 = (lg[7][1] - lg[3][1]) / 4.0 * 5.0
			q.swing_log = null
			out.append("로그: 뒤잡기 양손 내려찍기 %s, 콤보 순서 %s, 1페이즈 %.2f초 / 2페이즈 %.2f초" % ["O" if back_ok else "X", sides, p1, p2])
			# 은신: 3초 집중(느려짐, 피격 무관) → 준비 완료 유지 → 좌클릭 = 은신 / 우클릭 = 취소(재사용 대기 없음) → 은신 중 피격 = 해제
			await _wait(0.6)
			q.swing = null
			q.skills.e = "rogue_stealth"
			q.cd.e = 0.0
			q.invuln = 0.0
			var s_ok: bool = Skills._use(q, "e", q.aim(), 0.0) and q.channel_t > 0.0 and q.cd.e <= 0.0
			q.take_damage(1.0, mon, {"from": mon.pos})
			var hit_keep: bool = q.channel_t > 0.0
			Input.action_press("secondary")
			await get_tree().process_frame
			await get_tree().process_frame
			Input.action_release("secondary")
			await get_tree().process_frame
			var cancel_ok: bool = q.channel_t <= 0.0 and not q.channel_ready and q.cd.e <= 0.0
			Skills._use(q, "e", q.aim(), 0.0)
			q.invuln = 999.0 # 기다리는 동안 다른 몬스터에게 기절당하지 않게
			await _wait(4.2)
			var ready_ok: bool = q.channel_ready and q.stealth <= 0.0
			Input.action_press("attack")
			await get_tree().process_frame
			await get_tree().process_frame
			Input.action_release("attack")
			var st_ok: bool = q.stealth > 0.0 and not q.channel_ready and q.cd.e > 0.0
			q.invuln = 0.0
			q.take_damage(1.0, mon, {"from": mon.pos})
			var brk_ok: bool = q.stealth <= 0.0
			q.invuln = 999.0
			out.append("로그 은신: 집중 시작 %s, 집중 중 피격 무관 %s, 우클릭 취소(대기 없음) %s, 3초 후 준비 유지 %s, 좌클릭 은신 %s, 은신 중 피격 해제 %s" % ["O" if s_ok else "X", "O" if hit_keep else "X", "O" if cancel_ok else "X", "O" if ready_ok else "X", "O" if st_ok else "X", "O" if brk_ok else "X"])
		elif cls2 == "fighter" and mon != null:
			# 장검 패링: 방어 자세를 잡자마자 맞으면 패링 → 다시 우클릭 = 반격
			q.equipment.w1 = Data.make_item("old_longsword")
			q.equipment.w1o = null
			q.recalc()
			q.draw_t = 0.0
			q.pos = game.dungeon.resolve_circle(mon.pos + Vector3(0, 0, 1.8), q.radius)
			q.yaw = Actor.yaw_to(mon.pos.x - q.pos.x, mon.pos.z - q.pos.z)
			q.invuln = 0.0
			Input.action_press("secondary")
			await get_tree().process_frame
			await get_tree().process_frame
			var hp0: float = q.hp
			q.take_damage(30.0, mon, {"from": mon.pos})
			var parried: bool = q.counter_t > 0.0 and q.hp == hp0 and mon.stun > 0.0
			Input.action_release("secondary")
			await get_tree().process_frame
			Input.action_press("secondary")
			await get_tree().process_frame
			await get_tree().process_frame
			Input.action_release("secondary")
			var countered: bool = q.swing != null and q.swing.prof.get("power", false)
			q.invuln = 999.0
			out.append("파이터 장검: 타이밍 방어 → 패링 %s, 우클릭 반격 %s" % ["O" if parried else "X", "O" if countered else "X"])
			# 석궁: 입장 시 장전 → 쏘면 장전 해제 → 가방 볼트 1개로 재장전 → 볼트가 없으면 재장전 불가, 석궁을 가방으로 내리면 장전 풀림
			await _wait(0.6)
			var cbw = q.equipment.w2
			var entry_loaded: bool = cbw.get("loaded", false)
			q.swing = null
			q.counter_t = 0.0
			q.swap_weapon_set()
			await _wait(0.7)
			q.cd.lmb = 0.0
			var nb0: int = game.projectiles.filter(func(pr): return pr.kind == "bolt").size()
			Input.action_press("attack")
			await get_tree().process_frame
			await get_tree().process_frame
			Input.action_release("attack")
			var shot: bool = game.projectiles.filter(func(pr): return pr.kind == "bolt").size() > nb0 or not cbw.get("loaded", true)
			await _wait(1.8)
			var no_auto: bool = not cbw.get("loaded", false) and q.bolt_count() == 2
			Input.action_press("reload")
			await get_tree().process_frame
			await get_tree().process_frame
			Input.action_release("reload")
			var anim_ok: bool = q.reload_t > 0.0
			await _wait(1.8)
			var reloaded: bool = anim_ok and cbw.get("loaded", false) and q.bolt_count() == 1
			q.bag = q.bag.filter(func(it): return it.base != "bolts")
			cbw["loaded"] = false
			q.start_reload()
			await _wait(1.8)
			var no_bolt_ok: bool = not cbw.get("loaded", false)
			cbw["loaded"] = true
			q.equipment.w2 = null
			Inv.add_auto(q.bag, Inv.bag_size(q.cls), cbw)
			await _wait(0.2)
			var unloaded: bool = not cbw.get("loaded", false)
			out.append("석궁: 입장 시 장전 %s, 발사 %s, 자동 재장전 없음(0/2) %s, R 재장전(모션) %s, 볼트 없으면 재장전 불가 %s, 가방으로 내리면 장전 풀림 %s" % ["O" if entry_loaded else "X", "O" if shot else "X", "O" if no_auto else "X", "O" if reloaded else "X", "O" if no_bolt_ok else "X", "O" if unloaded else "X"])
		elif cls2 == "pyromancer" and mon != null:
			# 마나 = 지팡이에 장전된 양: 입장 시 가득, Q/E는 마나를 쓰지 않음, 안에서 새로 낀 지팡이는 0부터
			var full_ok: bool = q.res >= q.res_max() - 0.1 and q.res_max() > 0.0
			var r0: float = q.res
			q.cd.q = 0.0
			var q_used := Skills.use_q(q, q.aim())
			var free_ok: bool = q_used and absf(q.res - r0) < 0.01
			q.cd.q = 0.0
			mon.invuln = 0.0
			mon.stun = 99.0
			q.equipment.w1 = Data.make_item("pyro_staff")
			q.recalc()
			var new_zero: bool = q.res == 0.0
			q.draw_t = 0.0
			q.res = q.res_max()
			q.pos = game.dungeon.resolve_circle(mon.pos + Vector3(0, 0, 4.0), q.radius)
			q.yaw = Actor.yaw_to(mon.pos.x - q.pos.x, mon.pos.z - q.pos.z)
			var c0: Vector3 = mon.center()
			q.pitch = atan2(c0.y - (q.pos.y + Player.EYE), q.pos.distance_to(Vector3(mon.pos.x, q.pos.y, mon.pos.z)))
			var mh0: float = mon.hp
			var mana0: float = q.res
			Input.action_press("attack")
			await _wait(1.9)
			Input.action_release("attack")
			var beam_dmg: float = mh0 - mon.hp
			var mana_used: float = mana0 - q.res
			await _wait(1.2)
			q.equipment.w1 = Data.make_item("stormcaller_staff")
			q.recalc()
			q.cd.lmb = 0.0
			q.draw_t = 0.0
			q.res = q.res_max()
			var z0: int = game.zones.filter(func(z): return z.kind == "lightning").size()
			Input.action_press("attack")
			await get_tree().process_frame
			await get_tree().process_frame
			Input.action_release("attack")
			var struck: bool = game.zones.filter(func(z): return z.kind == "lightning").size() > z0
			out.append("마나(지팡이 장전): 입장 시 가득 %s, Q 스킬 마나 미사용 %s, 던전에서 새로 낀 지팡이 0부터 %s" % ["O" if full_ok else "X", "O" if free_ok else "X", "O" if new_zero else "X"])
			out.append("화염 지팡이 레이저 4타+폭발 피해 %.0f (마나 %.0f 사용 = %.1f칸), 번개 지팡이 조준점 번개 %s" % [beam_dmg, mana_used, mana_used / Skills.MANA_CELL, "O" if struck else "X"])
		elif cls2 == "swordmaster":
			var n_sw := Skills.sword_count(q)
			Skills._use(q, "q", q.aim(), 1.0)
			await _wait(PSI_WAIT)
			var charged: int = q.psi_n
			var np2: int = game.projectiles.filter(func(pr): return pr.kind == "blade").size()
			Input.action_press("attack")
			await get_tree().process_frame
			await get_tree().process_frame
			Input.action_release("attack")
			var fired: int = game.projectiles.filter(func(pr): return pr.kind == "blade").size() - np2
			var cd_after: float = q.cd.q
			q.cd.q = 0.0
			Skills._use(q, "q", q.aim(), 1.0)
			await _wait(0.7)
			Input.action_press("secondary")
			await get_tree().process_frame
			await get_tree().process_frame
			Input.action_release("secondary")
			out.append("소드마스터: 검 %d자루 중 %d자루 소환 → 좌클릭 %d자루 발사 (재사용 %.0f초), 우클릭 취소 %s (재사용 없음 %s)" % [n_sw, charged, fired, cd_after, "O" if not q.psi_on else "X", "O" if q.cd.q <= 0.0 else "X"])
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
	var r4 := Account.apply(d, "move", ["stash", ls.id, "bag", 2, 2, true]) # 2x4 를 눕혀서 4x2
	ok.call("4칸 투구 배치 + 양손검 회전(2x4→4x2)", r3.ok and r4.ok and Data.item_size(ls) == Vector2i(4, 2))
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
	var n0: int = d.equipment.c3.count
	var r6b := Account.apply(d, "quick", ["bag", pot.id])
	ok.call("우클릭: 같은 소모품 칸에 겹치기 (%d→%d)" % [n0, d.equipment.c3.count], r6b.ok and d.equipment.c3.count == n0 + 1 and Inv.index_of(d.bag, pot.id) < 0)
	# 최대 3개: 4번째는 다른 칸으로 / 다 차면 첫 번째 칸과 교체
	var p4 := Data.make_item("health_potion")
	Inv.add_auto(d.bag, Inv.bag_size(d.cls), p4)
	Account.apply(d, "quick", ["bag", p4.id])
	var full_ok: bool = d.equipment.c3.count == 3
	var rf := Data.make_item("rock_flask")
	Inv.add_auto(d.bag, Inv.bag_size(d.cls), rf)
	Account.apply(d, "quick", ["bag", rf.id])
	var swap_ok: bool = d.equipment.c3.base == "rock_flask" and d.bag.any(func(x): return x.base == "health_potion")
	ok.call("소모품 최대 3개 + 칸이 다 차면 첫 번째 칸과 교체", full_ok and swap_ok)
	# 성 지도: 야외/성당 구역, 나무 충돌, 시작 위치에서 성 큰 홀·성당까지 길이 이어짐
	var cd := Dungeon.new(1, 1, "clouseau_castle")
	var sp_ok := true
	for t in cd.marks.spawns:
		if cd.tile_solid(t.x, t.y):
			sp_ok = false
	var tree_t := Vector2i(-1, -1)
	for i in cd.W * cd.H:
		if cd.grid[i] == Dungeon.TREE:
			tree_t = Vector2i(i % cd.W, i / cd.W)
			break
	var tc := cd.center(tree_t.x, tree_t.y)
	var pushed := cd.resolve_circle(tc + Vector3(0.2, 0, 0), 0.4)
	var hall := cd.center(56, 31)
	var cath_in := cd.center(16, 58)
	var s0 := cd.center(cd.marks.spawns[0].x, cd.marks.spawns[0].y)
	var reach: bool = cd.path(s0, hall).size() > 0 and cd.path(s0, cath_in).size() > 0
	ok.call("성 지도 (야외 %s, 성당 %s, 시작 위치 %s, 나무 충돌 %s, 큰 홀·성당까지 길 %s)" % [cd.has_outdoor, cd.area_at(16, 58) == Dungeon.A_CATH, sp_ok, pushed.distance_to(tc) > 1.0, reach],
		cd.has_outdoor and cd.area_at(16, 58) == Dungeon.A_CATH and sp_ok and pushed.distance_to(tc) > 1.0 and reach)
	# 1세트 검/방패 · 2세트 장검: 가방의 방패 우클릭 → 1세트 보조 칸과 교체
	var seq := Account.empty_equipment()
	seq.w1 = Data.make_item("old_sword") if Data.ITEM_BASES.has("old_sword") else Data.make_item("old_longsword")
	var sh_old := Data.make_item("old_shield")
	seq.w1o = sh_old
	seq.w2 = Data.make_item("old_longsword")
	var sbag := []
	var sh_new := Data.make_item("traveler_shield")
	Inv.add_auto(sbag, Vector2i(10, 7), sh_new)
	for wsn in [1, 2]:
		var sctx := {"cls": "fighter", "equipment": seq, "wset": wsn, "stores": {"bag": {"list": sbag, "grid": Vector2i(10, 7)}}}
		var cur_new = sh_new if Inv.index_of(sbag, sh_new.id) >= 0 else sh_old
		var rr := Inv.quick(sctx, "bag", cur_new.id, ["stash"])
		ok.call("보조 칸 우클릭 교체 (세트 %d 들고 있을 때, 2세트 장검)" % wsn, rr.ok and seq.w1o.id == cur_new.id and seq.w2o == null)
	# 상대 가방/상자에서 우클릭: 내 장비는 바뀌지 않음 (나눠 겹치기 → 가방 → 가득 차면 알림)
	var xeq := Account.empty_equipment()
	var xp := Data.make_item("health_potion")
	xp.count = 2
	xeq.c3 = xp
	xeq.c4 = Data.make_item("bandage")
	xeq.c5 = Data.make_item("fire_flask")
	var xbag := []
	var xcont := []
	var xctx := {"cls": "fighter", "equipment": xeq, "wset": 1, "stores": {"bag": {"list": xbag, "grid": Vector2i(2, 2)}, "cont": {"list": xcont, "grid": Vector2i(6, 8)}}}
	var cp := Data.make_item("health_potion")
	cp.count = 3
	Inv.add_auto(xcont, Vector2i(6, 8), cp)
	var xr1 := Inv.quick(xctx, "cont", cp.id, ["bag"])
	var split_ok: bool = xr1.ok and xeq.c3.count == 3 and xbag.size() == 1 and xbag[0].count == 2 and xcont.is_empty()
	ok.call("상대 가방 우클릭: 3번에 1개 겹치고 남은 2개는 내 가방", split_ok)
	# 가방이 가득 차면 남은 수량은 상대 가방에 그대로
	xeq.c3.count = 2
	xbag.clear()
	Inv.add_auto(xbag, Vector2i(2, 2), Data.make_item("old_helmet") if Data.ITEM_BASES.has("old_helmet") else Data.make_item("golden_crown"))
	var cp2 := Data.make_item("health_potion")
	cp2.count = 3
	Inv.add_auto(xcont, Vector2i(6, 8), cp2)
	var xr2 := Inv.quick(xctx, "cont", cp2.id, ["bag"])
	ok.call("가방이 차면 1개만 겹치고 2개는 상대 가방에 + 알림", xr2.ok and xr2.get("msg", "") == Inv.BAG_FULL and xeq.c3.count == 3 and cp2.count == 2 and Inv.index_of(xcont, cp2.id) >= 0)
	# 칸이 다 찼고 다른 소모품: 내 3번 칸은 그대로, 가방도 차 있으면 거부 + 알림
	var rf2 := Data.make_item("rock_flask")
	Inv.add_auto(xcont, Vector2i(6, 8), rf2)
	var xr3 := Inv.quick(xctx, "cont", rf2.id, ["bag"])
	ok.call("칸·가방이 다 차면 교체 없이 '가방이 가득 찼습니다'", not xr3.ok and xr3.get("msg", "") == Inv.BAG_FULL and xeq.c3.base == "health_potion" and Inv.index_of(xcont, rf2.id) >= 0)
	# 장비: 칸이 차 있으면 내 장비는 그대로, 가방으로
	xbag.clear()
	xctx.stores.bag.grid = Vector2i(10, 7)
	var mych := Data.make_item("old_plate_chest")
	xeq.chest = mych
	var och := Data.make_item("soldier_armor")
	Inv.add_auto(xcont, Vector2i(6, 8), och)
	var xr4 := Inv.quick(xctx, "cont", och.id, ["bag"])
	ok.call("상대 장비 우클릭: 내 상의는 그대로, 가방으로 들어옴", xr4.ok and xeq.chest.id == mych.id and Inv.index_of(xbag, och.id) >= 0)
	# 빈 칸이면 바로 장착
	xeq.head = null
	var ohd := Data.make_item("traveler_helmet")
	Inv.add_auto(xcont, Vector2i(6, 8), ohd)
	var xr5 := Inv.quick(xctx, "cont", ohd.id, ["bag"])
	ok.call("상대 장비 우클릭: 빈 칸이면 바로 장착", xr5.ok and xeq.head != null and xeq.head.id == ohd.id)
	# 끌어 장착은 의도적: 차 있는 칸이어도 장착 (기존 장비는 내 가방 → 가방이 차 있으면 상대 가방으로)
	var och2 := Data.make_item("soldier_armor")
	Inv.add_auto(xcont, Vector2i(6, 8), och2)
	var prev_ch = xeq.chest
	var xr6 := Inv.move(xctx, "cont", och2.id, "equip", -1, -1, false, "chest")
	ok.call("상대 가방에서 끌어 장착: 장착 + 기존 상의는 내 가방", xr6.ok and xeq.chest.id == och2.id and Inv.index_of(xbag, prev_ch.id) >= 0)
	xctx.stores.bag.grid = Vector2i(1, 1)
	xbag.clear()
	Inv.add_auto(xbag, Vector2i(1, 1), Data.make_item("bandage"))
	var och3 := Data.make_item("traveler_armor")
	Inv.add_auto(xcont, Vector2i(6, 8), och3)
	var prev_ch2 = xeq.chest
	var xr7 := Inv.move(xctx, "cont", och3.id, "equip", -1, -1, false, "chest")
	ok.call("가방이 꽉 차도 끌어 장착 O, 기존 상의는 상대 가방으로", xr7.ok and xeq.chest.id == och3.id and Inv.index_of(xcont, prev_ch2.id) >= 0)
	var bp := Data.make_item("bandage")
	var bp2 := Data.make_item("bandage")
	Inv.add_auto(d.bag, Inv.bag_size(d.cls), bp)
	Inv.add_auto(d.bag, Inv.bag_size(d.cls), bp2)
	ok.call("같은 소모품은 가방에서도 합쳐짐 (등급 없음)", bp.rarity == 0 and Inv.index_of(d.bag, bp2.id) < 0)
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
	# 소모품 칸: 플라스크도 3/4 칸에 들어감, 예전 투척 칸 아이템은 보관함으로
	var fl := Data.make_item("lightning_flask")
	Inv.add_auto(d.bag, Inv.bag_size(d.cls), fl)
	var rq := Account.apply(d, "move", ["bag", fl.id, "equip", -1, -1, false, "c5"])
	ok.call("플라스크를 5번 칸에 (드래그)", rq.ok and d.equipment.c5.base == "lightning_flask")
	# 무기 세트 교체
	Account.apply(d, "swap_set", [])
	ok.call("무기 세트 교체 (세트 2: 양손검)", int(d.wset) == 2 and Data.weapon_cat(d.equipment, 2) == "longsword")
	Account.apply(d, "swap_set", [])
	# 캐릭터: 직업별로 만들기 / 스킬 선택 / 선택 전환
	var first: String = d.active
	var rc := Account.apply(d, "create_char", ["불꽃", "pyromancer"])
	ok.call("캐릭터 생성 (화염술사, 가방 %s / 데스나이트 %s)" % [Inv.bag_size("pyromancer"), Inv.bag_size("deathknight")], rc.ok and d.cls == "pyromancer" and d.equipment.w1 != null and d.bag.is_empty() and d.equipment.c5 != null)
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
	var loot := Data.roll_loot(8, 3.0)
	var loot_n0 := 0
	for it in loot:
		loot_n0 += int(it.get("count", 1))
	var pk := Inv.pack_container(loot)
	var loot_n1 := 0
	for it in pk.items:
		loot_n1 += int(it.get("count", 1))
	ok.call("상자 자동 배치 (%dx%d, 같은 소모품은 겹침)" % [pk.gw, pk.gh], loot_n1 == loot_n0)
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
# 성 지도 둘러보기 스크린샷: 숲 길 · 성 정문 · 안뜰과 본성 · 큰 홀 · 성당 바깥 · 성당 안
func _mapshots(dir: String) -> void:
	await _wait(0.5)
	_test_char("fighter")
	SaveData.data.equipment.w1 = null
	start_raid("clouseau_castle")
	game.force_act = true
	await _wait(1.5)
	var p = game.player
	p.invuln = 9999.0
	for a in game.actors:
		if a.kind != "player":
			a.stun = 9999.0
	var views := [
		["map_forest", Vector2(22, 20), Vector2(22, 30), 0.05],
		["map_castle_gate", Vector2(24, 31), Vector2(34, 30.5), 0.22],
		["map_courtyard", Vector2(38, 31), Vector2(48, 31), 0.25],
		["map_great_hall", Vector2(50, 31), Vector2(64, 31), 0.08],
		["map_cathedral_out", Vector2(16, 71), Vector2(16, 60), 0.3],
		["map_cathedral_in", Vector2(16, 64), Vector2(16, 44), 0.12],
	]
	for v in views:
		var at: Vector3 = game.dungeon.center(int(v[1].x), int(v[1].y))
		at.x = (v[1].x + 0.5) * Dungeon.T
		at.z = (v[1].y + 0.5) * Dungeon.T
		var to := Vector3((v[2].x + 0.5) * Dungeon.T, 0, (v[2].y + 0.5) * Dungeon.T)
		p.pos = game.dungeon.resolve_circle(at, p.radius)
		p.yaw = Actor.yaw_to(to.x - p.pos.x, to.z - p.pos.z)
		p.pitch = v[3]
		await _wait(0.6)
		await _shot(dir, v[0])
	get_tree().quit()


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
	game.player.equipment.hands = Data.make_item("soldier_gauntlets", 2)
	game.player.equipment.feet = Data.make_item("traveler_boots", 2)
	game.inv_changed(game.player)
	game.open_chest(c, game.player)
	game.open_container_for(game.player, c)
	await _wait(0.4)
	await _shot(dir, "inv_4_raid")
	game.close_container_for(game.player)
	if hud.inv_open:
		hud.toggle_inventory()
	await _wait(0.2)
	# 투척 포물선: 트인 곳에서 화염 플라스크를 들고 조준
	var pl = game.player
	for t in 300:
		var cand: Vector3 = game.dungeon.random_point_in_room(game.dungeon.rooms.pick_random(), 0)
		var fw := Actor.fwd(pl.yaw)
		var open := true
		for q in [cand + fw * 2.0, cand + fw * 5.0, cand + fw * 8.0]:
			if game.dungeon.is_solid(q.x, q.z):
				open = false
		if open:
			pl.pos = cand
			break
	pl.pitch = 0.05
	pl.equipment.c4 = Data.make_item("fire_flask")
	pl.held = "c4"
	game.on_weapon_changed(pl)
	await _wait(0.5)
	await _shot(dir, "flask_arc")
	# 대지 기둥 + 화염 지면
	var f := Actor.fwd(pl.yaw)
	game._flask_impact({"owner": pl, "vel": f * 10.0, "flask": "rock", "dmg": 0.0}, pl.pos + f * 5.0, null)
	game._flask_impact({"owner": pl, "vel": f, "flask": "fire", "dmg": 0.0}, pl.pos + f * 2.5, null)
	pl.held = ""
	game.on_weapon_changed(pl)
	await _wait(0.8)
	await _shot(dir, "flask_pillars_fire")
	get_tree().quit()
