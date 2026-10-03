# 레이드(던전) 진행: 월드 구성, 전투, 투사체, 이펙트, 상자, 전리품, 포탈, 붕괴
class_name Game
extends Node3D

signal raid_ended(result: Dictionary)

const RAID_TIME := 900.0 # 15분

var loadout: Dictionary
var quality := "mid"
var sensitivity := 0.0022
var world: Node3D
var camera: Camera3D
var env: WorldEnvironment
var player_light: OmniLight3D
var view_model: Node3D
var shield_bubble: MeshInstance3D
var hud # Hud
var dungeon: Dungeon
var player: Player
var actors: Array = []
var projectiles: Array = []
var effects: Array = []
var chests: Array = []
var loot_bags: Array = []
var portals: Array = []
var portal_schedule: Array = []
var explored := PackedByteArray()
var time := 0.0
var level_time := 0.0
var time_left := RAID_TIME
var depth := 1
var result = null
var end_timer := -1.0
var warned := false
var boss_dead := false
var running := false
var typing := false
var force_act := false # 자동 테스트용
var menu_open := false
var flash_mat: StandardMaterial3D
var base_fog := 0.03
var cull_t := 0.0
var interact_target = null


func _ready() -> void:
	flash_mat = StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(1, 0.15, 0.1, 0.55)
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD


func start(lo: Dictionary, hud_node) -> void:
	loadout = lo
	hud = hud_node
	time = 0.0
	time_left = RAID_TIME
	result = null
	end_timer = -1.0
	player = null
	build_level(1)
	running = true
	hud.start(self)
	hud.announce("던전에 입장했습니다", "보물을 모아 탈출 포탈로 살아 나가세요")


func shadows_enabled() -> bool:
	return quality != "low"


