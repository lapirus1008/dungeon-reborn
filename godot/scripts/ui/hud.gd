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
var ammo_box: VBoxContainer
var ammo_label: Label
var ammo_hint: Label
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
var inv_panel: Control # 던전 인벤토리 전체 (대상 | 내 정보 | 내 장비·가방)
var inv_equip: EquipView
var inv_preview: CharPreview
var inv_name: Label
var inv_attrs: HBoxContainer
var inv_skills: HBoxContainer
var cont_equip: EquipView
var cont_scroll: ScrollContainer
var inv_bag: GridView
var inv_title: Label
var inv_stats: RichTextLabel
var cont_panel: Control
var cont_title: Label
var cont_grid: GridView
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
	# 하단 오른쪽: 석궁 장전/볼트 (장전 수 / 가방 볼트)
	ammo_box = VBoxContainer.new()
	ammo_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_box.position = Vector2(-190, -150)
	ammo_box.custom_minimum_size = Vector2(170, 0)
	ammo_box.visible = false
	ammo_label = UI.label("", 30)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_hint = UI.label("", 13, Color(1.0, 0.75, 0.5))
	ammo_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_box.add_child(ammo_label)
	ammo_box.add_child(ammo_hint)
	root.add_child(ammo_box)
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
	# 마나는 칸으로 표시 (1칸 = 화염 지팡이 레이저 4타 + 폭발 한 번)
	var cells := Control.new()
	cells.name = "Cells"
	cells.custom_minimum_size = Vector2(340, 14)
	cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cells.draw.connect(func():
		if game == null or game.player == null or game.player.res_type() != "mana":
			return
		var mx: float = game.player.res_max()
		var n := int(mx / Skills.MANA_CELL)
		for i in range(1, n + 1):
			var x := 340.0 * i * Skills.MANA_CELL / mx
			if x < 339.0:
				cells.draw_rect(Rect2(x - 1, 0, 2, 14), Color(0, 0, 0, 0.85)))
	res_stack.add_child(cells)
	res_stack.add_child(res_label)
	bars.add_child(res_stack)
	root.add_child(bars)

	skills_row = HBoxContainer.new()
	skills_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	skills_row.position = Vector2(-273, -80)
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


