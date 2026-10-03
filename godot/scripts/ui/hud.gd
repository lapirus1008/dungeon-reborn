# 인게임 HUD: 체력/스태미나/마나, 스킬, 타이머, 미니맵, 킬피드, 인벤토리, 전리품 창, 메뉴
class_name Hud
extends CanvasLayer

signal menu_resume
signal menu_abandon
signal setting_changed(key: String, value)

var game
var container = null # 열려 있는 상자/전리품 Dictionary
var inv_open := false
var map_open := false
var menu_visible := false

var root: Control
var vignette: ColorRect
var vig_mat: ShaderMaterial
var hp_bar: ProgressBar
var hp_heal: ProgressBar
var shield_bar: ProgressBar
var hp_text: Label
var st_bar: ProgressBar
var mana_bar: ProgressBar
var res_label: Label
var status_label: Label
var timer_label: Label
var depth_label: Label
var portal_label: Label
var killfeed_box: VBoxContainer
var crosshair: Control
var hitmarker: Label
var target_box: VBoxContainer
var target_name: Label
var target_hp: ProgressBar
var prompt_label: Label
var channel_box: VBoxContainer
var channel_label: Label
var channel_bar: ProgressBar
var channel_t := 0.0
var announce_box: VBoxContainer
var announce_title: Label
var announce_sub: Label
var skills_row: HBoxContainer
var skill_boxes := {}
var shield_label: Label
var minimap: MiniMap
var bigmap: MiniMap
var bigmap_wrap: Control
var inv_panel: PanelContainer
var inv_equip: HBoxContainer
var inv_bag: GridContainer
var inv_title: Label
var inv_stats: Label
var cont_panel: PanelContainer
var cont_title: Label
var cont_grid: GridContainer
var menu: Control
var fps_label: Label
var hurt_v := 0.0
var sens_slider: HSlider
var quality_opt: OptionButton