func build_level(d: int) -> void:
	if world:
		world.queue_free()
	if dungeon:
		dungeon.dispose()
	for p in projectiles:
		if is_instance_valid(p.node):
			p.node.queue_free()
	depth = d
	level_time = 0.0
	warned = false
	boss_dead = false
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	var deep := d > 1

	# 환경: 어두운 배경, 안개, 글로우, 톤매핑
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.005, 0.004) if deep else Color(0.008, 0.008, 0.01)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.32, 0.18, 0.16) if deep else Color(0.24, 0.22, 0.26)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.1
	e.fog_enabled = true
	e.fog_light_color = Color(0.09, 0.03, 0.02) if deep else Color(0.04, 0.035, 0.03)
	e.fog_density = base_fog
	e.fog_sky_affect = 0.0
	e.glow_enabled = quality != "low"
	e.glow_intensity = 0.7
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 1.0
	e.ssao_enabled = quality == "high"
	e.ssao_radius = 1.2
	e.ssao_intensity = 1.5
	env.environment = e
	world.add_child(env)

	dungeon = Dungeon.new(d)
	dungeon.build(world, false)
	explored = PackedByteArray()
	explored.resize(dungeon.W * dungeon.H)
	actors = []
	projectiles = []
	effects = []
	chests = []
	loot_bags = []
	portals = []
	if deep:
		portal_schedule = [{"at": 45.0, "kind": "exit", "n": 2}, {"at": 200.0, "kind": "exit", "n": 2}]
	else:
		portal_schedule = [
			{"at": 120.0, "kind": "exit", "n": 2},
			{"at": 210.0, "kind": "descend", "n": 1},
			{"at": 400.0, "kind": "exit", "n": 2},
			{"at": 640.0, "kind": "exit", "n": 1},
		]

	var rooms: Array = dungeon.rooms
	var boss_room: Dictionary
	var normal := []
	for r in rooms:
		if r.boss:
			boss_room = r
		else:
			normal.append(r)
	var dist_boss := func(r): return Vector2(r.cx - boss_room.cx, r.cz - boss_room.cz).length()
	normal.sort_custom(func(a, b): return dist_boss.call(a) > dist_boss.call(b))
	var start_room: Dictionary = normal[randi_range(0, mini(3, normal.size() - 1))]
	var spawn := dungeon.random_point_in_room(start_room, 1)

	if player == null:
		player = Player.new(self, spawn, loadout.cls, loadout.equipment, loadout.bag)
	else:
		player.pos = spawn
	player.yaw = randf() * TAU
	actors.append(player)

	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 90.0
	world.add_child(camera)
	camera.make_current()
	# 플레이어 횃불(손전등 역할) - 그림자로 입체감
	player_light = OmniLight3D.new()
	player_light.light_color = Color(1.0, 0.72, 0.45)
	player_light.light_energy = 1.6
	player_light.omni_range = 16.0
	player_light.omni_attenuation = 1.3
	player_light.shadow_enabled = shadows_enabled()
	player_light.shadow_bias = 0.08
	world.add_child(player_light)
	view_model = Models.view_model(player.cls)
	camera.add_child(view_model)
	shield_bubble = Models.shield_bubble(0.75)
	shield_bubble.visible = false
	camera.add_child(shield_bubble)

	# 경쟁 모험가 스폰 (플레이어와 먼 방)
	var others := []
	for r in normal:
		if r != start_room:
			others.append(r)
	others.sort_custom(func(a, b): return Vector2(a.cx - start_room.cx, a.cz - start_room.cz).length() > Vector2(b.cx - start_room.cx, b.cz - start_room.cz).length())
	var bot_count := 3 if deep else 4
	var bot_rooms := []
	for i in mini(bot_count, others.size()):
		var room: Dictionary = others[mini(others.size() - 1, i * 2)]
		bot_rooms.append(room)
		actors.append(Bot.new(self, dungeon.random_point_in_room(room, 1), d))

	# 몬스터와 상자
	var mul := 1.5 if deep else 1.0
	var luck := 1.2 if deep else 0.0
	for r in rooms:
		if r == start_room:
			spawn_chest(r, 0, luck)
			continue
		if r.boss:
			actors.append(Monster.new(self, "wraith_knight", dungeon.center(int(r.cx), int(r.cz)), r, mul))
			for i in 2:
				actors.append(Monster.new(self, "skeleton", dungeon.random_point_in_room(r), r, mul))
			spawn_chest(r, 2, luck + 2.5)
			spawn_chest(r, 1, luck + 1.0)
			continue
		var area: int = r.w * r.h
		var n := 0 if r in bot_rooms else mini(4, 1 + area / 18 + (1 if deep else 0))
		for i in n:
			var roll := randf()
			var type := "skeleton" if roll < 0.35 else ("skeleton_archer" if roll < 0.55 else ("goblin" if roll < 0.8 else "ghoul"))
			actors.append(Monster.new(self, type, dungeon.random_point_in_room(r), r, mul))
		spawn_chest(r, 1 if randf() < 0.25 else 0, luck)
		if area > 30 and randf() < 0.5:
			spawn_chest(r, 0, luck)


func spawn_chest(room: Dictionary, tier: int, luck: float) -> void:
	var p := Vector3.ZERO
	for k in 20:
		p = dungeon.random_point_in_room(room, 0)
		var clash := false
		for c in chests:
			if c.pos.distance_to(p) < 3.0:
				clash = true
		if not clash:
			break
	var node := Models.chest(tier)
	node.position = p
	node.rotation.y = randf() * TAU
	world.add_child(node)
	var count := 6 if tier == 2 else (randi_range(3, 4) if tier == 1 else randi_range(1, 3))
	var nm := "황금 보물상자" if tier == 2 else ("장식된 상자" if tier == 1 else "나무 상자")
	chests.append({"pos": p, "node": node, "tier": tier, "room": room, "opened": false, "items": Data.roll_loot(count, luck + tier), "name": nm, "claimed_by": null, "kind": "chest"})


# ------------------------------------------------------------------ 관계/검색
func hostile(a, b) -> bool:
	if a == b:
		return false
	if a.faction == "monster" and b.faction == "monster":
		return false
	return true


func nearest(list: Array, p: Vector3):
	var best = null
	var bd := 1e18
	for o in list:
		var d: float = o.pos.distance_squared_to(p)
		if d < bd:
			bd = d
			best = o
	return best


func exit_portals() -> Array:
	return portals.filter(func(p): return p.kind == "exit")