# 던전본 파밍 화면: 왼쪽 = 대상(상자/시체), 가운데 = 내 정보, 오른쪽 = 내 장비·가방
func _build_inventory() -> void:
	inv_panel = Control.new()
	inv_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inv_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inv_panel.visible = false
	root.add_child(inv_panel)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	row.offset_top = 40
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inv_panel.add_child(row)

	# 왼쪽: 대상
	cont_panel = UI.panel_box(Vector2(430, 690))
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	cont_panel.add_child(lv)
	cont_title = UI.title("")
	lv.add_child(cont_title)
	cont_equip = EquipView.new(32.0)
	cont_equip.store = "ceq"
	cont_equip.on_op = _inv_op
	cont_equip.hint = "드래그: 내 가방·장비칸으로 · 우클릭: 가져오기/장착"
	lv.add_child(cont_equip)
	cont_scroll = ScrollContainer.new()
	cont_scroll.custom_minimum_size = Vector2(Inv.CONT_W * 36 + 14, 300)
	cont_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cont_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cont_grid = GridView.new("cont", 36.0)
	cont_grid.on_op = _inv_op
	cont_grid.hint = "드래그: 가방이나 장비칸으로 · 우클릭: 가져오기/장착 · Shift+클릭: 가방으로"
	cont_scroll.add_child(cont_grid)
	lv.add_child(cont_scroll)
	lv.add_child(UI.button("모두 가져가기", _take_all))
	lv.add_child(UI.label("F / Tab 닫기", 12, UI.MUTED))
	cont_panel.visible = false
	row.add_child(cont_panel)

	# 가운데: 내 정보 (캐릭터 모습, 능력치, Q/E)
	var mid := UI.panel_box(Vector2(340, 690))
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	mid.add_child(mv)
	inv_preview = CharPreview.new(Vector2(320, 330))
	mv.add_child(inv_preview)
	inv_name = _centered(UI.label("", 16, UI.GOLD))
	mv.add_child(inv_name)
	inv_attrs = HBoxContainer.new()
	inv_attrs.alignment = BoxContainer.ALIGNMENT_CENTER
	inv_attrs.add_theme_constant_override("separation", 4)
	mv.add_child(inv_attrs)
	inv_skills = HBoxContainer.new()
	inv_skills.alignment = BoxContainer.ALIGNMENT_CENTER
	inv_skills.add_theme_constant_override("separation", 8)
	mv.add_child(inv_skills)
	var ss := ScrollContainer.new()
	ss.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ss.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inv_stats = RichTextLabel.new()
	inv_stats.bbcode_enabled = true
	inv_stats.fit_content = true
	inv_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ss.add_child(inv_stats)
	mv.add_child(ss)
	row.add_child(mid)

	# 오른쪽: 내 장비 + 가방
	var right := UI.panel_box(Vector2(420, 690))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	right.add_child(v)
	inv_title = UI.title("소지품")
	v.add_child(inv_title)
	inv_equip = EquipView.new(34.0)
	inv_equip.on_op = _inv_op
	inv_equip.drop_outside = true
	inv_equip.hint = "우클릭: 해제 · Shift+클릭: 바닥에 버리기 · 드래그: 옮기기"
	v.add_child(inv_equip)
	inv_bag = GridView.new("bag", 36.0)
	inv_bag.on_op = _inv_op
	inv_bag.drop_outside = true
	v.add_child(inv_bag)
	var hint := UI.label("드래그 이동 (R 회전) · 우클릭: 장착/해제 · Shift+클릭: 바닥에 버리기 · 1/2: 무기 세트 · 3/4/5: 소모품 꺼내기 → 좌클릭 사용 · G: 횃불 · Tab/Esc 닫기 (게임은 계속 진행)", 12, UI.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(380, 0)
	v.add_child(hint)
	row.add_child(right)


func _build_container() -> void:
	pass # _build_inventory 에서 함께 만듦


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
	v.add_child(_centered(UI.label("M 닫기 · 파랑: 탈출 포탈 · 빨강: 심연 포탈", 13, UI.MUTED)))
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
	for k in ["q", "e", "w1", "w2", "c3", "c4", "c5", "torch"]:
		var box := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.03, 0.02, 0.85)
		sb.border_color = Color("#5a4a32")
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(4)
		box.add_theme_stylebox_override("panel", sb)
		var small: bool = k != "rmb" and k != "q" and k != "e"
		box.custom_minimum_size = Vector2(56 if small else 84, 58)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		var key_text: String = {"rmb": "우클릭", "q": "Q", "e": "E", "w1": "1", "w2": "2", "c3": "3", "c4": "4", "c5": "5", "torch": "G 횃불"}[k]
		v.add_child(_centered(UI.label(key_text, 11, UI.GOLD)))
		var nm := _centered(UI.label("", 13 if not small else 15))
		nm.clip_text = true
		nm.custom_minimum_size = Vector2(48 if small else 76, 0)
		v.add_child(nm)
		var cd_bar := _bar(Color(0, 0, 0, 0.0), Vector2(48 if small else 76, 4))
		v.add_child(cd_bar)
		box.add_child(v)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		skills_row.add_child(box)
		skill_boxes[k] = {"box": box, "style": sb, "name": nm, "cd": cd_bar, "sid": ""}
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
	UI.tip_cls = p.cls
	inv_equip.set_equipment(p.equipment, p.cls, p.wset)
	inv_preview.set_char(p.cls, Data.weapon_model(p.cls, p.equipment, p.wset), p.equipment.get("head") != null)
	inv_name.text = "%s · %s %s" % [p.name, Data.CLASSES[p.cls].icon, Data.CLASSES[p.cls].name]
	UI.clear(inv_attrs)
	var at: Dictionary = p.stats.get("attrs", {})
	for k in Data.ATTRS:
		var bx := VBoxContainer.new()
		bx.custom_minimum_size = Vector2(48, 0)
		bx.add_child(_centered(UI.label(Data.ATTR_ICONS[k], 16)))
		bx.add_child(_centered(UI.label(str(int(at.get(k, 0))), 15, UI.GOLD if Data.POWER_ATTR[p.cls] == k else UI.TEXT)))
		bx.tooltip_text = Data.ATTR_NAMES[k]
		inv_attrs.add_child(bx)
	UI.clear(inv_skills)
	for sl in ["q", "e"]:
		var sk: Dictionary = Data.SKILLS[Skills.skill_id(p, sl)]
		inv_skills.add_child(UI.label("%s %s %s" % [sl.to_upper(), sk.get("icon", ""), sk.name], 13))
	inv_bag.hint = "우클릭: 장착/사용 · Shift+클릭: 바닥에 버리기" + " · R: 회전"
	inv_bag.set_items(p.bag, Inv.bag_size(p.cls))
	var items := []
	for s in Data.ALL_SLOTS:
		if p.equipment[s] != null:
			items.append(p.equipment[s])
	items.append_array(p.bag)
	inv_title.text = "소지품  (가치 💰 %d)" % Data.items_value(items)
	inv_stats.text = UI.stats_text(p.cls, p.stats)


