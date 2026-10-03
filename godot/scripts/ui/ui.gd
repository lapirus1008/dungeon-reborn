# UI 공용: 테마, 아이템 슬롯, 툴팁, 토스트
class_name UI
extends RefCounted

const GOLD := Color("#d9b45a")
const TEXT := Color("#e6dccb")
const MUTED := Color("#9a8e7a")
const PANEL := Color(0.086, 0.07, 0.055, 0.94)
const LINE := Color("#4a3c2a")

static var tooltip: PanelContainer
static var tooltip_label: RichTextLabel
static var toast_box: VBoxContainer
static var font: Font
static var theme: Theme


static func build_theme() -> Theme:
	# 가변 폰트 기본값은 가장 얇은 굵기이므로 굵기(wght)를 지정
	var kr: FontFile = load("res://fonts/NotoSansKR.ttf")
	var emoji_v := FontVariation.new()
	emoji_v.base_font = load("res://fonts/NotoEmoji.ttf")
	emoji_v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500}
	var fv := FontVariation.new()
	fv.base_font = kr
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500}
	fv.fallbacks = [emoji_v]
	font = fv
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 16
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.border_color = LINE
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(14)
	panel.shadow_color = Color(0, 0, 0, 0.5)
	panel.shadow_size = 12
	th.set_stylebox("panel", "PanelContainer", panel)
	th.set_stylebox("panel", "Panel", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color("#4a3620")
	btn.border_color = Color("#8a6a3a")
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(4)
	btn.set_content_margin_all(8)
	var btn_h := btn.duplicate()
	btn_h.bg_color = Color("#6a4c2a")
	var btn_d := btn.duplicate()
	btn_d.bg_color = Color("#2a2016")
	btn_d.border_color = Color("#3a3022")
	th.set_stylebox("normal", "Button", btn)
	th.set_stylebox("hover", "Button", btn_h)
	th.set_stylebox("pressed", "Button", btn_h)
	th.set_stylebox("disabled", "Button", btn_d)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color("#f3e3c0"))
	th.set_color("font_disabled_color", "Button", Color(0.5, 0.45, 0.4))
	th.set_color("font_color", "Label", TEXT)
	th.set_color("default_color", "RichTextLabel", TEXT)
	th.set_font("normal_font", "RichTextLabel", font)
	th.set_font("bold_font", "RichTextLabel", font)
	th.set_font_size("normal_font_size", "RichTextLabel", 16)
	th.set_font_size("bold_font_size", "RichTextLabel", 16)
	theme = th
	return th