func dist_to_player(p: Vector3) -> float:
	return player.pos.distance_to(p) if player else 0.0


func nearest_adventurer_dist(p: Vector3) -> float:
	var bd := 1e9
	for a in actors:
		if a.kind == "monster" or not a.alive:
			continue
		var d: float = absf(a.pos.x - p.x) + absf(a.pos.z - p.z)
		if d < bd:
			bd = d
	return bd


func can_act() -> bool:
	return (force_act or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED) and not hud.is_panel_open() and not menu_open


# ------------------------------------------------------------------ 전투
func melee_hit(attacker, dmg: float, rng: float, arc: float, opts: Dictionary = {}) -> int:
	var hits := 0
	for a in actors:
		if not a.alive or a.extracted or not hostile(attacker, a):
			continue
		var dx: float = a.pos.x - attacker.pos.x
		var dz: float = a.pos.z - attacker.pos.z
		var d := sqrt(dx * dx + dz * dz)
		if d > rng + a.radius:
			continue
		if d > 0.6 and absf(angle_difference(attacker.yaw, Actor.yaw_to(dx, dz))) > arc / 2.0:
			continue
		if not dungeon.los(attacker.pos.x, attacker.pos.z, a.pos.x, a.pos.z):
			continue
		var k: float = opts.get("knock", 0.0)
		var nd := maxf(d, 0.001)
		var info := {"knock": Vector3(dx / nd * k, 0, dz / nd * k), "from": attacker.pos}
		if opts.has("stun"):
			info["stun"] = opts.stun
		a.take_damage(dmg, attacker, info)
		hits += 1
	if hits:
		Sfx.play("hit", dist_to_player(attacker.pos))
	return hits


func shoot_at(src, tgt, kind: String, dmg: float, speed: float, spread: float) -> void:
	var from := Vector3(src.pos.x, src.pos.y + src.height * 0.75, src.pos.z)
	from += Actor.fwd(src.yaw) * 0.6
	var to: Vector3 = tgt.center()
	var d := from.distance_to(to)
	to += tgt.last_vel * (d / speed) * 0.6
	var dir := (to - from).normalized()
	dir.x += randf_range(-1, 1) * spread
	dir.y += randf_range(-0.5, 0.5) * spread
	dir.z += randf_range(-1, 1) * spread
	spawn_projectile(src, kind, from, dir.normalized(), speed, dmg)


func spawn_projectile(owner, kind: String, p: Vector3, dir: Vector3, speed: float, dmg: float) -> void:
	var node: Node3D
	var gravity := 0.0
	var rad := 0.15
	match kind:
		"arrow":
			node = Models.arrow()
			gravity = 5.0
			Sfx.play("bow", dist_to_player(p))
		"bolt":
			node = Models.orb(Color(0.48, 0.42, 1.0), 0.12)
			Sfx.play("magic", dist_to_player(p))
		_:
			node = Models.orb(Color(1.0, 0.42, 0.1), 0.25)
			rad = 0.3
			Sfx.play("fire", dist_to_player(p))
	node.position = p
	world.add_child(node)
	projectiles.append({"owner": owner, "kind": kind, "node": node, "pos": p, "vel": dir * speed, "dmg": dmg, "gravity": gravity, "radius": rad, "life": 4.0, "stuck": 0.0})