# 인벤토리 조작은 서버(오프라인/호스트는 로컬 Game)가 처리
func _inv_op(op: String, args: Array) -> void:
	UI.hide_tip()
	game.request_inv(op, args)


func render_container() -> void:
	var c: Dictionary = container
	cont_title.text = c.name
	var corpse: bool = c.get("kind", "") == "corpse"
	cont_equip.visible = corpse
	if corpse:
		cont_equip.set_equipment(c.equipment, c.get("cls", "fighter"), 1)
		cont_grid.cell = 32.0
	else:
		cont_grid.cell = 36.0
	cont_grid.set_items(c.items, Vector2i(int(c.get("gw", Inv.CONT_W)), int(c.get("gh", 8))))


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
func damage_number(p: Vector3, amount: float, color: Color, prefix := "", crit := false) -> void:
	var l := Label3D.new()
	l.text = prefix + str(roundi(amount)) + ("!" if crit else "")
	l.font = UI.font
	l.font_size = 60 if crit else 40
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


# 조준선 X 표시: 맞혔을 때 잠깐 (치명타는 주황색으로 크게, 처치는 빨강)
func hit_marker(kill: bool, crit := false) -> void:
	hitmarker.modulate = Color(1, 0.25, 0.2, 1) if kill else (Color(1.0, 0.6, 0.15, 1) if crit else Color(1, 1, 1, 1))
	hitmarker.scale = Vector2.ONE * (1.35 if crit or kill else 1.0)
	hitmarker.pivot_offset = hitmarker.size * 0.5
	var tw := hitmarker.create_tween()
	tw.tween_property(hitmarker, "modulate:a", 0.0, 0.3 if crit else 0.22)


func shake(v: float) -> void:
	if game.player != null:
		game.player.shake = maxf(game.player.shake, v)


