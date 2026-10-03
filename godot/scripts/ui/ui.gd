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


# 아이템 세부 정보 (던전본 툴팁): 희귀도/종류/레벨, 기본 수치, 고정 옵션(범위), 무작위 옵션(Ω/Φ/Δ), 세트, 고유 효과
static func item_tip(item: Dictionary, extra := "") -> String:
	var b: Dictionary = Data.ITEM_BASES[item.base]
	var rar := int(item.get("rarity", b.get("rarity", 0)))
	var r: Dictionary = Data.RARITIES[rar]
	var cnt := int(item.get("count", 1))
	var t := "[font_size=18][color=#%s]%s %s%s[/color][/font_size]\n" % [_c(r.color), b.icon, b.name, (" x%d" % cnt) if cnt > 1 else ""]
	var kind := ""
	match b.slot:
		"weapon":
			kind = Data.WEAPON_NAMES.get(b.cat, "무기") + (" (양손)" if b.cat in Data.TWO_HANDED else (" (보조)" if b.cat in Data.OFFHAND else ""))
		"consumable":
			kind = "소모품"
		"utility":
			kind = "투척"
		"treasure":
			kind = "보물"
		_:
			kind = (Data.ARMOR_TYPES.get(b.get("cat", ""), "") + " " if Data.ARMOR_TYPES.has(b.get("cat", "")) else "") + Data.SLOT_NAMES.get(b.slot, b.slot)
	var sz: Array = b.get("size", [1, 1])
	var lvl := ""
	if b.has("lvl") and b.slot == "weapon" and not (b.cat in Data.OFFHAND):
		lvl = " · 공격 레벨 %d" % b.lvl
	elif b.has("lvl") and b.slot in ["head", "chest", "legs", "weapon"]:
		lvl = " · 방어 레벨 %d" % b.lvl
	t += "[color=#9a8e7a][font_size=13]%s %s%s · %dx%d칸[/font_size][/color]\n" % [r.name, kind, lvl, sz[0], sz[1]]
	t += "[font_size=14]"
	var st: Dictionary = item.get("stats", {})
	if st.has("dmg") and int(st.dmg) > 0:
		var rng := ""
		if b.get("dmg", [0, 0])[0] != b.get("dmg", [0, 0])[1]:
			rng = " [color=#7a7062](%d~%d)[/color]" % [b.dmg[0], b.dmg[1]]
		t += "[color=#e6dccb]%d %s 피해[/color]%s\n" % [st.dmg, Data.DMG_TYPES.get(b.get("dtype", "phys"), "물리"), rng]
	if b.slot == "weapon":
		if b.cat in Data.OFFHAND or b.cat in ["sword", "longsword", "dagger", "mace"]:
			t += "[color=#e6dccb]%d%% 막은 피해 감소[/color]\n" % (97 if b.cat == "shield" else 75)
		var ms: int = {"sword": -10, "longsword": -30, "mace": -15, "staff": -30, "crossbow": -30, "shield": -10, "orb": -10}.get(b.cat, 0)
		if ms != 0:
			t += "[color=#e6dccb]%d 이동 속도[/color]\n" % ms
	if st.has("armor"):
		t += "[color=#e6dccb]방어도 %d[/color]\n" % st.armor
	if b.get("ms", 0) != 0 and b.slot != "weapon":
		t += "[color=#e6dccb]%d 이동 속도[/color]\n" % b.ms
	for f in item.get("fixed", []):
		if f.k == "set":
			continue
		var rng := ""
		if f.has("min") and f.min != f.max:
			rng = (" [color=#7a7062](%.1f~%.1f)[/color]" % [f.min, f.max]) if f.min is float else (" [color=#7a7062](%d~%d)[/color]" % [f.min, f.max])
		t += "[color=#d9c9a8]%s[/color]%s\n" % [Data.mod_label(f), rng]
	t += "[/font_size]"
	var affs: Array = item.get("affixes", []) + item.get("fixed", []).filter(func(x): return x.k == "set")
	if affs.size():
		t += "[font_size=14]"
		for a in affs:
			if a.k == "set":
				var sp: Dictionary = Data.SET_PERKS.get(a.set, {})
				t += "[color=#ffd36a]◆ %s[/color] [color=#7a7062](세트 포인트)[/color]\n" % Data.mod_label(a)
				for tr in sp.get("tiers", []):
					t += "[font_size=11][color=#9a8e7a]   %d: %s[/color][/font_size]\n" % [tr[0], tr[1]]
			else:
				t += "[color=#8fd0ff]%s[/color] [color=#7a7062]%s[/color]\n" % [Data.mod_label(a), Data.TIER_NAMES[int(a.get("t", 0))]]
		t += "[/font_size]"
	if b.has("unique"):
		t += "[font_size=13][color=#ff9b5a]%s[/color][/font_size]\n" % b.unique
	if b.has("heal"):
		t += "[color=#8fd0ff]체력 %d 회복[/color]\n" % b.heal
	if b.has("mana"):
		t += "[color=#8fd0ff]마나 %d 회복[/color]\n" % b.mana
	if b.slot == "utility":
		t += "[color=#8fd0ff]G 키로 던지기 (피해 %d)[/color]\n" % b.get("dmg", 0)
	if b.slot == "weapon":
		var cl: Array = Data.weapon_classes(b.cat)
		var ok: bool = tip_cls == "" or tip_cls in cl
		t += "[font_size=12][color=#%s]착용: %s[/color][/font_size]\n" % ["9a8e7a" if ok else "e05a40", Data.class_names(cl)]
	t += "[color=#d9b45a]💰 %d 골드%s[/color]" % [int(item.value) * cnt, (" (개당 %d)" % item.value) if cnt > 1 else ""]
	if extra != "":
		t += "\n[color=#9a8e7a][font_size=12]%s[/font_size][/color]" % extra
	return t