func update_projectiles(dt: float) -> void:
	var i := projectiles.size() - 1
	while i >= 0:
		var p: Dictionary = projectiles[i]
		if p.stuck > 0.0:
			p.stuck -= dt
			if p.stuck <= 0.0:
				p.node.queue_free()
				projectiles.remove_at(i)
			i -= 1
			continue
		p.life -= dt
		var vel: Vector3 = p.vel
		var steps := maxi(1, int(ceil(vel.length() * dt / 0.3)))
		var sdt := dt / steps
		var done := false
		for s in steps:
			if done:
				break
			vel.y -= p.gravity * sdt
			p.pos += vel * sdt
			var pp: Vector3 = p.pos
			if dungeon.is_solid(pp.x, pp.z) or pp.y < 0.02 or pp.y > Dungeon.WALL_H - 0.05:
				done = true
				if p.kind == "fireball":
					explode(pp, 4.0, p.dmg, p.owner, "fire")
				elif p.kind == "arrow":
					p.stuck = 6.0
					p.node.position = pp
				else:
					spark(pp, Color(0.55, 0.48, 1.0))
				break
			for a in actors:
				if not a.alive or a == p.owner or a.extracted:
					continue
				if p.owner != null and not hostile(p.owner, a):
					continue
				var dx: float = a.pos.x - pp.x
				var dz: float = a.pos.z - pp.z
				if dx * dx + dz * dz > pow(a.radius + p.radius, 2):
					continue
				if pp.y < a.pos.y - 0.1 or pp.y > a.pos.y + a.height + 0.1:
					continue
				done = true
				if p.kind == "fireball":
					explode(pp, 4.0, p.dmg, p.owner, "fire")
				else:
					var head: bool = pp.y > a.pos.y + a.height * 0.82
					var vn := Vector3(vel.x, 0, vel.z).normalized()
					a.take_damage(p.dmg * (1.5 if head else 1.0), p.owner, {"knock": vn * 2.0, "from": p.owner.pos if p.owner != null else pp, "headshot": head})
					Sfx.play("hit", dist_to_player(a.pos))
					if p.kind == "bolt":
						spark(pp, Color(0.55, 0.48, 1.0))
				break
		p.vel = vel
		if (done and p.stuck <= 0.0) or p.life <= 0.0:
			p.node.queue_free()
			projectiles.remove_at(i)
			i -= 1
			continue
		p.node.position = p.pos
		if p.kind == "arrow" and vel.length_squared() > 0.01 and p.stuck <= 0.0:
			p.node.look_at(p.pos + vel, Vector3.UP)
		i -= 1


func explode(p: Vector3, rad: float, dmg: float, owner, kind: String) -> void:
	for a in actors:
		if not a.alive or a.extracted or (owner != null and not hostile(owner, a)):
			continue
		var dx: float = a.pos.x - p.x
		var dz: float = a.pos.z - p.z
		var d := sqrt(dx * dx + dz * dz)
		if d > rad + a.radius:
			continue
		if d > 1.0 and not dungeon.los(p.x - dx * 0.01, p.z - dz * 0.01, a.pos.x, a.pos.z):
			continue
		var f := 1.0 - minf(1.0, d / rad) * 0.5
		var nd := maxf(d, 0.001)
		a.take_damage(dmg * f, owner, {"knock": Vector3(dx / nd * 8.0, 0, dz / nd * 8.0), "from": p, "stun": 0.4 if kind == "slam" else 0.0})
	var color := Color(1.0, 0.42, 0.1) if kind == "fire" else Color(0.6, 0.23, 1.0)
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	m.mesh = sm
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mt.albedo_color = Color(color.r, color.g, color.b, 0.7)
	m.material_override = mt
	m.position = p if kind != "slam" else Vector3(p.x, 0.2, p.z)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(m)
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 8.0
	l.omni_range = 12.0
	l.position = p + Vector3(0, 0.5, 0)
	world.add_child(l)
	effects.append({"node": m, "light": l, "t": 0.0, "dur": 0.45, "kind": "explode", "rad": rad, "mat": mt})
	Sfx.play("fire", dist_to_player(p))
	if dist_to_player(p) < 10.0:
		player.shake = 0.3


func spark(p: Vector3, color: Color) -> void:
	var m := Models.sphere(0.3, Models.glow_mat(color, 3.0), 6)
	m.position = p
	world.add_child(m)
	effects.append({"node": m, "t": 0.0, "dur": 0.2, "kind": "spark"})


# 스킬 사용 시 퍼지는 고리 (보호막/치유 시각 효과)
func spawn_ring_burst(p: Vector3, color: Color, rad: float) -> void:
	var m := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 32
	tm.ring_segments = 4
	m.mesh = tm
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mt.albedo_color = color
	m.material_override = mt
	m.position = p
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(m)
	effects.append({"node": m, "t": 0.0, "dur": 0.6, "kind": "ring", "rad": rad, "mat": mt})


