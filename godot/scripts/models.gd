# 기본 도형으로 만든 캐릭터/오브젝트 모델 (나중에 실제 3D 모델로 교체 가능하도록 한곳에 모음)
class_name Models
extends RefCounted

static var _mats := {}
static var _meshes := {}
static var hpbar_shader: Shader = preload("res://shaders/hpbar.gdshader")
static var shield_shader: Shader = preload("res://shaders/shield.gdshader")


static func mat(color: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f" % [color.to_html(), rough, metal]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]


static func glow_mat(color: Color, energy := 3.0) -> StandardMaterial3D:
	var key := "glow_%s_%.1f" % [color.to_html(), energy]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
		_mats[key] = m
	return _mats[key]


static func box_mesh(size: Vector3) -> BoxMesh:
	var key := "box%s" % size
	if not _meshes.has(key):
		var b := BoxMesh.new()
		b.size = size
		_meshes[key] = b
	return _meshes[key]


static func box(size: Vector3, material: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = box_mesh(size)
	m.material_override = material
	return m


static func cyl(top: float, bottom: float, height: float, material: Material, seg := 8) -> MeshInstance3D:
	var key := "cyl%.3f_%.3f_%.3f_%d" % [top, bottom, height, seg]
	if not _meshes.has(key):
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = bottom
		c.height = height
		c.radial_segments = seg
		c.rings = 1
		_meshes[key] = c
	var m := MeshInstance3D.new()
	m.mesh = _meshes[key]
	m.material_override = material
	return m


static func sphere(radius: float, material: Material, seg := 10) -> MeshInstance3D:
	var key := "sph%.3f_%d" % [radius, seg]
	if not _meshes.has(key):
		var s := SphereMesh.new()
		s.radius = radius
		s.height = radius * 2.0
		s.radial_segments = seg
		s.rings = seg / 2
		_meshes[key] = s
	var m := MeshInstance3D.new()
	m.mesh = _meshes[key]
	m.material_override = material
	return m


# 무기 색: 지팡이 구슬은 직업별 (파이로 빨강, 크라이오 하늘, 드루이드 초록)
static func weapon(type: String, orb_color := Color(0.4, 0.67, 1.0)) -> Node3D:
	var custom := AssetRegistry.scene("weapons", type)
	if custom != null:
		return custom
	var g := Node3D.new()
	var steel := mat(Color(0.78, 0.8, 0.83), 0.3, 0.9)
	var leather := mat(Color(0.23, 0.14, 0.08))
	match type:
		"longsword":
			var blade := box(Vector3(0.06, 1.25, 0.025), steel)
			blade.position.y = 0.82
			var guard := box(Vector3(0.22, 0.05, 0.06), mat(Color(0.2, 0.2, 0.22), 0.4, 0.7))
			guard.position.y = 0.18
			var grip := box(Vector3(0.045, 0.34, 0.045), leather)
			grip.position.y = 0.0
			for n in [blade, guard, grip]:
				g.add_child(n)
		"dagger":
			var blade := box(Vector3(0.05, 0.38, 0.02), steel)
			blade.position.y = 0.3
			var guard := box(Vector3(0.14, 0.03, 0.05), mat(Color(0.3, 0.3, 0.32), 0.4, 0.7))
			guard.position.y = 0.1
			var grip := box(Vector3(0.04, 0.16, 0.04), leather)
			for n in [blade, guard, grip]:
				g.add_child(n)
		"greatsword":
			var blade := box(Vector3(0.14, 1.5, 0.035), mat(Color(0.35, 0.36, 0.4), 0.35, 0.9))
			blade.position.y = 0.98
			var guard := box(Vector3(0.42, 0.08, 0.1), mat(Color(0.15, 0.12, 0.18), 0.4, 0.7))
			guard.position.y = 0.2
			var gem := box(Vector3(0.06, 0.06, 0.11), glow_mat(Color(0.6, 0.2, 0.9), 3.0))
			gem.position.y = 0.2
			var grip := box(Vector3(0.05, 0.4, 0.05), leather)
			for n in [blade, guard, gem, grip]:
				g.add_child(n)
		"mace":
			var shaft := cyl(0.03, 0.035, 0.7, mat(Color(0.3, 0.22, 0.12)), 6)
			shaft.position.y = 0.25
			var head := sphere(0.13, mat(Color(0.75, 0.68, 0.45), 0.35, 0.8), 8)
			head.position.y = 0.62
			for i in 4:
				var fl := box(Vector3(0.05, 0.2, 0.2), mat(Color(0.75, 0.68, 0.45), 0.35, 0.8))
				fl.position.y = 0.62
				fl.rotation.y = i * PI / 4
				g.add_child(fl)
			g.add_child(shaft)
			g.add_child(head)
		"sword", "boss_sword":
			var big := type == "boss_sword"
			var blade := box(Vector3(0.08, 1.6 if big else 1.0, 0.03), mat(Color(0.78, 0.8, 0.83), 0.3, 0.9))
			blade.position.y = 0.95 if big else 0.65
			var guard := box(Vector3(0.32, 0.06, 0.08), mat(Color(0.54, 0.41, 0.16), 0.4, 0.7))
			guard.position.y = 0.14
			var grip := box(Vector3(0.05, 0.25, 0.05), mat(Color(0.23, 0.14, 0.08)))
			g.add_child(blade)
			g.add_child(guard)
			g.add_child(grip)
		"bow":
			# 위/아래 활대 + 시위
			var wood := mat(Color(0.42, 0.27, 0.14))
			var up := box(Vector3(0.045, 0.62, 0.045), wood)
			up.position = Vector3(0.08, 0.3, 0)
			up.rotation.z = 0.28
			var dn := box(Vector3(0.045, 0.62, 0.045), wood)
			dn.position = Vector3(0.08, -0.3, 0)
			dn.rotation.z = -0.28
			var grip := box(Vector3(0.06, 0.14, 0.06), mat(Color(0.2, 0.12, 0.06)))
			grip.position.x = 0.16
			var string := box(Vector3(0.008, 1.18, 0.008), mat(Color(0.86, 0.86, 0.86)))
			string.position.x = -0.02
			g.add_child(up)
			g.add_child(dn)
			g.add_child(grip)
			g.add_child(string)
			g.set_meta("string", string)
		"staff":
			var shaft := cyl(0.035, 0.045, 1.6, mat(Color(0.36, 0.23, 0.11)), 6)
			shaft.position.y = 0.5
			var orb := sphere(0.11, glow_mat(orb_color, 4.0), 8)
			orb.position.y = 1.35
			g.add_child(shaft)
			g.add_child(orb)
			g.set_meta("orb", orb)
		"club":
			var c := cyl(0.09, 0.04, 0.8, mat(Color(0.29, 0.19, 0.09)), 6)
			c.position.y = 0.4
			g.add_child(c)
	return g


# 인간형 모델: parts 메타에 부위 노드 저장
static func humanoid(o: Dictionary) -> Node3D:
	var skin: Color = o.get("skin", Color(0.85, 0.66, 0.51))
	var body: Color = o.get("body", Color(0.33, 0.33, 0.33))
	var legs: Color = o.get("legs", Color(0.23, 0.23, 0.23))
	var head_c: Color = o.get("head", skin)
	var helmet = o.get("helmet", null)
	var wpn_type: String = o.get("weapon", "sword")
	var shield: bool = o.get("shield", false)
	var scale: float = o.get("scale", 1.0)
	var eyes = o.get("eyes", null)
	var skeletal: bool = o.get("skeletal", false)
	var hunch: float = o.get("hunch", 0.0)
	var hs: float = o.get("head_scale", 1.0)
	var metal: float = o.get("metal", 0.0)

	var root := Node3D.new()
	var rig := Node3D.new()
	rig.scale = Vector3.ONE * scale
	root.add_child(rig)
	var meshes: Array = []

	var torso_w := 0.38 if skeletal else 0.55
	var torso := box(Vector3(torso_w, 0.7, 0.3), mat(body, 0.7, metal))
	torso.position.y = 1.25
	torso.rotation.x = hunch
	rig.add_child(torso)
	meshes.append(torso)
	var bone := Color(0.85, 0.82, 0.72)
	if skeletal:
		for i in 4:
			var rib := box(Vector3(0.5, 0.04, 0.32), mat(bone))
			rib.position = Vector3(0, 1.05 + i * 0.13, 0)
			rig.add_child(rib)
			meshes.append(rib)

	var head := Node3D.new()
	head.position.y = 1.78
	var hd := box(Vector3(0.32, 0.34, 0.32) * hs, mat(head_c))
	head.add_child(hd)
	meshes.append(hd)
	if helmet != null:
		var hm := box(Vector3(0.36, 0.2, 0.36) * hs, mat(helmet, 0.35, 0.8))
		hm.position.y = 0.1 * hs
		head.add_child(hm)
		meshes.append(hm)
	if eyes != null:
		for s in [-1, 1]:
			var e := box(Vector3(0.06, 0.04, 0.02), glow_mat(eyes, 6.0))
			e.position = Vector3(s * 0.08 * hs, 0.02, -0.165 * hs)
			head.add_child(e)
	rig.add_child(head)

	var arm_c := bone if skeletal else body
	var limb := func(w: float, h: float, c: Color) -> Node3D:
		var g := Node3D.new()
		var m := box(Vector3(w, h, w), mat(c, 0.7, metal))
		m.position.y = -h / 2.0
		g.add_child(m)
		meshes.append(m)
		return g
	var arm_l: Node3D = limb.call(0.09 if skeletal else 0.15, 0.7, arm_c)
	var arm_r: Node3D = limb.call(0.09 if skeletal else 0.15, 0.7, arm_c)
	arm_l.position = Vector3(-(torso_w / 2 + 0.09), 1.55, 0)
	arm_r.position = Vector3(torso_w / 2 + 0.09, 1.55, 0)
	rig.add_child(arm_l)
	rig.add_child(arm_r)
	var leg_l: Node3D = limb.call(0.1 if skeletal else 0.18, 0.85, bone if skeletal else legs)
	var leg_r: Node3D = limb.call(0.1 if skeletal else 0.18, 0.85, bone if skeletal else legs)
	leg_l.position = Vector3(-0.13, 0.88, 0)
	leg_r.position = Vector3(0.13, 0.88, 0)
	rig.add_child(leg_l)
	rig.add_child(leg_r)

	var wpn := weapon(wpn_type, o.get("orb", Color(0.4, 0.67, 1.0)))
	if wpn_type == "bow":
		wpn.rotation = Vector3(0, PI / 2, 0)
		wpn.position = Vector3(0, -0.65, -0.05)
		arm_l.add_child(wpn)
	elif wpn_type == "dagger":
		wpn.position = Vector3(0, -0.68, 0)
		wpn.rotation.x = -PI / 2
		arm_r.add_child(wpn)
		var w2 := weapon("dagger")
		w2.position = Vector3(0, -0.68, 0)
		w2.rotation.x = -PI / 2
		arm_l.add_child(w2)
	else:
		wpn.position = Vector3(0, -0.68, 0)
		wpn.rotation.x = -PI / 2
		arm_r.add_child(wpn)
	for c in wpn.get_children():
		if c is MeshInstance3D:
			meshes.append(c)
	if shield:
		var sh := cyl(0.32, 0.32, 0.06, mat(Color(0.42, 0.29, 0.14)), 12)
		sh.rotation.z = PI / 2
		sh.position = Vector3(-0.08, -0.5, 0)
		arm_l.add_child(sh)
		meshes.append(sh)

	root.set_meta("parts", {"rig": rig, "torso": torso, "head": head, "arm_l": arm_l, "arm_r": arm_r, "leg_l": leg_l, "leg_r": leg_r, "wpn": wpn})
	root.set_meta("meshes", meshes)
	return root


static func chest(tier: int) -> Node3D:
	var custom := AssetRegistry.scene("props", "chest_%d" % tier)
	if custom != null:
		# 교체 모델은 뚜껑 노드 이름을 "Lid"로 둔다
		var lid_node = custom.find_child("Lid", true, false)
		custom.set_meta("lid", lid_node if lid_node != null else Node3D.new())
		return custom
	var g := Node3D.new()
	var tint := Color(1.0, 0.82, 0.48) if tier == 2 else (Color(0.85, 0.65, 0.45) if tier == 1 else Color.WHITE)
	var key := "chest%d" % tier
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = Textures.wood()
		m.albedo_color = tint
		m.roughness = 0.75
		_mats[key] = m
	var body_m: StandardMaterial3D = _mats[key]
	var base := box(Vector3(1.3, 0.7, 0.85), body_m)
	base.position.y = 0.35
	g.add_child(base)
	var lid_pivot := Node3D.new()
	lid_pivot.position = Vector3(0, 0.7, 0.42)
	var lid := cyl(0.42, 0.42, 1.3, body_m, 10)
	lid.rotation.z = PI / 2
	lid.position.z = -0.42
	lid_pivot.add_child(lid)
	g.add_child(lid_pivot)
	var metal := mat(Color(1.0, 0.8, 0.2), 0.3, 0.9) if tier == 2 else mat(Color(0.47, 0.47, 0.47), 0.4, 0.8)
	for x in [-0.45, 0.45]:
		var band := box(Vector3(0.08, 0.72, 0.88), metal)
		band.position = Vector3(x, 0.35, 0)
		g.add_child(band)
	var lock := box(Vector3(0.16, 0.2, 0.06), metal)
	lock.position = Vector3(0, 0.62, -0.45)
	g.add_child(lock)
	g.set_meta("lid", lid_pivot)
	if tier == 2:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.4)
		l.light_energy = 0.8
		l.omni_range = 3.0
		l.position.y = 1.0
		g.add_child(l)
	return g


static func loot_bag(color: Color) -> Node3D:
	var g := Node3D.new()
	var b := sphere(0.4, mat(color), 10)
	b.scale = Vector3(1, 0.8, 1)
	b.position.y = 0.3
	var knot := cyl(0.0, 0.15, 0.3, mat(color), 6)
	knot.position.y = 0.72
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.5
	tm.outer_radius = 0.6
	tm.rings = 16
	tm.ring_segments = 3
	ring.mesh = tm
	ring.material_override = glow_mat(Color(1.0, 0.82, 0.38), 2.0)
	ring.scale = Vector3(1, 0.1, 1)
	ring.position.y = 0.03
	g.add_child(b)
	g.add_child(knot)
	g.add_child(ring)
	return g


static func portal(kind: String) -> Node3D:
	var color := Color(0.29, 0.72, 1.0) if kind == "exit" else Color(1.0, 0.23, 0.16)
	var g := Node3D.new()
	var spin := Node3D.new()
	spin.position.y = 1.8
	g.add_child(spin)
	var tm := TorusMesh.new()
	tm.inner_radius = 1.38
	tm.outer_radius = 1.62
	tm.rings = 32
	tm.ring_segments = 8
	var ring := MeshInstance3D.new()
	ring.mesh = tm
	ring.material_override = glow_mat(color, 5.0)
	ring.rotation.x = PI / 2
	spin.add_child(ring)
	var disc_m := StandardMaterial3D.new()
	disc_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc_m.albedo_color = Color(color.r, color.g, color.b, 0.4)
	disc_m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.4
	cm.bottom_radius = 1.4
	cm.height = 0.02
	cm.radial_segments = 32
	disc.mesh = cm
	disc.material_override = disc_m
	disc.rotation.x = PI / 2
	spin.add_child(disc)
	var floor_ring := MeshInstance3D.new()
	var fr := TorusMesh.new()
	fr.inner_radius = 1.8
	fr.outer_radius = 2.2
	fr.rings = 32
	fr.ring_segments = 3
	floor_ring.mesh = fr
	floor_ring.material_override = glow_mat(color, 2.0)
	floor_ring.scale = Vector3(1, 0.05, 1)
	floor_ring.position.y = 0.04
	g.add_child(floor_ring)
	var parts := CPUParticles3D.new()
	parts.amount = 60
	parts.lifetime = 2.5
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	parts.emission_ring_axis = Vector3.UP
	parts.emission_ring_radius = 1.8
	parts.emission_ring_inner_radius = 0.2
	parts.emission_ring_height = 0.1
	parts.direction = Vector3.UP
	parts.spread = 15.0
	parts.gravity = Vector3(0, 0.6, 0)
	parts.initial_velocity_min = 0.3
	parts.initial_velocity_max = 0.9
	parts.scale_amount_min = 0.5
	parts.scale_amount_max = 1.0
	var pm := SphereMesh.new()
	pm.radius = 0.04
	pm.height = 0.08
	pm.radial_segments = 4
	pm.rings = 2
	pm.material = glow_mat(color, 6.0)
	parts.mesh = pm
	g.add_child(parts)
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 3.5
	l.omni_range = 14.0
	l.position.y = 2.0
	g.add_child(l)
	g.set_meta("spin", spin)
	g.set_meta("disc", disc_m)
	g.set_meta("light", l)
	return g


static func arrow() -> Node3D:
	var g := Node3D.new()
	var shaft := cyl(0.015, 0.015, 0.8, mat(Color(0.54, 0.41, 0.23)), 4)
	shaft.rotation.x = PI / 2
	var tip := cyl(0.0, 0.04, 0.12, mat(Color(0.6, 0.6, 0.6), 0.3, 0.9), 4)
	tip.rotation.x = -PI / 2
	tip.position.z = -0.45
	var fl := box(Vector3(0.002, 0.06, 0.12), mat(Color(0.9, 0.9, 0.85)))
	fl.position.z = 0.36
	g.add_child(shaft)
	g.add_child(tip)
	g.add_child(fl)
	return g


static func orb(color: Color, size: float, with_light := true) -> Node3D:
	var g := Node3D.new()
	var core := sphere(size, glow_mat(Color(1, 1, 1), 4.0), 8)
	var halo_m := StandardMaterial3D.new()
	halo_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_m.albedo_color = Color(color.r, color.g, color.b, 0.6)
	var halo := sphere(size * 1.9, halo_m, 10)
	g.add_child(core)
	g.add_child(halo)
	if with_light:
		var l := OmniLight3D.new()
		l.light_color = color
		l.light_energy = 2.0
		l.omni_range = 7.0
		g.add_child(l)
	return g


static func shield_bubble(radius: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 32
	s.rings = 16
	m.mesh = s
	var sm := ShaderMaterial.new()
	sm.shader = shield_shader
	m.material_override = sm
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


static func hp_bar() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 0.1)
	m.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = hpbar_shader
	m.material_override = sm
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.visible = false
	return m


# ------------------------------------------------------------------ 직업별 외형
const CLASS_LOOK := {
	"fighter": {"body": Color(0.48, 0.5, 0.53), "legs": Color(0.23, 0.23, 0.25), "helmet": Color(0.54, 0.56, 0.6), "shield": true, "metal": 0.6},
	"swordmaster": {"body": Color(0.45, 0.12, 0.12), "legs": Color(0.12, 0.1, 0.1), "helmet": Color(0.15, 0.12, 0.12), "shield": false, "metal": 0.2},
	"rogue": {"body": Color(0.14, 0.14, 0.16), "legs": Color(0.1, 0.1, 0.11), "helmet": Color(0.09, 0.09, 0.1), "shield": false, "metal": 0.0},
	"deathknight": {"body": Color(0.1, 0.1, 0.13), "legs": Color(0.07, 0.07, 0.09), "helmet": Color(0.15, 0.13, 0.2), "shield": false, "metal": 0.8, "eyes": Color(0.6, 0.3, 1.0)},
	"druid": {"body": Color(0.3, 0.4, 0.2), "legs": Color(0.3, 0.22, 0.13), "helmet": Color(0.35, 0.5, 0.25), "shield": false, "metal": 0.0},
	"pyromancer": {"body": Color(0.55, 0.16, 0.08), "legs": Color(0.3, 0.08, 0.05), "helmet": Color(0.45, 0.12, 0.06), "shield": false, "metal": 0.0},
	"cryomancer": {"body": Color(0.6, 0.75, 0.88), "legs": Color(0.3, 0.4, 0.55), "helmet": Color(0.7, 0.85, 0.95), "shield": false, "metal": 0.0},
	"priest": {"body": Color(0.85, 0.82, 0.72), "legs": Color(0.55, 0.5, 0.4), "helmet": Color(0.9, 0.8, 0.45), "shield": false, "metal": 0.3},
}
const ORB_COLORS := {"druid": Color(0.4, 1.0, 0.45), "pyromancer": Color(1.0, 0.45, 0.15), "cryomancer": Color(0.6, 0.9, 1.0)}


static func orb_color(cls: String) -> Color:
	return ORB_COLORS.get(cls, Color(0.4, 0.67, 1.0))


# 모험가(플레이어/AI) 모델: res://assets/characters/<직업>.glb 가 있으면 교체됨
static func hero_rig(cls: String, wmodel: String, helmet: bool) -> CharacterRig:
	return CharacterRig.create(cls, func():
		var look: Dictionary = CLASS_LOOK[cls]
		var root := humanoid({
			"body": look.body, "legs": look.legs, "helmet": look.helmet if helmet else null,
			"weapon": wmodel, "shield": look.shield, "metal": look.metal, "eyes": look.get("eyes", null),
			"orb": orb_color(cls),
		})
		return root)


# 드루이드 표범 형태
static func panther_rig() -> CharacterRig:
	return CharacterRig.create("panther", func():
		var root := Node3D.new()
		var rig := Node3D.new()
		root.add_child(rig)
		var fur := mat(Color(0.08, 0.08, 0.09), 0.6)
		var body := box(Vector3(0.5, 0.45, 1.3), fur)
		body.position.y = 0.75
		var head := box(Vector3(0.36, 0.34, 0.42), fur)
		head.position = Vector3(0, 0.95, -0.8)
		var tail := box(Vector3(0.08, 0.08, 0.8), fur)
		tail.position = Vector3(0, 0.85, 1.0)
		tail.rotation.x = -0.4
		var meshes := [body, head, tail]
		for n in meshes:
			rig.add_child(n)
		for s in [-1, 1]:
			var e := box(Vector3(0.07, 0.04, 0.02), glow_mat(Color(0.5, 1.0, 0.4), 6.0))
			e.position = Vector3(s * 0.09, 1.0, -1.02)
			rig.add_child(e)
		var legs := []
		for p in [Vector3(-0.18, 0.55, -0.45), Vector3(0.18, 0.55, -0.45), Vector3(-0.18, 0.55, 0.45), Vector3(0.18, 0.55, 0.45)]:
			var pivot := Node3D.new()
			pivot.position = p
			var leg := box(Vector3(0.13, 0.55, 0.13), fur)
			leg.position.y = -0.27
			pivot.add_child(leg)
			rig.add_child(pivot)
			legs.append(pivot)
			meshes.append(leg)
		var dummy := Node3D.new()
		rig.add_child(dummy)
		root.set_meta("parts", {"rig": rig, "leg_l": dummy, "leg_r": dummy, "arm_l": dummy, "arm_r": dummy, "panther_legs": legs})
		root.set_meta("meshes", meshes)
		return root)


# 드루이드 소환수 트렌트
static func treant_rig() -> CharacterRig:
	return CharacterRig.create("treant", func():
		var root := humanoid({"skin": Color(0.35, 0.25, 0.15), "body": Color(0.32, 0.22, 0.12), "legs": Color(0.28, 0.2, 0.1), "weapon": "claws", "scale": 1.6, "eyes": Color(0.5, 1.0, 0.3), "hunch": 0.2})
		var leaves := sphere(0.45, mat(Color(0.2, 0.45, 0.15)), 8)
		leaves.position.y = 3.25
		root.add_child(leaves)
		return root)


# 크라이오맨서 서리 장벽 얼음 덩어리
static func ice_block(h: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(1.4, h, 1.4)
	m.mesh = b
	var mt := StandardMaterial3D.new()
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.albedo_color = Color(0.6, 0.85, 1.0, 0.45)
	mt.roughness = 0.05
	mt.metallic = 0.2
	mt.emission_enabled = true
	mt.emission = Color(0.3, 0.6, 1.0)
	mt.emission_energy_multiplier = 0.6
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material_override = mt
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position.y = h / 2.0
	return m


# ------------------------------------------------------------------ 1인칭 뷰모델 (카메라 자식)
# res://assets/viewmodels/<직업>.glb 가 있으면 교체 (자식 노드 "R", "L"이 있으면 손 애니메이션이 적용됨)
static func view_model(cls: String, wmodel: String, panther := false) -> Node3D:
	var key := "panther" if panther else cls
	var custom := AssetRegistry.scene("viewmodels", key)
	if custom != null:
		for n in ["R", "L"]:
			if custom.find_child(n, true, false) == null:
				var d := Node3D.new()
				d.name = n
				custom.add_child(d)
		custom.set_meta("R", custom.find_child("R", true, false))
		custom.set_meta("L", custom.find_child("L", true, false))
		custom.set_meta("weapon", Node3D.new())
		return custom
	var g := Node3D.new()
	var look: Dictionary = CLASS_LOOK[cls]
	var sleeve_c: Color = Color(0.06, 0.06, 0.07) if panther else look.body
	var arm_mat := mat(sleeve_c, 0.6, look.metal if not panther else 0.0)
	var hand_mat := mat(Color(0.08, 0.08, 0.09) if panther else Color(0.7, 0.52, 0.4))
	var make_arm := func(side: float) -> Node3D:
		var a := Node3D.new()
		var sleeve := box(Vector3(0.09, 0.09, 0.4), arm_mat)
		sleeve.position.z = 0.12
		var hand := box(Vector3(0.08, 0.08, 0.1), hand_mat)
		hand.position.z = -0.12
		a.add_child(sleeve)
		a.add_child(hand)
		a.position = Vector3(side * 0.3, -0.34, -0.6)
		return a
	var R: Node3D = make_arm.call(1.0)
	var L: Node3D = make_arm.call(-1.0)
	g.add_child(R)
	g.add_child(L)
	var w := Node3D.new()
	if panther:
		# 발톱
		for arm in [R, L]:
			for i in 3:
				var claw := box(Vector3(0.015, 0.015, 0.12), mat(Color(0.9, 0.88, 0.8), 0.3))
				claw.position = Vector3((i - 1) * 0.025, 0.02, -0.22)
				arm.add_child(claw)
	else:
		match wmodel:
			"sword":
				w = weapon("sword")
				w.position = Vector3(0, 0, -0.14)
				w.rotation = Vector3(-0.5, 0, -0.25)
				w.scale = Vector3.ONE * 0.55
				R.add_child(w)
			"longsword":
				w = weapon("longsword")
				w.position = Vector3(-0.08, 0.0, -0.14)
				w.rotation = Vector3(-0.45, 0, 0.15)
				w.scale = Vector3.ONE * 0.55
				R.add_child(w)
				L.position = Vector3(-0.08, -0.38, -0.55)
			"greatsword":
				w = weapon("greatsword")
				w.position = Vector3(-0.08, 0.0, -0.12)
				w.rotation = Vector3(-0.35, 0, 0.3)
				w.scale = Vector3.ONE * 0.5
				R.add_child(w)
			"dagger":
				w = weapon("dagger")
				w.position = Vector3(0, 0, -0.14)
				w.rotation = Vector3(-1.2, 0, 0)
				w.scale = Vector3.ONE * 0.7
				R.add_child(w)
				var w2 := weapon("dagger")
				w2.position = Vector3(0, 0, -0.14)
				w2.rotation = Vector3(-1.2, 0, 0)
				w2.scale = Vector3.ONE * 0.7
				L.add_child(w2)
			"mace":
				w = weapon("mace")
				w.position = Vector3(0, 0, -0.12)
				w.rotation = Vector3(-0.6, 0, -0.2)
				w.scale = Vector3.ONE * 0.6
				R.add_child(w)
				var book := box(Vector3(0.16, 0.2, 0.05), mat(Color(0.5, 0.35, 0.15)))
				book.position = Vector3(0.05, 0.08, -0.2)
				var trim := box(Vector3(0.17, 0.21, 0.02), glow_mat(Color(1.0, 0.85, 0.4), 1.5))
				trim.position = Vector3(0.05, 0.08, -0.23)
				L.add_child(book)
				L.add_child(trim)
			_:
				w = weapon("staff", orb_color(cls))
				w.position = Vector3(0, -0.3, -0.12)
				w.rotation = Vector3(-0.35, 0, -0.12)
				w.scale = Vector3.ONE * 0.42
				R.add_child(w)
		if cls == "fighter":
			var sh := cyl(0.2, 0.2, 0.04, mat(Color(0.29, 0.2, 0.09)), 14)
			sh.rotation.x = PI / 2
			sh.position = Vector3(-0.06, -0.02, -0.3)
			var boss := sphere(0.045, mat(Color(0.47, 0.47, 0.47), 0.3, 0.9), 6)
			boss.position = Vector3(-0.06, -0.02, -0.33)
			L.add_child(sh)
			L.add_child(boss)
	# 뷰모델은 그림자를 드리우지 않음
	for n in g.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.set_meta("R", R)
	g.set_meta("L", L)
	g.set_meta("weapon", w)
	g.set_meta("L0", L.position)
	return g