# 스킬 툴팁
static func skill_tip(sid: String) -> String:
	var sk: Dictionary = Data.SKILLS[sid]
	var t := "[font_size=17][color=#d9b45a]%s %s[/color][/font_size]\n" % [sk.get("icon", ""), sk.name]
	t += "[font_size=12][color=#9a8e7a]재사용 대기 %.0f초%s[/color][/font_size]\n" % [sk.cd, (" · 자원 %d" % sk.cost) if sk.has("cost") else ""]
	t += "[font_size=13]%s[/font_size]" % sk.desc
	return t


# 능력치 / 파생 스탯 / 패시브 (로비와 던전 인벤토리 공용)
static func stats_text(cls: String, st: Dictionary) -> String:
	var a: Dictionary = st.attrs
	var base: Dictionary = Data.CLASS_ATTRS[cls]
	var t := "[font_size=13]"
	for k in Data.ATTRS:
		var diff: int = a[k] - base[k]
		var star := "★" if Data.POWER_ATTR[cls] == k else ""
		t += "%s [color=#d9b45a]%s%s[/color] [b]%d[/b]%s   " % [Data.ATTR_ICONS[k], Data.ATTR_NAMES[k], star, a[k], (" [color=#8fd0ff](+%d)[/color]" % diff) if diff > 0 else ""]
		if k == "vit":
			t += "\n"
	t += "\n[color=#9a8e7a]★ 피해량 능력치[/color]\n"
	t += "❤ %d · 🛡 %d · 물리 저항 %d%% · ⚔ x%.2f · 치명 %d%% (x%.2f)\n👟 %d%% · ⚡ 공속 %d%% · ⏳ 쿨감 %d%%" % [
		st.max_hp, st.armor, roundi(st.pres * 100.0), st.dmg_mul, roundi(st.crit * 100.0), st.crit_mul,
		roundi(st.speed_mul * 100.0), roundi(st.act_mul * 100.0), roundi((1.0 - st.cd_mul) * 100.0)]
	if st.res != "":
		t += " · %s %d" % [Data.RES_NAMES[st.res], st.res_max]
	var sets: Dictionary = st.get("sets", {})
	for k in sets:
		var tier := Data.set_tier(st, k)
		t += "\n[color=#ffd36a]◆ %s %d점%s[/color]" % [Data.SET_PERKS[k].name, sets[k], (" (%d단계 발동)" % tier) if tier > 0 else ""]
	t += "\n[color=#d9b45a]패시브 (조건을 채우면 자동 활성)[/color]\n"
	var ps: Array = Data.PASSIVES[cls]
	for i in ps.size():
		var p: Dictionary = ps[i]
		var req := []
		for k in p.req:
			req.append("%s %d" % [Data.ATTR_NAMES[k], p.req[k]])
		if i in st.passives:
			t += "[color=#9fe0a0]✔ %s[/color] [color=#9a8e7a][font_size=11]%s[/font_size][/color]\n" % [p.name, p.desc]
		else:
			t += "[color=#6a6258]🔒 %s (%s) [font_size=11]%s[/font_size][/color]\n" % [p.name, ", ".join(req), p.desc]
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