func spawn_telegraph(p: Vector3, rad: float, dur: float) -> void:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.02
	cm.radial_segments = 40
	m.mesh = cm
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.albedo_color = Color(1, 0.13, 0.13, 0.3)
	m.material_override = mt
	m.position = Vector3(p.x, 0.05, p.z)
	world.add_child(m)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = rad - 0.25
	tm.outer_radius = rad
	tm.rings = 48
	tm.ring_segments = 3
	ring.mesh = tm
	ring.material_override = Models.glow_mat(Color(1, 0.13, 0.13), 2.0)
	ring.scale = Vector3(1, 0.05, 1)
	ring.position = Vector3(p.x, 0.06, p.z)
	world.add_child(ring)
	effects.append({"node": m, "extra": ring, "t": 0.0, "dur": dur, "kind": "telegraph", "rad": rad})


func update_effects(dt: float) -> void:
	var i := effects.size() - 1
	while i >= 0:
		var e: Dictionary = effects[i]
		e.t += dt
		var k: float = minf(1.0, e.t / e.dur)
		var n: Node3D = e.node
		match e.kind:
			"explode":
				n.scale = Vector3.ONE * (0.3 + k * e.rad)
				e.mat.albedo_color.a = 0.7 * (1.0 - k)
				e.light.light_energy = 8.0 * (1.0 - k)
			"spark":
				n.scale = Vector3.ONE * (1.0 + k * 2.0)
			"ring":
				n.scale = Vector3(0.3 + k * e.rad, 1.0, 0.3 + k * e.rad)
				e.mat.albedo_color.a = 1.0 - k
			"telegraph":
				n.scale = Vector3(maxf(0.01, k) * e.rad, 1.0, maxf(0.01, k) * e.rad)
		if k >= 1.0:
			n.queue_free()
			if e.has("extra"):
				e.extra.queue_free()
			if e.has("light"):
				e.light.queue_free()
			effects.remove_at(i)
		i -= 1


func on_damage(target, dmg: float, src, blocked: bool, info: Dictionary) -> void:
	if src == player and target != player and dmg > 0.0:
		var col := Color(0.6, 0.67, 0.67) if blocked else (Color(1.0, 0.82, 0.23) if info.get("headshot", false) else Color.WHITE)
		hud.damage_number(target.center(), dmg, col)
		hud.hit_marker(target.hp <= 0.0)
	if target == player and dmg > 0.0:
		hud.hurt(dmg / player.max_hp)
		Sfx.play("hurt")
		player.interact_t = 0.0


func on_death(actor, src) -> void:
	var sname: String = src.display_name() if src != null else "어둠"
	if actor.kind != "monster" or src == player:
		hud.killfeed("%s ➜ %s" % [sname, actor.display_name()], src == player or actor == player)
	Sfx.play("death", dist_to_player(actor.pos))
	actor.windup = 0.0
	if actor.kind == "monster":
		if src == player:
			player.kills += 1
		var is_boss: bool = actor.def.boss
		var luck := (1.2 if depth > 1 else 0.0) + (3.0 if is_boss else 0.0)
		if is_boss:
			boss_dead = true
			hud.announce("망령 기사가 쓰러졌습니다", "황금 보물상자를 차지하세요")
			drop_bag(actor.pos, Data.roll_loot(5, luck), "망령 기사의 유해", Color(1, 0.8, 0.2))
		elif randf() < 0.4:
			drop_bag(actor.pos, Data.roll_loot(randi_range(1, 2), luck), actor.name + "의 유해", Color(0.42, 0.31, 0.19))
	elif actor.kind == "bot":
		if src == player:
			player.pvp_kills += 1
		drop_bag(actor.pos, actor.all_items(), actor.name + "의 시체", Color(0.2, 0.33, 0.67))
		actor.hp_bar.visible = false
	elif actor == player:
		end_raid(false, src.display_name() if src != null else "어둠")


func drop_bag(p: Vector3, items: Array, nm: String, color := Color(0.42, 0.31, 0.19)) -> void:
	if items.is_empty():
		return
	var node := Models.loot_bag(color)
	var pp := Vector3(p.x, 0, p.z)
	node.position = pp
	world.add_child(node)
	loot_bags.append({"pos": pp, "node": node, "items": items, "name": nm, "kind": "bag"})