func _ready() -> void:
	layer = 1
	root = Control.new()
	root.theme = UI.theme
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	vignette = ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig_mat = ShaderMaterial.new()
	vig_mat.shader = load("res://shaders/vignette.gdshader")
	vignette.material = vig_mat
	root.add_child(vignette)

	fps_label = UI.label("", 12, Color(0.6, 0.7, 0.6))
	fps_label.position = Vector2(8, 6)
	root.add_child(fps_label)

	# 상단 중앙: 층, 타이머, 포탈
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-150, 8)
	top.custom_minimum_size = Vector2(300, 0)
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	depth_label = _centered(UI.label("", 14, UI.GOLD))
	timer_label = _centered(UI.label("15:00", 34))
	portal_label = _centered(UI.label("", 14, Color("#8fd0ff")))
	top.add_child(depth_label)
	top.add_child(timer_label)
	top.add_child(portal_label)
	root.add_child(top)

	minimap = MiniMap.new()
	minimap.custom_minimum_size = Vector2(200, 200)
	minimap.size = Vector2(200, 200)
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(-212, 12)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(minimap)

	killfeed_box = VBoxContainer.new()
	killfeed_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	killfeed_box.position = Vector2(-420, 225)
	killfeed_box.custom_minimum_size = Vector2(408, 0)
	killfeed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(killfeed_box)

	# 조준선
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(func():
		var c := Color(1, 1, 1, 0.85)
		crosshair.draw_rect(Rect2(-1, -8, 2, 16), c)
		crosshair.draw_rect(Rect2(-8, -1, 16, 2), c))
	root.add_child(crosshair)
	hitmarker = UI.label("✕", 30)
	hitmarker.set_anchors_preset(Control.PRESET_CENTER)
	hitmarker.position = Vector2(-11, -22)
	hitmarker.modulate.a = 0.0
	root.add_child(hitmarker)

	target_box = VBoxContainer.new()
	target_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	target_box.position = Vector2(-110, 150)
	target_box.custom_minimum_size = Vector2(220, 0)
	target_name = _centered(UI.label("", 16))
	target_hp = _bar(Color(0.8, 0.2, 0.2), Vector2(220, 7))
	target_box.add_child(target_name)
	target_box.add_child(target_hp)
	target_box.visible = false
	root.add_child(target_box)

	prompt_label = _centered(UI.label("", 15))
	prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	prompt_label.position = Vector2(-250, 110)
	prompt_label.custom_minimum_size = Vector2(500, 0)
	prompt_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	prompt_label.add_theme_constant_override("shadow_outline_size", 6)
	root.add_child(prompt_label)

	channel_box = VBoxContainer.new()
	channel_box.set_anchors_preset(Control.PRESET_CENTER)
	channel_box.position = Vector2(-140, 150)
	channel_box.custom_minimum_size = Vector2(280, 0)
	channel_label = _centered(UI.label("", 14))
	channel_bar = _bar(Color(0.29, 0.72, 1.0), Vector2(280, 9))
	channel_box.add_child(channel_label)
	channel_box.add_child(channel_bar)
	channel_box.visible = false
	root.add_child(channel_box)

	announce_box = VBoxContainer.new()
	announce_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	announce_box.position = Vector2(-400, 210)
	announce_box.custom_minimum_size = Vector2(800, 0)
	announce_title = _centered(UI.label("", 36, Color("#f0d8a0")))
	announce_sub = _centered(UI.label("", 16, Color("#d0c0a0")))
	for l in [announce_title, announce_sub]:
		l.add_theme_color_override("font_shadow_color", Color.BLACK)
		l.add_theme_constant_override("shadow_outline_size", 10)
	announce_box.add_child(announce_title)
	announce_box.add_child(announce_sub)
	announce_box.modulate.a = 0.0
	announce_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(announce_box)

	# 하단 왼쪽: 체력/스태미나/마나
	var bars := VBoxContainer.new()
	bars.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bars.position = Vector2(20, -140)
	bars.custom_minimum_size = Vector2(340, 0)
	bars.add_theme_constant_override("separation", 5)
	status_label = UI.label("", 13, Color(1.0, 0.75, 0.5))
	bars.add_child(status_label)
	shield_label = UI.label("", 14, Color(0.55, 0.8, 1.0))
	bars.add_child(shield_label)
	var hp_stack := Control.new()
	hp_stack.custom_minimum_size = Vector2(340, 24)
	hp_heal = _bar(Color(0.29, 0.54, 0.23), Vector2(340, 24))
	hp_bar = _bar(Color(0.8, 0.2, 0.15), Vector2(340, 24), true)
	shield_bar = _bar(Color(0.35, 0.65, 1.0, 0.85), Vector2(340, 24), true)
	hp_text = _centered(UI.label("", 14))
	hp_text.custom_minimum_size = Vector2(340, 24)
	hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_text.add_theme_color_override("font_shadow_color", Color.BLACK)
	hp_text.add_theme_constant_override("shadow_outline_size", 4)
	for n in [hp_heal, hp_bar, shield_bar, hp_text]:
		hp_stack.add_child(n)
	bars.add_child(hp_stack)
	st_bar = _bar(Color(0.85, 0.75, 0.31), Vector2(340, 10))
	mana_bar = _bar(Color(0.29, 0.48, 1.0), Vector2(340, 10))
	bars.add_child(st_bar)
	var res_stack := Control.new()
	res_stack.custom_minimum_size = Vector2(340, 14)
	mana_bar.custom_minimum_size = Vector2(340, 14)
	mana_bar.size = Vector2(340, 14)
	res_label = UI.label("", 11)
	res_label.custom_minimum_size = Vector2(340, 14)
	res_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	res_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	res_label.add_theme_constant_override("shadow_outline_size", 4)
	res_stack.add_child(mana_bar)
	res_stack.add_child(res_label)
	bars.add_child(res_stack)
	root.add_child(bars)

	skills_row = HBoxContainer.new()
	skills_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	skills_row.position = Vector2(-200, -80)
	skills_row.add_theme_constant_override("separation", 6)
	root.add_child(skills_row)

	_build_inventory()
	_build_container()
	_build_bigmap()
	_build_menu()


func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(color: Color, sz: Vector2, transparent_bg := false) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = sz
	b.size = sz
	b.show_percentage = false
	b.max_value = 1.0
	b.step = 0.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0) if transparent_bg else Color(0, 0, 0, 0.7)
	bg.border_color = Color(0, 0, 0, 0.9)
	bg.set_border_width_all(0 if transparent_bg else 1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _build_inventory() -> void:
	inv_panel = UI.panel_box(Vector2(480, 0))
	inv_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	inv_panel.position = Vector2(-720, -230)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	inv_panel.add_child(v)
	inv_title = UI.title("소지품")
	v.add_child(inv_title)
	inv_equip = HBoxContainer.new()
	inv_equip.add_theme_constant_override("separation", 10)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 16)
	m.add_child(inv_equip)
	v.add_child(m)
	inv_stats = UI.label("", 13, UI.MUTED)
	v.add_child(inv_stats)
	inv_bag = GridContainer.new()
	inv_bag.columns = 8
	inv_bag.add_theme_constant_override("h_separation", 5)
	inv_bag.add_theme_constant_override("v_separation", 5)
	v.add_child(inv_bag)
	v.add_child(UI.label("Tab / Esc 닫기 · 게임은 계속 진행 중입니다", 12, UI.MUTED))
	inv_panel.visible = false
	root.add_child(inv_panel)