static func label(text: String, size := 16, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func title(text: String) -> Label:
	var l := label(text, 18, GOLD)
	return l


static func button(text: String, cb: Callable, size := 15) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(func():
		Sfx.play("ui")
		cb.call())
	b.focus_mode = Control.FOCUS_NONE
	return b


static func big_button(text: String, cb: Callable) -> Button:
	var b := button(text, cb, 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#7a2416")
	sb.border_color = Color("#d06040")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(14)
	var sbh := sb.duplicate()
	sbh.bg_color = Color("#9a3420")
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbh)
	return b


static func panel_box(min_size := Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	return p


static var tip_cls := "" # 툴팁에서 착용 가능 여부를 표시할 현재 직업


static func _c(col: Color) -> String:
	return col.to_html(false)


# 아이템 세부 정보: 희귀도, 종류, 크기, 기본 수치(범위), 무작위 옵션(범위), 착용 직업, 가치
static func item_tip(item: Dictionary, extra := "") -> String:
	var b: Dictionary = Data.ITEM_BASES[item.base]
	var rar := int(item.get("rarity", 0))
	var r: Dictionary = Data.RARITIES[rar]
	var t := "[font_size=18][color=#%s]%s %s[/color][/font_size]\n" % [_c(r.color), b.icon, b.name]
	var kind := ""
	match b.slot:
		"weapon":
			kind = "무기"
		"consumable":
			kind = "소모품"
		"treasure":
			kind = "보물"
		_:
			kind = Data.SLOT_NAMES[b.slot]
	var sz: Array = b.get("size", [1, 1])
	t += "[color=#9a8e7a][font_size=13]%s %s · %dx%d칸[/font_size][/color]\n" % [r.name, kind, sz[0], sz[1]]
	var st: Dictionary = item.get("stats", {})
	if st.size():
		t += "[font_size=14]"
		for k in st:
			var line := Data.stat_label(k, st[k])
			var rng := ""
			if k == "armor" and b.has("armor"):
				rng = " [color=#7a7062](%d~%d)[/color]" % [maxi(1, roundi(b.armor * r.mult * 0.85)), roundi(b.armor * r.mult * 1.15)]
			elif k == "dmg" and b.has("dmg"):
				var m: float = b.dmg * (1.0 + (r.mult - 1.0) * 0.6)
				rng = " [color=#7a7062](%.2f~%.2f)[/color]" % [m * 0.95, m * 1.05]
			t += "[color=#e6dccb]%s[/color]%s\n" % [line, rng]
		t += "[/font_size]"
	var affs: Array = item.get("affixes", [])
	if affs.size():
		t += "[font_size=14]"
		for a in affs:
			var rg := Data.affix_range(a.k, rar)
			t += "[color=#8fd0ff]%s[/color] [color=#7a7062][%d~%d][/color]\n" % [Data.affix_label(a), rg.x, rg.y]
		t += "[/font_size]"
	if b.has("heal"):
		t += "[color=#8fd0ff]체력 %d 회복[/color]\n" % b.heal
	if b.slot == "weapon":
		var ok: bool = tip_cls == "" or tip_cls in b.classes
		t += "[font_size=12][color=#%s]착용: %s[/color][/font_size]\n" % ["9a8e7a" if ok else "e05a40", Data.class_names(b.classes)]
	t += "[color=#d9b45a]💰 %d 골드[/color]" % item.value
	if extra != "":
		t += "\n[color=#9a8e7a][font_size=12]%s[/font_size][/color]" % extra
	return t


# 능력치 / 파생 스탯 / 패시브 (로비와 던전 인벤토리 공용)
static func stats_text(cls: String, st: Dictionary) -> String:
	var a: Dictionary = st.attrs
	var base: Dictionary = Data.CLASS_ATTRS[cls]
	var t := "[font_size=13]"
	for k in Data.ATTRS:
		var diff: int = a[k] - base[k]
		var star := " ★" if Data.POWER_ATTR[cls] == k else ""
		t += "[color=#d9b45a]%s[/color] [b]%d[/b]%s%s   " % [Data.ATTR_NAMES[k], a[k], (" [color=#8fd0ff](+%d)[/color]" % diff) if diff > 0 else "", star]
	t += "\n[color=#9a8e7a]★ 피해량 능력치[/color]\n"
	t += "❤ %d · 🛡 %d (-%d%%) · ⚔ x%.2f · 👟 %d%% · ⚡ 공속 %d%% · ⏳ 쿨감 %d%%" % [
		st.max_hp, st.armor, roundi((1.0 - 100.0 / (100.0 + st.armor)) * 100.0), st.dmg_mul,
		roundi(st.speed_mul * 100.0), roundi(st.act_mul * 100.0), roundi((1.0 - st.cd_mul) * 100.0)]
	if st.res != "":
		t += " · 🔷 %s %d (회복 %d%%)" % [Data.RES_NAMES[st.res], st.res_max, roundi(st.regen_mul * 100.0)]
	t += "\n[color=#d9b45a]패시브[/color]\n"
	var ps: Array = Data.PASSIVES[cls]
	for i in ps.size():
		var p: Dictionary = ps[i]
		var req := []
		for k in p.req:
			req.append("%s %d" % [Data.ATTR_NAMES[k], p.req[k]])
		if i in st.passives:
			t += "[color=#9fe0a0]✔ %s[/color] [color=#9a8e7a]- %s[/color]\n" % [p.name, p.desc]
		else:
			t += "[color=#6a6258]🔒 %s - %s (필요: %s)[/color]\n" % [p.name, p.desc, ", ".join(req)]
	return t + "[/font_size]"


static func show_tip(text: String) -> void:
	if tooltip == null:
		return
	tooltip_label.text = text
	tooltip.visible = true
	tooltip.reset_size()


static func hide_tip() -> void:
	if tooltip:
		tooltip.visible = false


# 아이템 슬롯: 왼클릭/오른클릭 콜백
static func slot(item, on_left: Callable = Callable(), on_right: Callable = Callable(), opts: Dictionary = {}) -> Control:
	var sz: float = opts.get("size", 52.0)
	var p := Panel.new()
	p.custom_minimum_size = Vector2(sz, sz)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.047, 0.035)
	sb.border_color = Color("#3a3022")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	if item != null:
		var r: Dictionary = Data.RARITIES[item.rarity]
		sb.border_color = r.color
		sb.set_border_width_all(2)
		sb.bg_color = Color(0.06, 0.047, 0.035).lerp(r.color, 0.12)
	p.add_theme_stylebox_override("panel", sb)
	if opts.has("label"):
		var l := label(opts.label, 11, MUTED)
		l.position = Vector2(0, -17)
		p.add_child(l)
	if item != null:
		var b: Dictionary = Data.ITEM_BASES[item.base]
		var icon := label(b.icon, int(sz * 0.5), Data.RARITIES[item.rarity].color.lerp(Color.WHITE, 0.45))
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(icon)
		if opts.has("price"):
			var pr := label("%dg" % opts.price, 10, GOLD)
			pr.position = Vector2(sz - 26, sz - 16)
			p.add_child(pr)
		if opts.get("dim", false):
			p.modulate = Color(1, 1, 1, 0.45)
		var tip := item_tip(item, opts.get("tip", ""))
		p.mouse_entered.connect(func(): show_tip(tip))
		p.mouse_exited.connect(func(): hide_tip())
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_LEFT and on_left.is_valid():
				hide_tip()
				Sfx.play("ui")
				on_left.call()
			elif ev.button_index == MOUSE_BUTTON_RIGHT and on_right.is_valid():
				hide_tip()
				Sfx.play("ui")
				on_right.call())
	return p


static func toast(text: String) -> void:
	if toast_box == null:
		return
	var l := label(text, 15)
	var bg := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.75)
	sb.border_color = LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	bg.add_theme_stylebox_override("panel", sb)
	bg.add_child(l)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_child(bg)
	var tw := bg.create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(bg, "modulate:a", 0.0, 0.5)
	tw.tween_callback(bg.queue_free)
	while toast_box.get_child_count() > 5:
		toast_box.get_child(0).queue_free()
		toast_box.remove_child(toast_box.get_child(0))


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