func refresh_bag(bag: Dictionary) -> void:
	if bag.items.is_empty():
		if is_instance_valid(bag.node):
			bag.node.queue_free()
		loot_bags.erase(bag)
		if hud.container == bag:
			hud.close_container()


func open_chest(chest: Dictionary, _by) -> void:
	if chest.opened:
		return
	chest.opened = true
	Sfx.play("chest", dist_to_player(chest.pos))
	var lid: Node3D = chest.node.get_meta("lid")
	var tw := create_tween()
	tw.tween_property(lid, "rotation:x", -1.9, 0.35).set_trans(Tween.TRANS_BACK)


func bot_extract(bot) -> void:
	bot.extracted = true
	bot.alive = false
	bot.remove_from_world()
	hud.killfeed("%s 이(가) 탈출했습니다" % bot.display_name(), false, true)


# ------------------------------------------------------------------ 포탈
func spawn_portal(kind: String) -> void:
	var candidates := []
	for r in dungeon.rooms:
		if r.boss:
			continue
		var used := false
		for p in portals:
			if dungeon.room_at(p.pos.x, p.pos.z) == r:
				used = true
		if not used:
			candidates.append(r)
	if candidates.is_empty():
		return
	var room: Dictionary = candidates.pick_random()
	var p := dungeon.center(int(room.cx), int(room.cz))
	if dungeon.is_solid(p.x, p.z):
		p = dungeon.random_point_in_room(room)
	var node := Models.portal(kind)
	node.position = p
	world.add_child(node)
	portals.append({"kind": kind, "pos": p, "node": node, "life": 150.0 if kind == "descend" else INF})


func update_portals(dt: float) -> void:
	for s in portal_schedule:
		if not s.get("done", false) and level_time >= s.at:
			s["done"] = true
			for i in s.n:
				spawn_portal(s.kind)
			Sfx.play("bell")
			if s.kind == "exit":
				hud.announce("탈출 포탈이 열렸습니다", "지도(M)에서 파란 포탈 위치를 확인하세요")
			else:
				hud.announce("심연의 포탈이 열렸습니다", "붉은 포탈: 더 깊은 층으로 (더 강한 적, 더 좋은 보물)")
	var i := portals.size() - 1
	while i >= 0:
		var p: Dictionary = portals[i]
		p.life -= dt
		var spin: Node3D = p.node.get_meta("spin")
		var cp := camera.global_position
		var sp := spin.global_position
		# 카메라 쪽을 바라보게 (포탈 정중앙에 서 있으면 방향을 유지)
		if Vector2(cp.x - sp.x, cp.z - sp.z).length() > 0.2:
			spin.look_at(Vector3(cp.x, sp.y, cp.z), Vector3.UP)
			spin.rotate_object_local(Vector3.FORWARD, time)
		var dm: StandardMaterial3D = p.node.get_meta("disc")
		dm.albedo_color.a = 0.35 + sin(time * 3.0) * 0.1
		var pl: OmniLight3D = p.node.get_meta("light")
		pl.light_energy = 3.5 + sin(time * 4.0) * 0.6
		if p.life <= 0.0:
			p.node.queue_free()
			portals.remove_at(i)
			hud.toast("심연의 포탈이 닫혔습니다")
		i -= 1
	# 플레이어 탈출 채널링 (피격돼도 끊기지 않음)
	if not player.alive or result != null:
		return
	var portal = null
	for p in portals:
		if Vector2(p.pos.x - player.pos.x, p.pos.z - player.pos.z).length() < 1.8:
			portal = p
	if portal != null:
		if player.extract_t == 0.0:
			Sfx.play("portal")
		player.extract_t += dt
		hud.channel("탈출 중..." if portal.kind == "exit" else "심연으로 내려가는 중...", player.extract_t / 3.0)
		if player.extract_t >= 3.0:
			player.extract_t = 0.0
			if portal.kind == "exit":
				end_raid(true)
			else:
				descend()
	else:
		player.extract_t = 0.0