func _build_container() -> void:
	cont_panel = UI.panel_box(Vector2(330, 0))
	cont_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	cont_panel.position = Vector2(40, -200)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	cont_panel.add_child(v)
	cont_title = UI.title("")
	v.add_child(cont_title)
	cont_grid = GridContainer.new()
	cont_grid.columns = 5
	cont_grid.add_theme_constant_override("h_separation", 5)
	cont_grid.add_theme_constant_override("v_separation", 5)
	v.add_child(cont_grid)
	v.add_child(UI.button("모두 가져가기", _take_all))
	v.add_child(UI.label("F / Tab 닫기", 12, UI.MUTED))
	cont_panel.visible = false
	root.add_child(cont_panel)


func _build_bigmap() -> void:
	bigmap_wrap = ColorRect.new()
	(bigmap_wrap as ColorRect).color = Color(0, 0, 0, 0.6)
	bigmap_wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bigmap_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	bigmap = MiniMap.new()
	bigmap.big = true
	bigmap.custom_minimum_size = Vector2(700, 700)
	bigmap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(bigmap)
	v.add_child(_centered(UI.label("M 닫기 · 파랑: 탈출 포탈 · 빨강: 심연 포탈 · 노랑: 상자", 13, UI.MUTED)))
	c.add_child(v)
	bigmap_wrap.add_child(c)
	bigmap_wrap.visible = false
	root.add_child(bigmap_wrap)