func swing(side: float, bash: bool, dur: float, hit_at := -1.0) -> void:
	if game.player != null:
		game.player.client_swing(side, bash, dur, hit_at)


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
	st_bar.visible = false # 던전본: 스태미나 없음
	# 스태미나 고갈 시 붉게 (30%까지 회복해야 다시 달리기 가능)
	if p.res_type() != "":
		mana_bar.value = p.res / maxf(1.0, p.res_max())
		res_label.text = "%s %d / %d" % [Data.RES_NAMES[p.res_type()], roundi(p.res), roundi(p.res_max())]
		mana_bar.get_parent().get_node("Cells").queue_redraw()
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
	elif p.channel_ready:
		sts.append("은신 준비 완료")
	if p.mimic_form:
		sts.append("📦 상자 변신 중 (우클릭: 해제)")
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
	var cbx = p.active_crossbow() if p.has_method("active_crossbow") else null
	if cbx != null:
		var n: int = p.bolt_count()
		var ld: bool = cbx.get("loaded", false)
		ammo_label.text = "➶ %d / %d" % [1 if ld else 0, n]
		ammo_hint.text = "재장전 중..." if p.reload_t > 0.0 else ("" if ld else ("R: 재장전" if n > 0 else "볼트 없음"))
		ammo_label.add_theme_color_override("font_color", UI.TEXT if ld else Color("#ff6a4a"))
	ammo_box.visible = cbx != null
	status_label.text = " · ".join(sts)
	var tl := maxf(0.0, g.time_left)
	timer_label.text = "%d:%02d" % [int(tl / 60.0), int(tl) % 60]
	timer_label.add_theme_color_override("font_color", Color("#ff4a3a") if tl < 120.0 else UI.TEXT)
	depth_label.text = Data.MAPS.get(g.map_id, {}).get("name", "던전")
	var ex: int = g.exit_portals().size()
	portal_label.text = "🌀 탈출 포탈 %d개 열림" % ex if ex > 0 else "🌀 포탈 대기 중"

	for k in ["q", "e"]:
		var sbx: Dictionary = skill_boxes[k]
		var def := Skills.skill_def(p, k)
		if sbx.name.text != def.name:
			sbx.name.text = def.name
		var mx: float = Skills.cd_of(p, Skills.skill_id(p, k)) if k != "rmb" else float(def.get("cd", 0.0))
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
				active = p.panther or p.spin_t > 0.0 or p.hold_q >= 0.0
			"e":
				active = p.stealth > 0.0 or p.channel_t > 0.0 or p.channel_ready or p.dr > 0.0 or p.frozen > 0.0 or p.dash != null or p.hold_e >= 0.0
		if k != "rmb":
			var sid := Skills.skill_id(p, k)
			if sid in ["druid_nature", "priest_protection"] and p.charges > 0:
				sbx.name.text = "%s ×%d" % [def.name, p.charges]
				cooling = p.charges <= 0
		var st: StyleBoxFlat = sbx.style
		st.border_color = Color("#ffd060") if active else Color("#5a4a32")
		st.set_border_width_all(2 if active else 1)
		sbx.name.modulate = Color(0.5, 0.5, 0.5) if cooling else Color.WHITE
	# 1/2: 무기 세트 (사용 중이면 금색 테두리)
	for k in ["w1", "w2"]:
		var sbx: Dictionary = skill_boxes[k]
		var n := int(k.right(1))
		var w = p.equipment.get(k)
		var txt = Data.base_of(w).icon if w != null else "✊"
		var o = p.equipment.get(k + "o")
		if o != null:
			txt += Data.base_of(o).icon
		if sbx.name.text != txt:
			sbx.name.text = txt
		var st2: StyleBoxFlat = sbx.style
		st2.border_color = Color("#ffd060") if p.wset == n else Color("#5a4a32")
		st2.set_border_width_all(2 if p.wset == n else 1)
	# 3/4/5: 소모품 칸 · G: 횃불 (손에 들고 있으면 금색)
	for k in ["c3", "c4", "c5", "torch"]:
		var sbx: Dictionary = skill_boxes[k]
		var it = p.equipment.get(k)
		var txt := "-"
		var flask := false
		if it != null:
			txt = Data.base_of(it).icon + str(int(it.get("count", 1)))
			# 체력 물약을 뺀 플라스크는 20초 공유 재사용 대기
			flask = Data.base_of(it).has("throw") or (Data.base_of(it).has("drink") and Data.base_of(it).drink != "heal")
		if k == "torch" and p.torch_t > 0.0:
			txt = "🔥%d초" % ceili(p.torch_t)
		if sbx.name.text != txt:
			sbx.name.text = txt
		var c2: float = p.cd.flask if flask else (p.cd.potion if k != "torch" else 0.0)
		(sbx.cd as ProgressBar).value = clampf(c2 / Skills.FLASK_CD if flask else c2, 0.0, 1.0)
		if flask and c2 > 0.0 and it != null:
			txt = "%s%d초" % [Data.base_of(it).icon, ceili(c2)]
			if sbx.name.text != txt:
				sbx.name.text = txt
		var usable: bool = it != null or (k == "torch" and p.torch_t > 0.0)
		sbx.name.modulate = Color(0.5, 0.5, 0.5) if not usable or c2 > 0.0 else Color.WHITE
		var st3: StyleBoxFlat = sbx.style
		st3.border_color = Color("#ffd060") if p.held == k else Color("#5a4a32")
		st3.set_border_width_all(2 if p.held == k else 1)

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
	vig_mat.set_shader_parameter("stealth", 1.0 if p.stealth > 0.0 or p.channel_t > 0.0 or p.channel_ready else 0.0)

	fps_label.text = "%d FPS" % Engine.get_frames_per_second()