func descend() -> void:
	hud.close_container()
	time_left = maxf(time_left, 360.0)
	build_level(depth + 1)
	hud.on_level_changed()
	hud.announce("심연 2층", "적이 더 강해지고 보물이 더 값집니다")
	Sfx.play("portal")


# ------------------------------------------------------------------ 종료
func end_raid(success: bool, killer := "") -> void:
	if result != null:
		return
	var items := []
	for s in Data.GEAR_SLOTS:
		if player.equipment[s] != null:
			items.append(player.equipment[s])
	items.append_array(player.bag)
	result = {
		"success": success, "killer": killer, "items": items, "value": Data.items_value(items),
		"kills": player.kills, "pvp_kills": player.pvp_kills, "depth": depth, "time": time,
		"equipment": player.equipment, "bag": player.bag,
	}
	end_timer = 0.3 if success else 2.5
	hud.close_container()
	if success:
		Sfx.play("portal")


# ------------------------------------------------------------------ 입력
func _unhandled_input(event: InputEvent) -> void:
	if not running or player == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and player.alive:
		player.look(event.relative, sensitivity)


func fire_player_projectile(kind: String, speed: float, dmg: float, yaw_off: float) -> void:
	var b := Basis.from_euler(Vector3(camera.rotation.x, camera.rotation.y + yaw_off, 0.0), EULER_ORDER_YXZ)
	var dir := -b.z
	var from := camera.position + dir * 0.5 + Vector3(0, -0.12, 0)
	spawn_projectile(player, kind, from, dir, speed, dmg)


# 상호작용 대상 (상자, 전리품)
func find_interactable():
	var f := Actor.fwd(player.yaw)
	var best = null
	var bs := -1e9
	for list in [chests, loot_bags]:
		for o in list:
			var dx: float = o.pos.x - player.pos.x
			var dz: float = o.pos.z - player.pos.z
			var d := sqrt(dx * dx + dz * dz)
			if d > 2.6:
				continue
			var dot := (dx * f.x + dz * f.z) / maxf(d, 0.001)
			if dot < 0.2 and d > 1.3:
				continue
			var s := dot * 2.0 - d
			if s > bs:
				bs = s
				best = o
	return best


func update_interact(dt: float) -> void:
	var o = find_interactable()
	interact_target = o
	if hud.container != null and hud.container.pos.distance_to(player.pos) > 3.5:
		hud.close_container()
	if o == null or not player.alive:
		player.interact_t = 0.0
		hud.prompt("")
		return
	if o.kind == "chest" and not o.opened:
		if Input.is_action_pressed("interact") and not hud.is_panel_open() and not menu_open:
			player.interact_t += dt
			hud.channel("상자 여는 중...", player.interact_t / 1.2)
			if player.interact_t >= 1.2:
				player.interact_t = 0.0
				open_chest(o, player)
				hud.open_container(o)
		else:
			player.interact_t = 0.0
		hud.prompt("[F] 길게 눌러 %s 열기" % o.name)
	else:
		hud.prompt("[F] %s 살펴보기 (%d)" % [o.name, o.items.size()])
		if Input.is_action_just_pressed("interact") and not menu_open:
			if hud.container == o:
				hud.close_container()
			else:
				hud.open_container(o)