func _build_menu() -> void:
	menu = ColorRect.new()
	(menu as ColorRect).color = Color(0, 0, 0, 0.3)
	menu.theme = UI.theme
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(c)
	var p := UI.panel_box(Vector2(380, 0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	v.add_child(_centered(UI.title("메뉴")))
	v.add_child(_centered(UI.label("⚠ 게임은 계속 진행 중입니다", 15, Color("#ff8a6a"))))
	v.add_child(UI.button("돌아가기 (Esc)", func(): menu_resume.emit()))
	var sh := HBoxContainer.new()
	sh.add_child(UI.label("마우스 감도", 14, UI.MUTED))
	sens_slider = HSlider.new()
	sens_slider.min_value = 0.3
	sens_slider.max_value = 3.0
	sens_slider.step = 0.1
	sens_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sens_slider.value = SaveData.setting("sensitivity", 1.0)
	sens_slider.value_changed.connect(func(v2): setting_changed.emit("sensitivity", v2))
	sh.add_child(sens_slider)
	v.add_child(sh)
	var qh := HBoxContainer.new()
	qh.add_child(UI.label("그래픽 품질", 14, UI.MUTED))
	quality_opt = OptionButton.new()
	quality_opt.add_item("낮음 (빠름)")
	quality_opt.add_item("보통")
	quality_opt.add_item("높음 (선명)")
	quality_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quality_opt.selected = ["low", "mid", "high"].find(SaveData.setting("quality", "mid"))
	quality_opt.item_selected.connect(func(i): setting_changed.emit("quality", ["low", "mid", "high"][i]))
	qh.add_child(quality_opt)
	v.add_child(qh)
	v.add_child(UI.button("레이드 포기 (소지품 상실)", func(): menu_abandon.emit(), 13))
	c.add_child(p)
	menu.visible = false
	add_child(menu)


# ------------------------------------------------------------------ 상태
func start(g) -> void:
	game = g
	container = null
	inv_open = false
	map_open = false
	inv_panel.visible = false
	cont_panel.visible = false
	bigmap_wrap.visible = false
	for c in killfeed_box.get_children():
		c.queue_free()
	minimap.game = g
	bigmap.game = g
	on_level_changed()
	var cls: Dictionary = Data.CLASSES[g.player.cls]
	UI.clear(skills_row)
	skill_boxes.clear()
	for k in ["rmb", "q", "e", "p1", "p2"]:
		var box := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.03, 0.02, 0.85)
		sb.border_color = Color("#5a4a32")
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(4)
		box.add_theme_stylebox_override("panel", sb)
		box.custom_minimum_size = Vector2(74 if not k.begins_with("p") else 56, 58)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		var key_text: String = "우클릭" if k == "rmb" else (k.to_upper() if not k.begins_with("p") else k.substr(1))
		v.add_child(_centered(UI.label(key_text, 11, UI.GOLD)))
		var nm := _centered(UI.label("", 13))
		if k.begins_with("p"):
			nm.text = "🧪" if k == "p1" else "🩹"
		else:
			nm.text = Skills.skill_def(g.player, k).name
		v.add_child(nm)
		var cd_bar := _bar(Color(0, 0, 0, 0.0), Vector2(60, 4))
		v.add_child(cd_bar)
		box.add_child(v)
		box.tooltip_text = Skills.skill_def(g.player, k).desc if not k.begins_with("p") else ""
		skills_row.add_child(box)
		skill_boxes[k] = {"box": box, "style": sb, "name": nm, "cd": cd_bar}
	var rt: String = g.player.res_type()
	mana_bar.get_parent().visible = rt != ""
	if rt != "":
		(mana_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Data.RES_COLORS[rt]


func on_level_changed() -> void:
	pass


func is_panel_open() -> bool:
	return inv_open or container != null


func set_menu_visible(v: bool) -> void:
	menu_visible = v
	menu.visible = v


func toggle_inventory() -> void:
	if container != null:
		close_container()
		return
	inv_open = not inv_open
	inv_panel.visible = inv_open
	if inv_open:
		render_inventory()
	else:
		UI.hide_tip()


func toggle_map() -> void:
	map_open = not map_open
	bigmap_wrap.visible = map_open


func open_container(c: Dictionary) -> void:
	container = c
	cont_panel.visible = true
	inv_open = true
	inv_panel.visible = true
	refresh_panels()
	Sfx.play("chest")


func close_container(send := true) -> void:
	if container == null:
		return
	container = null
	if send and game != null:
		game.request_inv("close")
	cont_panel.visible = false
	inv_open = false
	inv_panel.visible = false
	UI.hide_tip()


func close_panels() -> void:
	close_container()
	inv_open = false
	inv_panel.visible = false
	UI.hide_tip()


func refresh_panels() -> void:
	if inv_open:
		render_inventory()
	if container != null:
		render_container()


func render_inventory() -> void:
	var p = game.player
	UI.clear(inv_equip)
	for slot in Data.GEAR_SLOTS:
		var it = p.equipment[slot]
		var sl: String = slot
		inv_equip.add_child(UI.slot(it, func(): _unequip(sl), Callable(), {"label": Data.SLOT_NAMES[slot], "size": 60.0, "tip": "클릭: 해제"}))
	UI.clear(inv_bag)
	for i in SaveData.BAG_SIZE:
		var it = p.bag[i] if i < p.bag.size() else null
		var idx := i
		var hint := "클릭: 사용/장착 · 우클릭: 상자에 넣기" if container != null else "클릭: 사용/장착 · 우클릭: 버리기"
		inv_bag.add_child(UI.slot(it, func(): _bag_click(idx), func(): _bag_drop(idx), {"tip": hint}))
	var items := []
	for s in Data.GEAR_SLOTS:
		if p.equipment[s] != null:
			items.append(p.equipment[s])
	items.append_array(p.bag)
	inv_title.text = "소지품  (가치 💰 %d)" % Data.items_value(items)
	var st: Dictionary = p.stats
	inv_stats.text = "❤ %d · 🛡 %d · ⚔ x%.2f · 👟 %d%%" % [p.max_hp, st.armor, st.dmg_mul, roundi(st.speed_mul * 100.0)]


# 인벤토리 조작은 서버(오프라인/호스트는 로컬 Game)가 처리
func _unequip(slot: String) -> void:
	if game.player.equipment[slot] != null:
		game.request_inv("unequip", [slot])


func _bag_click(i: int) -> void:
	if i < game.player.bag.size():
		game.request_inv("use", [i])


func _bag_drop(i: int) -> void:
	if i < game.player.bag.size():
		game.request_inv("drop", [i])


func render_container() -> void:
	var c: Dictionary = container
	cont_title.text = c.name
	UI.clear(cont_grid)
	for i in maxi(10, c.items.size()):
		var it = c.items[i] if i < c.items.size() else null
		var idx := i
		cont_grid.add_child(UI.slot(it, func(): _take(idx), Callable(), {"tip": "클릭: 가져가기"}))


func _take(i: int) -> void:
	if container == null or i >= container.items.size():
		return
	if game.player.bag.size() >= SaveData.BAG_SIZE:
		toast("가방이 가득 찼습니다")
		return
	game.request_inv("take", [i])


func _take_all() -> void:
	if container != null:
		game.request_inv("take_all")


# ------------------------------------------------------------------ 표시
func toast(text: String) -> void:
	UI.toast(text)


func prompt(text: String) -> void:
	if prompt_label.text != text:
		prompt_label.text = text
	prompt_label.visible = text != ""


func channel(text: String, k: float) -> void:
	channel_t = 0.1
	channel_label.text = text
	channel_bar.value = clampf(k, 0.0, 1.0)


func announce(title_text: String, sub: String = "") -> void:
	announce_title.text = title_text
	announce_sub.text = sub
	var tw := announce_box.create_tween()
	announce_box.modulate.a = 0.0
	tw.tween_property(announce_box, "modulate:a", 1.0, 0.4)
	tw.tween_interval(3.2)
	tw.tween_property(announce_box, "modulate:a", 0.0, 0.8)


func killfeed(text: String, mine := false, info := false) -> void:
	var l := UI.label(text, 14, Color("#ffd0b0") if mine else (Color("#bfe6ff") if info else UI.TEXT))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_outline_size", 5)
	killfeed_box.add_child(l)
	killfeed_box.move_child(l, 0)
	while killfeed_box.get_child_count() > 6:
		var last := killfeed_box.get_child(killfeed_box.get_child_count() - 1)
		killfeed_box.remove_child(last)
		last.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(8.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)


# 월드 공간 데미지 숫자 (Label3D)
func damage_number(p: Vector3, amount: float, color: Color, prefix := "") -> void:
	var l := Label3D.new()
	l.text = prefix + str(roundi(amount))
	l.font = UI.font
	l.font_size = 40
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 12
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.position = p + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
	game.world.add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 1.0, 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


func hit_marker(kill: bool) -> void:
	hitmarker.modulate = Color(1, 0.25, 0.2, 1) if kill else Color(1, 1, 1, 1)
	var tw := hitmarker.create_tween()
	tw.tween_property(hitmarker, "modulate:a", 0.0, 0.25)


func shake(v: float) -> void:
	if game.player != null:
		game.player.shake = maxf(game.player.shake, v)


func swing(side: float, bash: bool, dur: float) -> void:
	if game.player != null:
		game.player.client_swing(side, bash, dur)


func sfx(n: String) -> void:
	Sfx.play(n)


func hurt(frac: float) -> void:
	hurt_v = minf(1.0, hurt_v + 0.3 + frac * 2.0)


func update_hud(dt: float) -> void:
	var g = game
	var p = g.player
	hp_bar.value = p.hp / p.max_hp
	hp_heal.value = minf(p.max_hp, p.hp + p.heal) / p.max_hp
	shield_bar.value = p.shield / p.max_hp
	shield_bar.visible = p.shield > 0.0
	hp_text.text = "%d / %d" % [ceili(p.hp), roundi(p.max_hp)] + (" (+%d)" % ceili(p.shield) if p.shield > 0.0 else "")
	shield_label.text = ("🔷 보호막 %d · %.1f초" % [ceili(p.shield), maxf(0.0, p.shield_t)]) if p.shield > 0.0 else ""
	st_bar.value = p.stamina / 100.0
	# 스태미나 고갈 시 붉게 (30%까지 회복해야 다시 달리기 가능)
	(st_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color(0.6, 0.25, 0.2) if p.exhausted else Color(0.85, 0.75, 0.31)
	if p.res_type() != "":
		mana_bar.value = p.res / maxf(1.0, p.res_max())
		res_label.text = "%s %d / %d" % [Data.RES_NAMES[p.res_type()], roundi(p.res), roundi(p.res_max())]
	var sts := []
	if p.stun > 0.0:
		sts.append("기절")
	if p.root > 0.0:
		sts.append("속박")
	if p.slow > 0.0:
		sts.append("둔화")
	if p.dots.size():
		sts.append("중독")
	if p.channel_t > 0.0:
		sts.append("은신 집중 %.1f" % p.channel_t)
	if p.stealth > 0.0:
		sts.append("👁 은신 %.0f초" % p.stealth)
	if p.frozen > 0.0:
		sts.append("❄ 서리 장벽 %.1f" % p.frozen)
	if p.panther:
		sts.append("🐆 표범 형태")
	if p.dr > 0.0:
		sts.append("회오리 검")
	if p.immune > 0.0:
		sts.append("면역")
	if p.exhausted:
		sts.append("지침")
	status_label.text = " · ".join(sts)
	var tl := maxf(0.0, g.time_left)
	timer_label.text = "%d:%02d" % [int(tl / 60.0), int(tl) % 60]
	timer_label.add_theme_color_override("font_color", Color("#ff4a3a") if tl < 120.0 else UI.TEXT)
	depth_label.text = "심연 %d층" % g.depth if g.depth > 1 else "고대 지하묘지 1층"
	var ex: int = g.exit_portals().size()
	portal_label.text = "🌀 탈출 포탈 %d개 열림" % ex if ex > 0 else "🌀 포탈 대기 중"

	for k in ["rmb", "q", "e"]:
		var sbx: Dictionary = skill_boxes[k]
		var def := Skills.skill_def(p, k)
		if sbx.name.text != def.name:
			sbx.name.text = def.name
			sbx.box.tooltip_text = def.desc
		var mx: float = def.cd
		var c: float = p.cd[k]
		var cooling := mx > 0.0 and c > 0.0
		var cd_bar: ProgressBar = sbx.cd
		cd_bar.value = c / mx if cooling else 0.0
		(cd_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color(0.9, 0.7, 0.3, 0.9)
		var active := false
		match k:
			"rmb":
				active = p.blocking or p.parry > 0.0 or p.charge_t >= 0.0
			"q":
				active = p.panther or p.spin_t > 0.0
			"e":
				active = p.stealth > 0.0 or p.channel_t > 0.0 or p.dr > 0.0 or p.frozen > 0.0 or p.dash != null
		var st: StyleBoxFlat = sbx.style
		st.border_color = Color("#ffd060") if active else Color("#5a4a32")
		st.set_border_width_all(2 if active else 1)
		sbx.name.modulate = Color(0.5, 0.5, 0.5) if cooling else Color.WHITE
	var pots := 0
	var bands := 0
	for it in p.bag:
		if it.base == "health_potion":
			pots += 1
		elif it.base == "bandage":
			bands += 1
	skill_boxes.p1.name.text = "🧪 %d" % pots
	skill_boxes.p2.name.text = "🩹 %d" % bands

	var t = g.aimed_actor()
	if t != null:
		target_box.visible = true
		target_name.text = t.display_name()
		target_name.add_theme_color_override("font_color", Color("#ff7a5a") if t.kind == "bot" else (Color("#ff4040") if t.kind == "monster" and t.def.boss else Color("#dddddd")))
		target_hp.value = t.hp / t.max_hp
	else:
		target_box.visible = false

	if channel_t > 0.0:
		channel_t -= dt
	channel_box.visible = channel_t > 0.0
	var charge_k: float = minf(1.0, p.charge_t / 1.2) if p.charge_t >= 0.0 else -1.0
	crosshair.scale = Vector2.ONE * ((1.6 - charge_k * 0.6) if charge_k >= 0.0 else 1.0)
	crosshair.visible = not inv_open and not menu_visible

	var low_hp := 0.35 + sin(g.time * 6.0) * 0.1 if p.hp / p.max_hp < 0.3 else 0.0
	hurt_v = maxf(0.0, hurt_v - dt * 1.5)
	vig_mat.set_shader_parameter("hurt", minf(1.0, hurt_v + low_hp))
	vig_mat.set_shader_parameter("shield", 1.0 if p.shield > 0.0 else 0.0)
	vig_mat.set_shader_parameter("shield_hit", p.shield_hit_fx)
	vig_mat.set_shader_parameter("tint", p.shield_color)
	vig_mat.set_shader_parameter("frost", 1.0 if p.frozen > 0.0 else 0.0)
	vig_mat.set_shader_parameter("stealth", 1.0 if p.stealth > 0.0 or p.channel_t > 0.0 else 0.0)

	fps_label.text = "%d FPS" % Engine.get_frames_per_second()