# ------------------------------------------------------------------ 메인 루프
func _process(delta: float) -> void:
	if not running:
		return
	var dt := minf(delta, 0.05)
	time += dt
	level_time += dt
	if result == null:
		time_left -= dt
	if time_left <= 120.0 and not warned:
		warned = true
		Sfx.play("bell")
		hud.announce("던전이 무너지고 있습니다!", "2분 안에 탈출하지 못하면 어둠에 삼켜집니다")
	if time_left <= 120.0:
		env.environment.fog_density = base_fog + (1.0 - maxf(0.0, time_left) / 120.0) * 0.06
	if time_left <= 0.0 and player.alive and result == null:
		player.hp = 0.0
		player.alive = false
		end_raid(false, "무너지는 던전")

	player.update(dt)
	update_interact(dt)
	for a in actors:
		if a != player:
			a.update(dt)
			a.last_vel = (a.pos - a.last_pos) / dt
			a.last_vel.y = 0.0
			a.last_pos = a.pos
	separate()

	# 보이지 않는 캐릭터는 그리지 않음 (멀거나 벽 너머)
	cull_t -= dt
	var do_cull := cull_t <= 0.0
	if do_cull:
		cull_t = 0.15
	var cam_pos := camera.global_position
	for a in actors:
		if a == player or a.extracted or a.node == null:
			continue
		if do_cull:
			var d: float = absf(a.pos.x - player.pos.x) + absf(a.pos.z - player.pos.z)
			a.set_visible(d < 70.0 and (d < 8.0 or dungeon.los(player.pos.x, player.pos.z, a.pos.x, a.pos.z)))
		if a.visible:
			a.animate(dt)
			a.update_hp_bar(cam_pos)
		else:
			a.node.position = a.pos

	update_projectiles(dt)
	update_effects(dt)
	for b in loot_bags:
		b.node.rotation.y += dt
	update_portals(dt)
	player.update_camera(camera, view_model, shield_bubble, dt)
	player_light.position = camera.position + Vector3(0, 0.6, 0) - Actor.fwd(player.yaw) * 0.5
	player_light.light_energy = 1.6 + sin(time * 13.0) * 0.08 + sin(time * 7.3) * 0.1
	dungeon.animate_torches(time, cam_pos)
	update_explored()
	hud.update_hud(dt)

	# 죽은 몬스터/봇 정리 (시체는 잠시 남김)
	var keep := []
	for a in actors:
		if a == player or a.alive:
			keep.append(a)
		elif a.extracted:
			continue
		elif a.death_t < (30.0 if a.kind == "bot" else 8.0):
			if not a.visible:
				a.death_t += dt
			keep.append(a)
		else:
			a.remove_from_world()
	actors = keep

	if result != null:
		end_timer -= dt
		if end_timer <= 0.0:
			running = false
			raid_ended.emit(result)


func separate() -> void:
	for i in actors.size():
		var a = actors[i]
		if not a.alive or a.extracted:
			continue
		for j in range(i + 1, actors.size()):
			var b = actors[j]
			if not b.alive or b.extracted:
				continue
			var dx: float = b.pos.x - a.pos.x
			var dz: float = b.pos.z - a.pos.z
			var mn: float = a.radius + b.radius
			var d2 := dx * dx + dz * dz
			if d2 >= mn * mn or d2 < 1e-6:
				continue
			var d := sqrt(d2)
			var push := (mn - d) / 2.0
			var nx := dx / d
			var nz := dz / d
			a.pos.x -= nx * push
			a.pos.z -= nz * push
			b.pos.x += nx * push
			b.pos.z += nz * push
	for a in actors:
		if a.alive:
			a.pos = dungeon.resolve_circle(a.pos, a.radius)


func update_explored() -> void:
	var tx := dungeon.to_tile(player.pos.x)
	var tz := dungeon.to_tile(player.pos.z)
	var R := 4
	for z in range(tz - R, tz + R + 1):
		for x in range(tx - R, tx + R + 1):
			if x < 0 or z < 0 or x >= dungeon.W or z >= dungeon.H:
				continue
			if (x - tx) * (x - tx) + (z - tz) * (z - tz) > R * R:
				continue
			explored[dungeon.idx(x, z)] = 1


# 조준 중인 대상 (이름 표시용)
func aimed_actor():
	var dir := -camera.global_transform.basis.z
	var cp := camera.global_position
	var best = null
	var bd := 30.0
	for a in actors:
		if a == player or not a.alive or a.extracted:
			continue
		var to: Vector3 = a.center() - cp
		var d := to.length()
		if d > bd:
			continue
		if to.normalized().dot(dir) < cos(atan2(a.radius + 0.3, d)):
			continue
		if not dungeon.los(cp.x, cp.z, a.pos.x, a.pos.z):
			continue
		best = a
		bd = d
	return best


func abandon() -> void:
	if result != null:
		return
	player.hp = 0.0
	player.alive = false
	end_raid(false, "포기")
	end_timer = 0.0
