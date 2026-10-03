# 레이드(던전) 진행: 월드 구성, 전투, 투사체, 이펙트, 상자, 전리품, 포탈, 붕괴
class_name Game
extends Node3D

signal raid_ended(result: Dictionary)
signal raid_over # 서버: 모든 플레이어가 탈출/사망해 레이드가 완전히 끝남

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
# 멀티플레이
var net := "offline" # offline | host | server(전용, 로컬 플레이어 없음) | client
var players: Array = [] # 사람 플레이어 (서버/오프라인)
var humans: Array = [] # 서버: 참가자 [{peer, name, cls, equipment, bag}]
var pvp := false
var level_seed := 0
var map_id := "sinners_end_1"
var fixtures: Array = [] # 지도 고정 물체: 성소(회복), 부활석, 아래층 계단
var nid_seq := 0
var bag_seq := 0
var portal_seq := 0
var proj_seq := 0
var zone_seq := 0
var snap_t := 0.0
var input_t := 0.0
var over := false
var net_actors := {} # 클라이언트: nid -> 액터
var net_proj := {} # 클라이언트: 투사체 id -> {node, pos, vel, gravity, kind, stuck}
var net_zones := {} # 클라이언트: 구역 id -> zone


func _ready() -> void:
	flash_mat = StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(1, 0.15, 0.1, 0.55)
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD


func start(lo: Dictionary, hud_node) -> void:
	loadout = lo
	if lo.has("map") and Data.MAPS.has(lo.map):
		map_id = lo.map
	hud = hud_node
	time = 0.0
	time_left = RAID_TIME
	result = null
	end_timer = -1.0
	player = null
	build_level(1)
	running = true
	if hud != null:
		hud.start(self)
		hud.announce(Data.MAPS[map_id].name, "보물을 모아 탈출 포탈로 살아 나가세요" if not online() else "%d명이 함께 입장했습니다 · %s" % [players.size(), "개인전 (서로 적)" if pvp else "파티 (서로 아군)"])


# 서버: 참가자 목록으로 레이드 생성 (host면 peer 1이 로컬 플레이어)
func start_server(mode: String, hs: Array, is_pvp: bool, hud_node, map := "") -> void:
	net = mode
	if Data.MAPS.has(map):
		map_id = map
	humans = hs
	pvp = is_pvp
	level_seed = randi() % 2000000000 + 1
	Net.game = self
	start({}, hud_node)
	for p in players:
		if p.peer_id > 1:
			Net.send_begin(p.peer_id, client_info(p))


func online() -> bool:
	return net != "offline"


func is_auth() -> bool:
	return net != "client"


func is_human(a) -> bool:
	return a != null and a.kind == "player" and a is Player


# ------------------------------------------------------------------ 이벤트 라우팅
# 위치가 있는 소리: 로컬은 거리 감쇠로 재생, 접속자에게도 전달
func sfx(n: String, p: Vector3, v := 0.06) -> void:
	if player != null and hud != null:
		Sfx.play(n, player.pos.distance_to(p), v)
	_bc("sfx", [n, p, v], false)


# 특정 플레이어의 HUD에 표시 (토스트, 피해 숫자, 피격 효과 등)
func notify(a, m: String, args: Array = []) -> void:
	if not is_human(a):
		return
	if a == player:
		if hud != null:
			hud.callv(m, args)
	elif a.peer_id > 1 and is_auth():
		Net.send_ev(a.peer_id, "hud", [m, args])


func notify_all(m: String, args: Array = []) -> void:
	if hud != null:
		hud.callv(m, args)
	_bc("hud", [m, args])


# 서버 -> 레이드 중인 모든 클라이언트
func _bc(n: String, args: Array, reliable := true) -> void:
	if net != "host" and net != "server":
		return
	for p in players:
		if p.peer_id > 1 and not p.done:
			Net.send_ev(p.peer_id, n, args, reliable)


func add_actor(a) -> void:
	nid_seq += 1
	a.nid = nid_seq
	actors.append(a)
	if running and online() and is_auth():
		_bc("actor_add", [describe(a)])
	if net == "host" and is_human(a) and a != player:
		a.puppet = NetActor.new(self, describe(a))


# 클라이언트가 대리 액터를 만들 때 필요한 정보
func describe(a) -> Dictionary:
	var d := {"id": a.nid, "k": a.kind, "n": a.name if a.kind == "player" else a.display_name(), "f": a.faction,
		"p": a.pos, "y": a.yaw, "mh": a.max_hp, "r": a.radius, "h": a.height}
	match a.kind:
		"monster":
			d["t"] = a.type
		"player", "bot":
			d["c"] = a.cls
			d["w"] = Data.weapon_model(a.cls, a.equipment, a.wset)
			d["hm"] = a.equipment.head != null
	return d


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
	_make_env(deep)

	if online():
		seed(level_seed + d)
	dungeon = Dungeon.new(d, level_seed + d if online() else 0, map_id)
	dungeon.build(world, false)
	_reset_lists(d)
	_spawn_fixtures()

	var mdef: Dictionary = Data.MAPS.get(map_id, Data.MAPS[Data.MAP_ORDER[0]])
	var rooms: Array = dungeon.rooms
	var boss_room = null
	for r in rooms:
		if r.boss:
			boss_room = r
	# 시작 위치: 지도에 정해진 스폰 지점 (섞어서 배정)
	var spawns: Array = dungeon.marks.spawns.duplicate()
	spawns.shuffle()
	var spawn_at := func(i: int, k: int) -> Vector3:
		var t: Vector2i = spawns[i % spawns.size()]
		var c := dungeon.center(t.x, t.y)
		# 같은 지점의 파티원은 조금씩 떨어뜨림
		var off := Vector3(cos(k * 2.1), 0, sin(k * 2.1)) * (1.2 if k > 0 else 0.0)
		return dungeon.resolve_circle(c + off, 0.5)
	var used_spawns := 0
	var used_rooms := []
	if players.is_empty():
		if humans.is_empty():
			player = Player.new(self, spawn_at.call(0, 0), loadout.cls, loadout.equipment, loadout.bag, "당신", "player", 0, loadout.get("skills", {}), int(loadout.get("wset", 1)))
			player.char_id = loadout.get("char", "")
			player.name = loadout.get("name", "당신")
			players = [player]
			used_spawns = 1
		else:
			# 개인전: 각자 다른 스폰 지점 · 파티: 같은 스폰 지점에 함께
			var i := 0
			for h in humans:
				var si := i if pvp else 0
				var p := Player.new(self, spawn_at.call(si, 0 if pvp else i), h.cls, h.equipment, h.bag, h.name, ("player_%d" % h.peer) if pvp else "player", h.peer, h.get("skills", {}), int(h.get("wset", 1)))
				p.char_id = h.get("char", "")
				players.append(p)
				if h.peer == 1 and net == "host":
					player = p
				i += 1
			used_spawns = humans.size() if pvp else 1
	else:
		player.pos = spawn_at.call(0, 0)
		used_spawns = 1
	for p in players:
		var rr = dungeon.room_at(p.pos.x, p.pos.z)
		if rr != null and not (rr in used_rooms):
			used_rooms.append(rr)
		# 시작할 때 가장 가까운 열린 쪽을 바라봄
		p.yaw = randf() * TAU
		add_actor(p)
	if player != null:
		_make_view()

	# 다른 모험가 팀(봇): 남은 스폰 지점
	var bot_count := 4
	if online():
		bot_count = maxi(1, bot_count - (players.size() - 1))
	for k in mini(bot_count, maxi(0, spawns.size() - used_spawns)):
		var bp: Vector3 = spawn_at.call(used_spawns + k, 0)
		var rr = dungeon.room_at(bp.x, bp.z)
		if rr != null:
			used_rooms.append(rr)
		add_actor(Bot.new(self, bp, d))

	# 몬스터와 상자 (지도별 출현 몬스터 가중치)
	var mul := 1.5 if d > 1 else 1.0
	var luck := 1.2 if d > 1 else 0.0
	var pool: Dictionary = mdef.monsters
	var total := 0.0
	for k in pool:
		total += float(pool[k])
	var pick := func() -> String:
		var r := randf() * total
		for k in pool:
			r -= float(pool[k])
			if r <= 0.0:
				return k
		return pool.keys()[0]
	var elites: Array = mdef.get("elites", [])
	var normal := rooms.filter(func(r): return not r.boss and not (r in used_rooms))
	normal.shuffle()
	var elite_rooms := normal.slice(0, mini(2, normal.size()))
	# 시작 지점 근처 방에는 몬스터를 두지 않음 (입장하자마자 싸우지 않도록)
	var starts := []
	for a in actors:
		if is_adventurer(a):
			starts.append(Vector2(a.pos.x, a.pos.z) / Dungeon.T)
	for r in rooms:
		var near_start := false
		for sp in starts:
			if sp.distance_to(Vector2(r.cx, r.cz)) < 4.0:
				near_start = true
		if near_start and not r.boss and not (r in used_rooms):
			used_rooms.append(r)
	for r in rooms:
		var area: int = r.tiles.size() if r.has("tiles") else r.w * r.h
		if r in used_rooms:
			spawn_chest(r, 0, luck)
			continue
		if r.boss:
			add_actor(Monster.new(self, mdef.boss, dungeon.center(int(r.cx), int(r.cz)), r, mul))
			for i in 2:
				add_actor(Monster.new(self, pick.call(), dungeon.random_point_in_room(r), r, mul))
			spawn_chest(r, 2, luck + 2.5)
			spawn_chest(r, 1, luck + 1.0)
			continue
		if r in elite_rooms and elites.size():
			add_actor(Monster.new(self, elites.pick_random(), dungeon.random_point_in_room(r), r, mul))
		var n := mini(4, 1 + area / 16)
		for i in n:
			var t: String = pick.call()
			add_actor(Monster.new(self, t, dungeon.random_point_in_room(r), r, mul))
		# 상자 (일부는 미믹)
		if randf() < float(mdef.get("mimic", 0.0)):
			add_actor(Monster.new(self, "mimic", dungeon.random_point_in_room(r, 0), r, mul))
		else:
			spawn_chest(r, 1 if randf() < 0.25 else 0, luck)
		if area > 30 and randf() < 0.4:
			spawn_chest(r, 0, luck)
	if online():
		randomize()


func _reset_lists(d: int) -> void:
	explored = PackedByteArray()
	explored.resize(dungeon.W * dungeon.H)
	actors = []
	projectiles = []
	zones = []
	effects = []
	chests = []
	loot_bags = []
	portals = []
	if d > 1:
		portal_schedule = [{"at": 45.0, "kind": "exit", "n": 2}, {"at": 200.0, "kind": "exit", "n": 2}]
	elif online():
		# 함께하기: 심연 포탈 없이 탈출 포탈만
		portal_schedule = [{"at": 120.0, "kind": "exit", "n": 2}, {"at": 330.0, "kind": "exit", "n": 2}, {"at": 600.0, "kind": "exit", "n": 2}]
	else:
		portal_schedule = [
			{"at": 120.0, "kind": "exit", "n": 2},
			{"at": 400.0, "kind": "exit", "n": 2},
			{"at": 640.0, "kind": "exit", "n": 1},
		]


# 카메라, 손전등, 1인칭 뷰모델 (로컬 플레이어가 있을 때만)
func _make_view() -> void:
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 90.0
	world.add_child(camera)
	camera.make_current()
	# 플레이어 횃불(손전등 역할) - 그림자로 입체감
	player_light = OmniLight3D.new()
	player_light.light_color = Color(1.0, 0.72, 0.45)
	player_light.light_energy = 1.3
	player_light.omni_range = 16.0
	player_light.omni_attenuation = 1.3
	player_light.shadow_enabled = shadows_enabled()
	player_light.shadow_bias = 0.08
	world.add_child(player_light)
	view_model = Models.view_model(player.cls, Data.weapon_model(player.cls, player.equipment, player.wset), player.panther)
	camera.add_child(view_model)
	shield_bubble = Models.shield_bubble(0.75)
	shield_bubble.visible = false
	camera.add_child(shield_bubble)


func _make_env(deep: bool) -> void:
	# 환경: 어두운 배경, 안개, 글로우, 톤매핑
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.005, 0.004) if deep else Color(0.008, 0.008, 0.01)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.32, 0.18, 0.16) if deep else Color(0.24, 0.22, 0.26)
	e.ambient_light_energy = 0.42
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


# ------------------------------------------------------------------ 지도 고정 물체
# 성소: 길게 눌러 체력 회복(1회) · 부활석: 쓰러진 파티원 부활 · 계단: 아래층 (2층 준비 중)
func _spawn_fixtures() -> void:
	fixtures = []
	var shrines: Array = dungeon.marks.shrines
	if shrines.is_empty():
		var rr := RandomNumberGenerator.new()
		rr.seed = hash(map_id + "shrine")
		shrines = dungeon._spread_points(8, dungeon.marks.spawns, rr)
	var add := func(kind: String, t: Vector2i) -> void:
		var p := dungeon.center(t.x, t.y)
		var node := Models.fixture(kind)
		node.position = p
		world.add_child(node)
		var nm: String = {"shrine": "회복의 성소", "stone": "부활석", "stairs": "아래층 계단"}[kind]
		fixtures.append({"id": fixtures.size(), "kind": kind, "pos": p, "node": node, "used": false, "name": nm})
	for t in shrines:
		add.call("shrine", t)
	for t in dungeon.marks.stones:
		add.call("stone", t)
	for t in dungeon.marks.descent:
		add.call("stairs", t)


func _fixture_used(id: int) -> void:
	if id < 0 or id >= fixtures.size():
		return
	var f: Dictionary = fixtures[id]
	f.used = true
	if is_instance_valid(f.node):
		Models.fixture_spent(f.node)


func _use_fixture(p, f: Dictionary) -> void:
	match f.kind:
		"shrine":
			if f.used:
				return
			p.apply_heal(p.max_hp * 0.5, 2.0)
			p.dots.clear()
			p.burn = 0
			_fixture_used(f.id)
			_bc("fix_used", [f.id])
			spawn_ring_burst(f.pos + Vector3(0, 0.4, 0), Color(0.5, 1.0, 0.6), 2.5)
			sfx("heal", f.pos)
			notify(p, "toast", ["성소의 축복: 체력 회복"])
		"stone":
			var best = null
			for q in players:
				if q != p and not q.alive and not q.done and q.revive_wait > 0.0 and q.faction == p.faction:
					best = q
			if best == null:
				notify(p, "toast", ["부활시킬 파티원이 없습니다"])
				return
			best.pos = dungeon.resolve_circle(f.pos + Vector3(1.2, 0, 0), best.radius)
			revive_player(best, p)
			spawn_ring_burst(f.pos + Vector3(0, 0.4, 0), Skills.GOLD, 3.0)
		"stairs":
			notify(p, "toast", ["2층은 준비 중입니다"])


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
	var pk := Inv.pack_container(Data.roll_loot(count, luck + tier))
	chests.append({"id": chests.size(), "pos": p, "rot": node.rotation.y, "node": node, "tier": tier, "room": room, "opened": false, "items": pk.items, "gw": pk.gw, "gh": pk.gh, "name": nm, "claimed_by": null, "kind": "chest"})


# ------------------------------------------------------------------ 관계/검색
func is_adventurer(a) -> bool:
	return a != null and a.kind in ["player", "bot"]


# 던전본: 파티원도 무기에 맞는다. '신중' 패시브가 있으면 서로 피해 없음
func friendly_fire(a, b) -> bool:
	if not is_adventurer(a) or not is_adventurer(b) or a == b or a.faction != b.faction:
		return false
	return not (Skills.has_fx(a, "careful") or Skills.has_fx(b, "careful"))


# 모든 공격 피해의 관문: 치명타, 은신 일격, 광기의 포효, 약점, 패시브/고유 효과
func hit(src, a, dmg: float, info: Dictionary = {}) -> float:
	if a == null or not a.alive:
		return 0.0
	var hero: bool = src != null and src.is_hero()
	var crit := false
	var stealthed: bool = hero and src.stealth > 0.0
	if hero:
		if info.get("weapon", false):
			dmg += src.stats.get("lightning_add", 0.0) + src.stats.get("cold_add", 0.0)
		if not info.get("dot", false) and info.get("can_crit", true):
			var ch: float = src.stats.get("crit", 0.05)
			if src.pursuit_t > 0.0:
				ch += 0.5
			if src.hp >= src.max_hp - 0.5:
				ch += src.stats.get("crit_full", 0.0)
			if src.counter_ready and info.get("melee", false):
				crit = true
				src.counter_ready = false
			elif randf() < ch:
				crit = true
			if crit:
				var cm: float = src.stats.get("crit_mul", 1.5)
				if stealthed and src.cls == "rogue":
					cm += 0.6
				dmg *= cm
		if src.warcry_t > 0.0:
			dmg *= 1.3
	if a.kind == "monster" and a.def.get("weak", "") != "" and a.def.weak == info.get("dtype", "phys"):
		dmg *= 2.5
	info["crit"] = crit
	var dealt: float = a.take_damage(dmg, src, info)
	if not hero:
		return dealt
	if dealt > 0.0:
		var ls: float = src.stats.get("lifesteal", 0.0) + (0.3 if src.warcry_t > 0.0 else 0.0) + (0.5 if stealthed and Skills.has_fx(src, "ambush") else 0.0)
		if ls > 0.0:
			src.heal_now(dealt * ls)
		if src.warcry_t > 0.0 and info.get("weapon", false) and Skills.has_fx(src, "hamstring"):
			a.add_slow(1.5, 0.8)
		if stealthed and Skills.has_fx(src, "hidden_poison") and not info.get("blocked", false):
			a.add_dot(50.0, 3.0, src)
		if src.petrify_coat > 0.0 and info.get("weapon", false) and a != src:
			src.petrify_coat = 0.0
			a.petrify(4.0)
			notify(src, "toast", ["석화!"])
			spawn_ring_burst(a.pos + Vector3(0, 1.0, 0), Color(0.6, 0.6, 0.6), 1.5)
		if info.get("dtype", "") == "cold" and Skills.has_fx(src, "frost_scale"):
			src.frost_scale = mini(100, src.frost_scale + 1)
		# 서리의 메아리: 눈보라 안의 적을 아군이 때리면 40 영구 실드
		var echo = a.get_meta("blizz_owner") if a.has_meta("blizz_owner") else null
		if echo != null and is_instance_valid_actor(echo) and Skills.has_fx(echo, "frost_echo") and float(a.get_meta("blizz_t", 0.0)) > time and not info.get("blocked", false):
			if src.faction == echo.faction and src.shield < 40.0:
				src.give_shield(40.0, 9999.0, Skills.FROST)
		var u: Array = src.stats.get("uniques", [])
		if info.get("melee", false):
			if "elf_speed" in u and src.get_meta("elf_cd", 0.0) <= time:
				src.set_meta("elf_cd", time + 8.0)
				src.add_speed(150.0, 3.0, true)
			if "grove_slow" in u:
				a.add_slow(1.0, 0.2)
				src.add_slow(1.0, 0.4)
			if "lifesteal_stack" in u:
				src.heal_now(dealt * 0.03 * mini(10, int(src.get_meta("ls_stack", 0)) + 1))
				src.set_meta("ls_stack", mini(10, int(src.get_meta("ls_stack", 0)) + 1))
	if crit:
		if Skills.has_fx(src, "faith_mp"):
			Skills.gain(src, 5.0)
		if Skills.has_fx(src, "endless_chill"):
			Skills.gain(src, 1.0)
		if info.get("psionic", false) and Skills.has_fx(src, "hobble"):
			a.add_speed(-60.0, 5.0)
	if info.get("psionic", false) and dealt > 0.0:
		if Skills.has_fx(src, "pursuit"):
			src.pursuit_t = 5.0
		if Skills.has_fx(src, "healing_sheath") and not info.get("blocked", false):
			src.heal_now(30.0)
	if stealthed and not info.get("dot", false):
		src.break_stealth()
	return dealt


func is_instance_valid_actor(a) -> bool:
	return a != null and a is Actor


func hostile(a, b) -> bool:
	if a == b or a.faction == b.faction:
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
	return player.pos.distance_to(p) if player else 999.0


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
		hit(attacker, a, dmg, info)
		hits += 1
	if hits:
		sfx("hit", attacker.pos)
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


# 투사체 종류별 외형/색
const PROJ_COLORS := {
	"bolt": Color(0.48, 0.42, 1.0), "firebolt": Color(1.0, 0.45, 0.12), "pyroblast": Color(1.0, 0.4, 0.08),
	"icebolt": Color(0.6, 0.9, 1.0), "thorn": Color(0.45, 0.95, 0.35), "poison": Color(0.4, 0.95, 0.2),
	"grasp": Color(0.35, 0.95, 0.55), "blade": Color(0.55, 0.75, 1.0), "fireball": Color(1.0, 0.42, 0.1),
	"holy": Color(1.0, 0.9, 0.5), "spit": Color(0.6, 0.9, 0.2), "magic_orb": Color(0.9, 0.3, 0.9),
}


# extra: homing(선회 강도), slow(초), aoe(반경), root(초), dot(초당 피해), pull, heal_owner, gravity, life
func spawn_projectile(owner, kind: String, p: Vector3, dir: Vector3, speed: float, dmg: float, extra: Dictionary = {}) -> void:
	var gravity: float = extra.get("gravity", 0.0)
	var rad := 0.15
	match kind:
		"arrow", "bolt":
			gravity = 5.0 if kind == "arrow" else 1.5
			sfx("bow", p)
		"knife":
			gravity = 3.0
			sfx("swing", p)
		"blade":
			pass
		"pyroblast", "fireball":
			rad = 0.45
			sfx("fire", p)
		"poison":
			pass
		_:
			sfx("magic", p)
	var node := _proj_node(kind)
	node.position = p
	world.add_child(node)
	proj_seq += 1
	var pr := {"id": proj_seq, "owner": owner, "kind": kind, "node": node, "pos": p, "vel": dir * speed, "speed": speed, "dmg": dmg,
		"gravity": gravity, "radius": rad, "life": extra.get("life", 4.0), "stuck": 0.0, "tgt": null, "retarget": 0.0}
	pr.merge(extra)
	projectiles.append(pr)


func _proj_node(kind: String) -> Node3D:
	var node: Node3D
	var color: Color = PROJ_COLORS.get(kind, Color.WHITE)
	match kind:
		"arrow", "bolt":
			node = Models.arrow()
		"knife":
			node = Models.weapon("dagger")
			node.scale = Vector3.ONE * 0.8
		"blade":
			node = Models.weapon("longsword")
			node.scale = Vector3.ONE * 0.6
			for m in node.find_children("*", "GeometryInstance3D", true, false):
				(m as GeometryInstance3D).material_overlay = Models.glow_mat(Color(0.4, 0.6, 1.0, 0.5), 1.5)
		"pyroblast", "fireball":
			node = Models.orb(color, 0.42)
		"poison":
			node = Models.orb(color, 0.16, false)
		_:
			node = Models.orb(color, 0.13, kind != "thorn")
	return node


func _orient_proj(node: Node3D, kind: String, p: Vector3, vel: Vector3) -> void:
	if kind in ["arrow", "knife", "blade"] and vel.length_squared() > 0.01:
		node.look_at(p + vel, Vector3.UP if absf(vel.normalized().y) < 0.95 else Vector3.RIGHT)
		if kind != "arrow":
			node.rotate_object_local(Vector3.RIGHT, -PI / 2)


# 유도 투사체의 표적 (전방, 시야 내, 은신 제외)
func _homing_target(p: Dictionary):
	var best = null
	var bs := 1e9
	var v: Vector3 = p.vel.normalized()
	for a in actors:
		if not a.alive or a.extracted or a == p.owner or (p.owner != null and not hostile(p.owner, a)):
			continue
		var to: Vector3 = a.center() - p.pos
		var d := to.length()
		if d > 30.0 or (a.stealth > 0.0 and d > 3.0):
			continue
		if to.normalized().dot(v) < 0.35:
			continue
		if not dungeon.los(p.pos.x, p.pos.z, a.pos.x, a.pos.z):
			continue
		var score := d * (2.0 - to.normalized().dot(v))
		if score < bs:
			bs = score
			best = a
	return best


func _projectile_impact(p: Dictionary, pp: Vector3, hit) -> void:
	var owner = p.owner
	if p.get("aoe", 0.0) > 0.0:
		var kind := "fire" if p.get("fire_aoe", false) or p.kind != "poison" else "poison"
		explode(pp, p.aoe, p.dmg, owner, kind, {"root": p.get("root", 0.0), "dot": p.get("dot", 0.0), "burn": p.get("burn", 0), "dtype": p.get("dtype", "fire")})
		return
	if hit == null:
		spark(pp, PROJ_COLORS.get(p.kind, Color(0.55, 0.48, 1.0)))
		return
	var a = hit
	var head: bool = pp.y > a.pos.y + a.height * 0.82
	var vel: Vector3 = p.vel
	var vn := Vector3(vel.x, 0, vel.z).normalized()
	var info := {"knock": vn * 2.0, "from": owner.pos if owner != null else pp, "headshot": head, "ranged": true,
		"dtype": p.get("dtype", "phys"), "psionic": p.get("psionic", false), "weapon": p.get("weapon", false)}
	if p.get("pull", false) and owner != null:
		# 영혼의 족쇄: 시전자 앞 2m까지 끌어당김
		var to: Vector3 = owner.pos - a.pos
		to.y = 0.0
		var dist := maxf(0.0, to.length() - 2.0)
		info["knock"] = to.normalized() * dist * 8.0
		if hostile(owner, a):
			Skills.gain(owner, p.get("soul_gain", 10.0))
	var pdmg: float = p.dmg * (1.5 if head else 1.0)
	if p.get("far_bonus", false) and owner != null:
		var fd: float = owner.pos.distance_to(a.pos)
		if fd > 15.0:
			pdmg *= 1.0 + minf(0.3, (fd - 15.0) / 10.0 * 0.3)
	hit(owner, a, pdmg, info)
	if p.get("slow", 0.0) > 0.0:
		a.add_slow(p.slow, p.get("slow_mul", 0.55))
	if p.get("curse", false) and owner != null:
		a.curse_t = 10.0
		a.curse_src = owner
		a.curse_dps = 10.32 * owner.dmg_mul() * (1.0 + (0.3 if p.get("far_bonus", false) and owner.pos.distance_to(a.pos) > 25.0 else 0.0))
	if p.get("heal_owner", 0.0) > 0.0 and owner != null:
		owner.heal_now(p.heal_owner)
	sfx("hit", a.pos)
	if p.kind != "arrow" and p.kind != "knife":
		spark(pp, PROJ_COLORS.get(p.kind, Color(0.55, 0.48, 1.0)))


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
		# 유도
		if p.get("homing", 0.0) > 0.0:
			p.retarget -= dt
			if p.retarget <= 0.0 or p.tgt == null or not p.tgt.alive:
				p.retarget = 0.2
				p.tgt = _homing_target(p)
			if p.tgt != null:
				var want: Vector3 = (p.tgt.center() - p.pos).normalized()
				vel = vel.normalized().lerp(want, minf(1.0, p.homing * dt)).normalized() * p.speed
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
				p.vel = vel
				if p.kind in ["arrow", "knife"]:
					p.stuck = 6.0
					p.node.position = pp
				else:
					_projectile_impact(p, pp, null)
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
				p.vel = vel
				_projectile_impact(p, pp, a)
				break
		p.vel = vel
		if (done and p.stuck <= 0.0) or p.life <= 0.0:
			if not done and p.get("aoe", 0.0) > 0.0:
				_projectile_impact(p, p.pos, null)
			p.node.queue_free()
			projectiles.remove_at(i)
			i -= 1
			continue
		p.node.position = p.pos
		if p.stuck <= 0.0:
			_orient_proj(p.node, p.kind, p.pos, vel)
		i -= 1


# extra: root(초), dot(초당 피해, 4초)
func explode(p: Vector3, rad: float, dmg: float, owner, kind: String, extra: Dictionary = {}) -> void:
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
		var kp := 2.0 if kind == "poison" else 8.0
		hit(owner, a, dmg * f, {"knock": Vector3(dx / nd * kp, 0, dz / nd * kp), "from": p, "stun": 0.4 if kind == "slam" else 0.0, "dtype": extra.get("dtype", "fire" if kind == "fire" else "phys"), "ranged": true})
		if extra.get("burn", 0) > 0:
			a.add_burn(int(extra.burn), owner)
		if extra.get("root", 0.0) > 0.0:
			a.add_root(extra.root)
		if extra.get("dot", 0.0) > 0.0:
			a.add_dot(extra.dot, 4.0, owner)
	var color := Color(1.0, 0.42, 0.1)
	match kind:
		"slam":
			color = Color(0.6, 0.23, 1.0)
		"poison":
			color = Color(0.35, 0.9, 0.2)
	explode_fx(p if kind != "slam" else Vector3(p.x, 0.2, p.z), rad, color)
	sfx("fire" if kind != "poison" else "magic", p)
	if kind != "poison":
		for h in players:
			if h.pos.distance_to(p) < 10.0:
				notify(h, "shake", [0.3])


# 폭발 시각 효과만 (피해 없음)
func explode_fx(p: Vector3, rad: float, color: Color) -> void:
	_bc("explode_fx", [p, rad, color])
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
	m.position = p
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(m)
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 8.0
	l.omni_range = 12.0
	l.position = p + Vector3(0, 0.5, 0)
	world.add_child(l)
	effects.append({"node": m, "light": l, "t": 0.0, "dur": 0.45, "kind": "explode", "rad": rad, "mat": mt})


# 조준선이 벽/바닥에 닿는 지점 (얼음 폭풍 위치)
func aim_point(origin: Vector3, dir: Vector3, max_d: float) -> Vector3:
	var p := origin
	var d := 0.0
	while d < max_d:
		var n := p + dir * 0.25
		if dungeon.is_solid(n.x, n.z) or n.y <= 0.0:
			break
		p = n
		d += 0.25
	return Vector3(p.x, 0.0, p.z)


# ------------------------------------------------------------------ 지속 지역 효과 (얼음 폭풍, 영혼의 장막, 회오리 검)
var zones: Array = []


func add_zone(z: Dictionary) -> void:
	z["t"] = z.get("dur", 3.0)
	z["tick_t"] = 0.0
	zone_seq += 1
	z["id"] = zone_seq
	if not z.has("pos"):
		z["pos"] = z.follow.pos
	var node := _zone_node(z)
	node.position = z.pos
	world.add_child(node)
	z["node"] = node
	zones.append(z)


func _zone_node(z: Dictionary) -> Node3D:
	var node := Node3D.new()
	match z.kind:
		"ice_storm":
			var disc := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = z.radius
			cm.bottom_radius = z.radius
			cm.height = 3.5
			cm.radial_segments = 32
			disc.mesh = cm
			var mt := StandardMaterial3D.new()
			mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mt.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mt.albedo_color = Color(0.45, 0.75, 1.0, 0.18)
			mt.cull_mode = BaseMaterial3D.CULL_DISABLED
			disc.material_override = mt
			disc.position.y = 1.75
			node.add_child(disc)
			var parts := CPUParticles3D.new()
			parts.amount = 120
			parts.lifetime = 0.8
			parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			parts.emission_box_extents = Vector3(z.radius * 0.8, 0.1, z.radius * 0.8)
			parts.position.y = 3.6
			parts.direction = Vector3.DOWN
			parts.spread = 10.0
			parts.gravity = Vector3(0, -6, 0)
			parts.initial_velocity_min = 3.0
			parts.initial_velocity_max = 5.0
			var pm := BoxMesh.new()
			pm.size = Vector3(0.05, 0.18, 0.05)
			pm.material = Models.glow_mat(Color(0.75, 0.92, 1.0), 2.0)
			parts.mesh = pm
			node.add_child(parts)
			var l := OmniLight3D.new()
			l.light_color = Color(0.5, 0.8, 1.0)
			l.light_energy = 2.5
			l.omni_range = z.radius * 2.0
			l.position.y = 2.0
			node.add_child(l)
		"soul_shroud":
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = z.radius - 0.3
			tm.outer_radius = z.radius
			tm.rings = 48
			tm.ring_segments = 3
			ring.mesh = tm
			ring.material_override = Models.glow_mat(Color(0.55, 0.2, 0.9), 2.5)
			ring.scale = Vector3(1, 0.08, 1)
			ring.position.y = 0.1
			node.add_child(ring)
			var parts := CPUParticles3D.new()
			parts.amount = 50
			parts.lifetime = 1.2
			parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			parts.emission_ring_axis = Vector3.UP
			parts.emission_ring_radius = z.radius
			parts.emission_ring_inner_radius = 0.5
			parts.emission_ring_height = 0.1
			parts.direction = Vector3.UP
			parts.gravity = Vector3(0, 1.0, 0)
			parts.initial_velocity_min = 0.5
			parts.initial_velocity_max = 1.2
			var pm := SphereMesh.new()
			pm.radius = 0.06
			pm.height = 0.12
			pm.radial_segments = 4
			pm.rings = 2
			pm.material = Models.glow_mat(Color(0.5, 0.15, 0.85), 4.0)
			parts.mesh = pm
			node.add_child(parts)
		"orbit_blade":
			var pivot := Node3D.new()
			pivot.name = "Pivot"
			var blade := Models.weapon("longsword")
			blade.rotation = Vector3(0, 0, PI / 2)
			blade.position = Vector3(z.radius * 0.7, 1.1, 0)
			blade.scale = Vector3.ONE * 0.8
			for m in blade.find_children("*", "GeometryInstance3D", true, false):
				(m as GeometryInstance3D).material_overlay = Models.glow_mat(Color(0.4, 0.6, 1.0, 0.5), 1.5)
			pivot.add_child(blade)
			node.add_child(pivot)
		"revelation":
			var pillar := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = z.radius
			cm.bottom_radius = z.radius
			cm.height = 0.1
			cm.radial_segments = 32
			pillar.mesh = cm
			pillar.material_override = Models.glow_mat(Color(1.0, 0.85, 0.4, 0.35), 2.0)
			pillar.position.y = 0.06
			node.add_child(pillar)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.85, 0.5)
			l.light_energy = 3.0
			l.omni_range = z.radius * 2.0
			l.position.y = 2.0
			node.add_child(l)
		"soul_storm":
			var parts := CPUParticles3D.new()
			parts.amount = 80
			parts.lifetime = 0.9
			parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			parts.emission_ring_axis = Vector3.UP
			parts.emission_ring_radius = z.radius
			parts.emission_ring_inner_radius = 1.0
			parts.emission_ring_height = 1.5
			parts.direction = Vector3.UP
			parts.gravity = Vector3(0, 2.0, 0)
			parts.initial_velocity_min = 0.5
			parts.initial_velocity_max = 2.0
			parts.orbit_velocity_min = 0.4
			parts.orbit_velocity_max = 0.8
			var pm := SphereMesh.new()
			pm.radius = 0.08
			pm.height = 0.16
			pm.radial_segments = 4
			pm.rings = 2
			pm.material = Models.glow_mat(Skills.SOUL, 4.0)
			parts.mesh = pm
			parts.position.y = 0.6
			node.add_child(parts)
		"fire_eye":
			var pivot := Node3D.new()
			pivot.name = "Pivot"
			var eye := Models.orb(Skills.FIRE, 0.25)
			eye.position = Vector3(1.4, 1.8, 0)
			pivot.add_child(eye)
			node.add_child(pivot)
	return node


func update_zones(dt: float) -> void:
	var i := zones.size() - 1
	while i >= 0:
		var z: Dictionary = zones[i]
		z.t -= dt
		var follow = z.get("follow")
		if follow != null:
			if not follow.alive:
				z.t = 0.0
			else:
				z.pos = follow.pos
		# 눈보라: 조준 지점으로 이동하다가 채널링이 끝나면 제자리에서 펼쳐짐
		if z.has("move_to") and not z.get("expanded", false):
			z["move_t"] = z.get("move_t", 0.0) + dt
			var to: Vector3 = z.move_to - z.pos
			to.y = 0.0
			var step: float = z.speed * dt
			if to.length() > step:
				var np: Vector3 = z.pos + to.normalized() * step
				if not dungeon.is_solid(np.x, np.z):
					z.pos = np
			if to.length() <= step or z.move_t >= z.get("move_dur", 3.0) or z.owner == null or not z.owner.alive:
				z.expanded = true
				z.radius = z.end_radius
				z.dmg = z.end_dmg
				z.slow_mul = z.end_slow_mul
				z.t = minf(z.t, 3.0)
				z.node.scale = Vector3.ONE * (z.end_radius / 2.5)
		var node: Node3D = z.node
		node.position = z.pos
		if z.kind == "orbit_blade" or z.kind == "fire_eye":
			node.get_node("Pivot").rotation.y += dt * (9.0 if z.kind == "orbit_blade" else 3.0)
		if z.get("delay", 0.0) > 0.0:
			z.delay -= dt
			if z.t <= 0.0:
				node.queue_free()
				zones.remove_at(i)
			i -= 1
			continue
		z.tick_t -= dt
		if z.tick_t <= 0.0 and z.t > 0.0:
			z.tick_t = z.get("tick", 0.5)
			_zone_tick(z)
			if z.get("once", false):
				z.t = minf(z.t, 0.25)
		if z.t <= 0.0:
			node.queue_free()
			zones.remove_at(i)
		i -= 1


func _zone_tick(z: Dictionary) -> void:
	var owner = z.owner
	var hits := 0
	var cands := []
	for a in actors:
		if not a.alive or a.extracted:
			continue
		var d: float = Vector2(a.pos.x - z.pos.x, a.pos.z - z.pos.z).length()
		if d > z.radius + a.radius or not dungeon.los(z.pos.x, z.pos.z, a.pos.x, a.pos.z):
			continue
		if owner != null and not hostile(owner, a):
			# 아군 치유 (신의 계시)
			if z.get("heal", 0.0) > 0.0 and (a == owner or (a.faction == owner.faction and is_adventurer(a))):
				a.apply_heal(z.heal, 0.4)
			continue
		cands.append([d, a])
	if z.get("nearest", false) and cands.size() > 1:
		cands.sort_custom(func(x, y): return x[0] < y[0])
		cands = [cands[0]]
	for c in cands:
		var a = c[1]
		if z.get("dmg", 0.0) > 0.0:
			hit(owner, a, z.dmg, {"from": z.pos, "ranged": true, "dtype": z.get("dtype", "phys"), "can_crit": z.kind != "soul_storm"})
		if z.get("slow", 0.0) > 0.0:
			a.add_slow(z.slow, z.get("slow_mul", 0.5))
		if z.get("burn", 0) > 0:
			a.add_burn(int(z.burn), owner)
		if z.get("blizzard", false):
			a.set_meta("blizz_owner", owner)
			a.set_meta("blizz_t", time + 0.8)
		hits += 1
	if hits and z.kind in ["orbit_blade", "revelation"]:
		sfx("hit", z.pos, 0.2)
	if z.kind == "revelation":
		spawn_ring_burst(z.pos + Vector3(0, 0.3, 0), Skills.GOLD, z.radius)


func end_zone(owner, kind: String) -> void:
	for z in zones:
		if z.owner == owner and z.kind == kind:
			z.t = 0.0


# ------------------------------------------------------------------ 직업 스킬 연동
func spawn_summon(owner, p: Vector3) -> void:
	var s := Summon.new(self, owner, p, 98.37 * owner.dmg_mul())
	add_actor(s)
	spawn_ring_burst(p + Vector3(0, 0.2, 0), Skills.NATURE, 2.5)


# 드루이드가 그림자 돌격으로 때린 적을 나무 정령이 즉시 공격
func summon_focus(c) -> void:
	for a in actors:
		if a.kind == "summon" and a.alive and a.owner_actor == c:
			var best = null
			var bd := 8.0
			for e in actors:
				if e.alive and hostile(c, e) and e.pos.distance_to(c.pos) < 3.5 and e.pos.distance_to(a.pos) < bd:
					bd = e.pos.distance_to(a.pos)
					best = e
			if best != null:
				a.target = best
				a.atk_cd = 0.0


# 부활 (프리스트 '부활' 패시브 또는 부활석)
func revive_player(t, by) -> void:
	if t.alive or t.done:
		return
	t.alive = true
	t.hp = t.max_hp * 0.3
	t.revive_wait = 0.0
	t.death_t = 0.0
	spawn_ring_burst(t.pos + Vector3(0, 0.5, 0), Skills.GOLD, 3.0)
	sfx("heal", t.pos)
	notify(t, "toast", ["%s 님이 부활시켰습니다" % (by.name if by != null else "부활석")])
	notify(t, "revived", [])
	for h in players:
		notify(h, "killfeed", ["%s 부활" % t.name, false, true])


# ------------------------------------------------------------------ 영혼 에너지볼 (데스나이트/크라이오맨서)
var soul_orbs: Array = []
var orb_seq := 0


func spawn_soul_orb(p: Vector3) -> void:
	orb_seq += 1
	_add_orb_node(orb_seq, p)
	_bc("orb_add", [orb_seq, p])


func _add_orb_node(id: int, p: Vector3) -> void:
	var m := Models.sphere(0.22, Models.glow_mat(Skills.SOUL, 3.0), 8)
	m.position = Vector3(p.x, 1.0, p.z)
	world.add_child(m)
	soul_orbs.append({"id": id, "pos": Vector3(p.x, 0, p.z), "node": m, "life": 60.0})


func update_soul_orbs(dt: float) -> void:
	var i := soul_orbs.size() - 1
	while i >= 0:
		var o: Dictionary = soul_orbs[i]
		o.life -= dt
		o.node.position.y = 1.0 + sin(time * 3.0 + o.id) * 0.15
		var taken := false
		if is_auth():
			for a in actors:
				if a.alive and not a.extracted and a.is_hero() and a.res_type() == "soul" and a.pos.distance_to(o.pos) < 2.6:
					Skills.gain(a, 15.0)
					if Skills.has_fx(a, "life_drain"):
						a.heal_now(14.0)
					notify(a, "sfx", ["magic"])
					taken = true
					break
		if taken or (o.life <= 0.0 and is_auth()):
			o.node.queue_free()
			soul_orbs.remove_at(i)
			_bc("orb_del", [o.id])
		i -= 1


# 드루이드 변신: 플레이어는 뷰모델 교체, AI는 모델 전환 (AIActor.active_rig)
func on_shapeshift(c) -> void:
	if c == player:
		_rebuild_view_model()
	if is_auth():
		spawn_ring_burst(c.pos + Vector3(0, 0.5, 0), Skills.NATURE, 2.0)


func on_weapon_changed(c = null) -> void:
	if c == null or c == player:
		_rebuild_view_model()


func _rebuild_view_model() -> void:
	if camera == null or player == null:
		return
	if view_model != null and is_instance_valid(view_model):
		view_model.queue_free()
	view_model = Models.view_model(player.cls, Data.weapon_model(player.cls, player.equipment, player.wset), player.panther)
	camera.add_child(view_model)


# 서리 장벽: 얼음 덩어리를 시전자 위치에 3초간 표시
func on_frozen(c) -> void:
	_bc("frozen_fx", [c.nid, c.frozen])
	var ice := Models.ice_block(c.height + 0.4)
	var holder := Node3D.new()
	holder.add_child(ice)
	holder.position = c.pos
	world.add_child(holder)
	effects.append({"node": holder, "t": 0.0, "dur": c.frozen, "kind": "ice", "follow": c})


func spark(p: Vector3, color: Color) -> void:
	_bc("spark", [p, color], false)
	var m := Models.sphere(0.3, Models.glow_mat(color, 3.0), 6)
	m.position = p
	world.add_child(m)
	effects.append({"node": m, "t": 0.0, "dur": 0.2, "kind": "spark"})


# 스킬 사용 시 퍼지는 고리 (보호막/치유 시각 효과)
func spawn_ring_burst(p: Vector3, color: Color, rad: float) -> void:
	_bc("spawn_ring_burst", [p, color, rad])
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
	_bc("spawn_telegraph", [p, rad, dur])
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
			"ice":
				if e.follow == null:
					k = 1.0
				else:
					n.position = e.follow.pos
				if not e.follow.alive or e.follow.frozen <= 0.0:
					k = 1.0
		if k >= 1.0:
			n.queue_free()
			if e.has("extra"):
				e.extra.queue_free()
			if e.has("light"):
				e.light.queue_free()
			effects.remove_at(i)
		i -= 1




func on_damage(target, dmg: float, src, blocked: bool, info: Dictionary) -> void:
	if is_human(src) and target != src and dmg > 0.0:
		var col := Color(0.6, 0.67, 0.67) if blocked else (Color(1.0, 0.82, 0.23) if info.get("headshot", false) else Color.WHITE)
		notify(src, "damage_number", [target.center(), dmg, col])
		notify(src, "hit_marker", [target.hp <= 0.0])
	if is_human(target) and dmg > 0.0:
		notify(target, "hurt", [dmg / target.max_hp])
		notify(target, "sfx", ["hurt"])
		target.interact_t = 0.0


func on_death(actor, src) -> void:
	if actor.kind == "summon":
		spawn_ring_burst(actor.pos + Vector3(0, 0.3, 0), Skills.NATURE, 2.0)
		return
	var sname: String = src.display_name() if src != null else "어둠"
	if actor.kind != "monster" or is_human(src):
		for h in players:
			if actor.kind != "monster" or src == h:
				notify(h, "killfeed", ["%s ➜ %s" % [sname if src != h else "당신", actor.display_name() if actor != h else "당신"], src == h or actor == h])
	sfx("death", actor.pos)
	actor.windup = 0.0
	if actor.kind in ["player", "bot"] or (actor.kind == "monster" and actor.def.get("ai", "") != "harmless"):
		spawn_soul_orb(actor.pos)
	_kill_hooks(actor, src)
	if actor.kind == "monster":
		if is_human(src):
			src.kills += 1
		var is_boss: bool = actor.def.boss
		var luck := (1.2 if depth > 1 else 0.0) + (3.0 if is_boss else 0.0)
		if is_boss:
			boss_dead = true
			notify_all("announce", ["%s 처치!" % actor.name, "보스의 전리품이 떨어졌습니다"])
			drop_items(actor.pos, Data.roll_loot(5, luck))
		elif randf() < 0.4:
			drop_items(actor.pos, Data.roll_loot(randi_range(1, 2), luck))
	elif actor.kind == "bot":
		if is_human(src):
			src.pvp_kills += 1
		drop_bag(actor.pos, actor.all_items(), actor.name + "의 시체", Color(0.2, 0.33, 0.67))
		actor.hp_bar.visible = false
	elif is_human(actor):
		if is_human(src) and src != actor:
			src.pvp_kills += 1
		# 파티 플레이: 살아 있는 파티원이 있으면 20초 동안 부활을 기다림
		var ally_alive := false
		if online() and not pvp:
			for h in players:
				if h != actor and not h.done and h.alive and h.faction == actor.faction:
					ally_alive = true
		if ally_alive:
			actor.revive_wait = 20.0
			actor.killer_name = src.display_name() if src != null else "어둠"
			notify(actor, "toast", ["쓰러졌습니다 - 20초 안에 파티원이 부활시킬 수 있습니다"])
		else:
			finish_player(actor, false, src.display_name() if src != null else "어둠")


# 처치 시 효과: 처치 시 생명력, 미다스의 손, 직업 패시브(흥분/화환 갱신/사신/암살), 실수
func _kill_hooks(actor, src) -> void:
	if src == null or not src.is_hero() or src == actor:
		return
	var st: Dictionary = src.stats
	if st.get("life_on_kill", 0.0) > 0.0:
		src.heal_now(st.life_on_kill)
	if Data.set_tier(st, "midas") >= 1 and src.get("bag") != null:
		var coins := Data.make_item("gold_coins")
		coins.count = 30
		Inv.add_auto(src.bag, Inv.bag_size(src.cls), coins)
		inv_changed(src)
	if Skills.has_fx(src, "assassinate"):
		Skills.enter_stealth(src, 6.0)
	if is_adventurer(actor):
		var e_id := Skills.skill_id(src, "e")
		if Skills.has_fx(src, "excite") and e_id == "fighter_inspire":
			src.cd.e = 0.0
		if Skills.has_fx(src, "wreath") and e_id == "pyro_fireshock":
			src.cd.e = 0.0
		if Skills.has_fx(src, "reaper") and e_id == "dk_soul_chain":
			src.cd.e = 0.0
		if "mistake" in st.get("uniques", []):
			src.hp = src.max_hp


func drop_bag(p: Vector3, items: Array, nm: String, color := Color(0.42, 0.31, 0.19)) -> void:
	if items.is_empty():
		return
	var pp := Vector3(p.x, 0, p.z)
	bag_seq += 1
	var b := _add_bag_node(bag_seq, pp, color, nm)
	var pk := Inv.pack_container(items)
	b["items"] = pk.items
	b["gw"] = pk.gw
	b["gh"] = pk.gh
	_bc("bag_add", [bag_seq, pp, color, nm, items.size()])


# 바닥에 아이템 하나를 떨어뜨림 (아이템 모양 + 등급 빛줄기, F로 줍기)
func drop_item(p: Vector3, it: Dictionary, scatter := 0.0) -> void:
	var pp := Vector3(p.x, 0, p.z)
	if scatter > 0.0:
		for _i in 6:
			var q := pp + Vector3(randf_range(-scatter, scatter), 0, randf_range(-scatter, scatter))
			if not dungeon.is_solid(q.x, q.z):
				pp = q
				break
	bag_seq += 1
	var b := _add_item_node(bag_seq, pp, str(it.base), int(it.get("rarity", 0)))
	b.items = [it]
	b.n = 1
	_bc("item_add", [bag_seq, pp, str(it.base), int(it.get("rarity", 0))])


func drop_items(p: Vector3, items: Array) -> void:
	for it in items:
		drop_item(p, it, 1.2 if items.size() > 1 else 0.4)


func _add_item_node(id: int, pp: Vector3, base_id: String, rar: int) -> Dictionary:
	var node := Models.ground_item(base_id, rar)
	node.position = pp
	world.add_child(node)
	var nm: String = Data.ITEM_BASES.get(base_id, {}).get("name", "아이템")
	var b := {"id": id, "pos": pp, "node": node, "items": [], "name": nm, "kind": "item", "n": 1, "rarity": rar}
	loot_bags.append(b)
	return b


func pickup_item(p, o: Dictionary) -> void:
	if o.items.is_empty():
		return
	var it: Dictionary = o.items[0]
	if not Inv.add_auto(p.bag, Inv.bag_size(p.cls), it):
		notify(p, "toast", ["가방에 자리가 없습니다"])
		return
	o.items.clear()
	notify(p, "sfx", ["pickup"])
	refresh_bag(o)
	p.recalc()
	inv_changed(p)


func _add_bag_node(id: int, pp: Vector3, color: Color, nm: String) -> Dictionary:
	var node := Models.loot_bag(color)
	node.position = pp
	world.add_child(node)
	var b := {"id": id, "pos": pp, "node": node, "items": [], "name": nm, "kind": "bag", "n": 0}
	loot_bags.append(b)
	return b


func refresh_bag(bag: Dictionary) -> void:
	if bag.items.is_empty():
		if is_instance_valid(bag.node):
			bag.node.queue_free()
		loot_bags.erase(bag)
		for p in players:
			if p.container == bag:
				close_container_for(p)
		_bc("bag_del", [bag.id])
	else:
		_bc("bag_n", [bag.id, bag.items.size()])


func open_chest(chest: Dictionary, _by) -> void:
	if chest.opened:
		return
	chest.opened = true
	sfx("chest", chest.pos)
	_bc("chest_open", [chest.id])
	_chest_lid(chest)


func _chest_lid(chest: Dictionary) -> void:
	var lid: Node3D = chest.node.get_meta("lid")
	var tw := create_tween()
	tw.tween_property(lid, "rotation:x", -1.9, 0.35).set_trans(Tween.TRANS_BACK)


func bot_extract(bot) -> void:
	bot.extracted = true
	bot.alive = false
	bot.remove_from_world()
	_bc("actor_del", [bot.nid])
	for h in players:
		notify(h, "killfeed", ["%s 이(가) 탈출했습니다" % bot.display_name(), false, true])


# ------------------------------------------------------------------ 상자/전리품 창 (서버 측, 플레이어별)
func cont_view(o: Dictionary) -> Dictionary:
	return {"cid": ("c%d" if o.kind == "chest" else "b%d") % o.id, "id": o.id, "name": o.name, "items": o.items, "pos": o.pos, "kind": o.kind, "gw": o.get("gw", Inv.CONT_W), "gh": o.get("gh", 8)}


func open_container_for(p, o: Dictionary) -> void:
	p.container = o
	if p == player:
		if hud != null:
			hud.open_container(o)
	elif p.peer_id > 1:
		Net.send_ev(p.peer_id, "cont_open", [cont_view(o)])


func close_container_for(p) -> void:
	if p.container == null:
		return
	p.container = null
	if p == player:
		if hud != null:
			hud.close_container(false)
	elif p.peer_id > 1:
		Net.send_ev(p.peer_id, "cont_close", [])


func container_changed(o: Dictionary) -> void:
	for p in players:
		if p.container == o:
			if p == player:
				if hud != null:
					hud.refresh_panels()
			elif p.peer_id > 1:
				Net.send_ev(p.peer_id, "cont_upd", [cont_view(o)])
	if o.kind == "bag":
		refresh_bag(o)


func inv_changed(p) -> void:
	if p == player:
		if hud != null:
			hud.refresh_panels()
	elif p is Player and p.peer_id > 1 and is_auth():
		Net.send_ev(p.peer_id, "inv", [p.equipment, p.bag, p.wset])


# HUD의 인벤토리 조작 요청 (클라이언트는 서버로 보냄)
func request_inv(op: String, args: Array = []) -> void:
	if is_auth():
		if player != null:
			inv_op(player, op, args)
	else:
		Net.send_inv(op, args)


# 레이드 중 인벤토리 조작 (서버 권한). 저장소: bag(가방), equip(장비), cont(열린 상자/전리품)
func _ctx_of(p) -> Dictionary:
	var stores := {"bag": {"list": p.bag, "grid": Inv.bag_size(p.cls)}}
	if p.container != null:
		stores["cont"] = {"list": p.container.items, "grid": Vector2i(p.container.get("gw", Inv.CONT_W), p.container.get("gh", 8))}
	return {"cls": p.cls, "equipment": p.equipment, "stores": stores}


func inv_op(p, op: String, args: Array) -> void:
	if p.done and op != "close":
		return
	var res := {}
	match op:
		"close":
			close_container_for(p)
			return
		"abandon":
			if not p.done:
				p.hp = 0.0
				p.alive = false
				finish_player(p, false, "포기")
			return
		"move":
			# [src, id, dst, x, y, r, slot]
			if args.size() < 6:
				return
			res = Inv.move(_ctx_of(p), str(args[0]), str(args[1]), str(args[2]), int(args[3]), int(args[4]), bool(args[5]), str(args[6]) if args.size() > 6 else "")
		"quick":
			if args.size() < 2:
				return
			var src := str(args[0])
			var it = Inv._peek(_ctx_of(p), src, str(args[1]))
			if it == null:
				return
			# 가방의 소모품은 오른쪽 클릭으로 사용
			if src == "bag" and Data.base_of(it).slot == "consumable":
				_use_item(p, it)
				return
			var order := ["bag"] if src != "bag" else ["cont"]
			res = Inv.quick(_ctx_of(p), src, it.id, order)
		"transfer":
			if args.size() < 2:
				return
			var src := str(args[0])
			# 던전본처럼: 상자가 열려 있지 않으면 Shift+클릭 = 바닥에 버리기
			if src != "cont" and p.container == null:
				inv_op(p, "drop", args)
				return
			res = Inv.transfer(_ctx_of(p), src, str(args[1]), ["cont", "bag"] if src == "equip" else (["bag"] if src == "cont" else ["cont"]))
		"use":
			var i := Inv.index_of(p.bag, str(args[0]) if args.size() else "")
			if i >= 0:
				_use_item(p, p.bag[i])
			return
		"drop":
			# 바닥에 버리기 [src, id]
			if args.size() < 2:
				return
			var ctx := _ctx_of(p)
			var it = Inv._peek(ctx, str(args[0]), str(args[1]))
			if it == null or str(args[0]) == "cont":
				return
			Inv._take(ctx, str(args[0]), it.id)
			drop_item(p.pos + Actor.fwd(p.yaw) * 1.1, it, 0.3)
			notify(p, "sfx", ["drop"])
			res = {"ok": true}
		"take_all":
			var c = p.container
			if c == null:
				return
			var items: Array = c.items.duplicate()
			items.sort_custom(func(a, b): return a.value > b.value)
			var n := 0
			for it in items:
				var r := Inv.move(_ctx_of(p), "cont", it.id, "bag", -1, 0, false)
				if r.ok:
					n += 1
			if n < items.size():
				notify(p, "toast", ["가방에 자리가 없습니다"])
			if n > 0:
				notify(p, "sfx", ["coin"])
			res = {"ok": n > 0}
	if res.get("msg", "") != "":
		notify(p, "toast", [res.msg])
	if res.get("ok", false):
		if op in ["move", "quick", "transfer"]:
			notify(p, "sfx", ["pickup"])
		p.recalc()
		if p.container != null:
			container_changed(p.container)
	inv_changed(p)


func _use_item(p, it: Dictionary) -> void:
	if p.hp >= p.max_hp:
		notify(p, "toast", ["체력이 가득 찼습니다"])
	elif p.alive and p.cd.potion <= 0.0:
		p.use_consumable(it.id)


# ------------------------------------------------------------------ 포탈
func spawn_portal(kind: String) -> void:
	# 지도에 정해진 탈출 지점이 있으면 먼저 사용
	if kind == "exit":
		for t in dungeon.marks.exits:
			var ep := dungeon.center(t.x, t.y)
			var taken := false
			for p in portals:
				if p.pos.distance_to(ep) < 4.0:
					taken = true
			if not taken:
				portal_seq += 1
				_add_portal_node(portal_seq, kind, ep)
				_bc("portal_add", [portal_seq, kind, ep])
				return
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
	portal_seq += 1
	_add_portal_node(portal_seq, kind, p)
	_bc("portal_add", [portal_seq, kind, p])


func _add_portal_node(id: int, kind: String, p: Vector3) -> void:
	var node := Models.portal(kind)
	node.position = p
	world.add_child(node)
	portals.append({"id": id, "kind": kind, "pos": p, "node": node, "life": 150.0 if kind == "descend" else INF})


func _animate_portals(dt: float) -> void:
	var i := portals.size() - 1
	while i >= 0:
		var p: Dictionary = portals[i]
		p.life -= dt
		var spin: Node3D = p.node.get_meta("spin")
		if camera != null:
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
		if p.life <= 0.0 and is_auth():
			p.node.queue_free()
			portals.remove_at(i)
			_bc("portal_del", [p.id])
			if hud != null:
				hud.toast("심연의 포탈이 닫혔습니다")
		i -= 1


func update_portals(dt: float) -> void:
	for s in portal_schedule:
		if not s.get("done", false) and level_time >= s.at:
			s["done"] = true
			for i in s.n:
				spawn_portal(s.kind)
			notify_all("sfx", ["bell"])
			if s.kind == "exit":
				notify_all("announce", ["탈출 포탈이 열렸습니다", "지도(M)에서 파란 포탈 위치를 확인하세요"])
			else:
				notify_all("announce", ["심연의 포탈이 열렸습니다", "붉은 포탈: 더 깊은 층으로 (더 강한 적, 더 좋은 보물)"])
	_animate_portals(dt)
	# 플레이어 탈출 채널링 (피격돼도 끊기지 않음)
	for pl in players:
		if pl.done or not pl.alive:
			continue
		var portal = null
		for p in portals:
			if Vector2(p.pos.x - pl.pos.x, p.pos.z - pl.pos.z).length() < 1.8:
				portal = p
		if portal != null:
			if pl.extract_t == 0.0:
				notify(pl, "sfx", ["portal"])
			pl.extract_t += dt
			channel_for(pl, "탈출 중..." if portal.kind == "exit" else "심연으로 내려가는 중...", pl.extract_t / 3.0)
			if pl.extract_t >= 3.0:
				pl.extract_t = 0.0
				if portal.kind == "exit" or online():
					finish_player(pl, true)
				else:
					descend()
					return
		else:
			pl.extract_t = 0.0


func channel_for(p, text: String, k: float) -> void:
	if p == player:
		if hud != null:
			hud.channel(text, k)
	else:
		p.ch = [text, k]


func descend() -> void:
	hud.close_container()
	time_left = maxf(time_left, 360.0)
	build_level(depth + 1)
	hud.on_level_changed()
	hud.announce("심연 2층", "적이 더 강해지고 보물이 더 값집니다")
	Sfx.play("portal")


# ------------------------------------------------------------------ 종료
# 플레이어 한 명의 레이드 종료 (탈출 성공 / 사망). 모두 끝나면 레이드 종료
func finish_player(p, success: bool, killer := "") -> void:
	if p.done:
		return
	p.done = true
	var items := []
	for s in Data.ALL_SLOTS:
		if p.equipment[s] != null:
			items.append(p.equipment[s])
	items.append_array(p.bag)
	var r := {
		"success": success, "killer": killer, "items": items, "value": Data.items_value(items),
		"kills": p.kills, "pvp_kills": p.pvp_kills, "depth": depth, "time": time, "char": p.char_id,
		"equipment": p.equipment, "bag": p.bag,
	}
	close_container_for(p)
	if success:
		p.extracted = true
		if p.puppet != null:
			p.puppet.remove_from_world()
		_bc("actor_del", [p.nid])
		for h in players:
			if h != p:
				notify(h, "killfeed", ["%s 이(가) 탈출했습니다" % p.name, false, true])
	elif online() and items.size():
		# 함께하기: 쓰러진 자리에 소지품이 떨어져 다른 사람이 주울 수 있음
		drop_bag(p.pos, items.duplicate(true), "%s의 시체" % p.name, Color(0.55, 0.25, 0.2))
	if p == player:
		result = r
		end_timer = 0.3 if success else 2.5
		if hud != null:
			hud.close_container(false)
		if success:
			Sfx.play("portal")
	elif p.peer_id > 1:
		Net.send_ev(p.peer_id, "result", [r])
		Net.on_player_result(p.peer_id, r)
		Net.player_left_raid(p.peer_id)
	var all_done := true
	for h in players:
		if not h.done:
			all_done = false
	if all_done:
		over = true


func end_raid(success: bool, killer := "") -> void:
	if player != null:
		finish_player(player, success, killer)


# 접속이 끊긴 친구는 사망 처리
func on_peer_left(id: int) -> void:
	for p in players:
		if p.peer_id == id and not p.done:
			p.hp = 0.0
			p.alive = false
			finish_player(p, false, "연결 끊김")


# ------------------------------------------------------------------ 입력
func _unhandled_input(event: InputEvent) -> void:
	if not running or player == null or hud == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and player.alive and not player.done:
		player.look(event.relative, sensitivity)


# 상호작용 대상 (상자, 전리품)
func find_interactable(pl = null):
	if pl == null:
		pl = player
	var f := Actor.fwd(pl.yaw)
	var best = null
	var bs := -1e9
	for list in [chests, loot_bags, fixtures]:
		for o in list:
			var dx: float = o.pos.x - pl.pos.x
			var dz: float = o.pos.z - pl.pos.z
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


func _item_count(o: Dictionary) -> int:
	return o.items.size() if is_auth() else int(o.get("n", 0))


func _prompt_for(o) -> String:
	if o == null:
		return ""
	if o.kind == "chest" and not o.opened:
		return "[F] 길게 눌러 %s 열기" % o.name
	if o.kind == "item":
		return "[F] 줍기: %s" % o.name
	match o.kind:
		"shrine":
			return "%s (사용함)" % o.name if o.used else "[F] 길게 눌러 %s 사용 (체력 회복)" % o.name
		"stone":
			return "[F] 길게 눌러 %s 사용 (쓰러진 파티원 부활)" % o.name
		"stairs":
			return "%s — 2층 준비 중" % o.name
	return "[F] %s 살펴보기 (%d)" % [o.name, _item_count(o)]


func update_interact(dt: float) -> void:
	for p in players:
		if not p.done:
			_interact_for(p, dt)


func _interact_for(p, dt: float) -> void:
	var o = find_interactable(p)
	var local: bool = p == player
	if local:
		interact_target = o
	if p.container != null and p.container.pos.distance_to(p.pos) > 3.5:
		close_container_for(p)
	var panel: bool = (hud != null and hud.is_panel_open()) or menu_open if local else p.inp.panel
	var menu: bool = menu_open if local else false
	# F: 열린 창이 있으면 닫기
	if p.inp.just_pressed("interact") and p.container != null and not menu:
		close_container_for(p)
		p.interact_t = 0.0
		if local and hud != null:
			hud.prompt(_prompt_for(o))
		return
	if o == null or not p.alive:
		p.interact_t = 0.0
		if local and hud != null:
			hud.prompt("")
		return
	if local and hud != null:
		hud.prompt(_prompt_for(o))
	if o.kind in ["shrine", "stone"] and not o.get("used", false):
		if p.inp.pressed("interact") and not panel and not menu:
			p.interact_t += dt
			var need := 1.5 if o.kind == "shrine" else 3.0
			channel_for(p, "%s 사용 중..." % o.name, p.interact_t / need)
			if p.interact_t >= need:
				p.interact_t = 0.0
				if is_auth():
					_use_fixture(p, o)
		else:
			p.interact_t = 0.0
	elif o.kind in ["shrine", "stone", "stairs"]:
		if p.inp.just_pressed("interact") and o.kind == "stairs" and is_auth():
			_use_fixture(p, o)
	elif o.kind == "chest" and not o.opened:
		if p.inp.pressed("interact") and not panel and not menu:
			p.interact_t += dt
			channel_for(p, "상자 여는 중...", p.interact_t / 1.2)
			if p.interact_t >= 1.2:
				p.interact_t = 0.0
				open_chest(o, p)
				open_container_for(p, o)
		else:
			p.interact_t = 0.0
	elif p.inp.just_pressed("interact") and not menu:
		if o.kind == "item":
			if is_auth():
				pickup_item(p, o)
		else:
			open_container_for(p, o)


# ------------------------------------------------------------------ 메인 루프
func _process(delta: float) -> void:
	if not running:
		return
	var dt := minf(delta, 0.05)
	if net == "client":
		_process_client(dt)
		return
	time += dt
	level_time += dt
	if not over:
		time_left -= dt
	if time_left <= 120.0 and not warned:
		warned = true
		notify_all("sfx", ["bell"])
		notify_all("announce", ["던전이 무너지고 있습니다!", "2분 안에 탈출하지 못하면 어둠에 삼켜집니다"])
	if time_left <= 120.0:
		env.environment.fog_density = base_fog + (1.0 - maxf(0.0, time_left) / 120.0) * 0.06
	if time_left <= 0.0:
		for p in players:
			if not p.done:
				p.hp = 0.0
				p.alive = false
				finish_player(p, false, "무너지는 던전")

	for p in players:
		if not p.extracted:
			p.update(dt)
	update_interact(dt)
	for a in actors:
		if a.kind != "player":
			a.update(dt)
			a.last_vel = (a.pos - a.last_pos) / dt
			a.last_vel.y = 0.0
			a.last_pos = a.pos
	separate()
	_draw_actors(dt)
	update_projectiles(dt)
	update_zones(dt)
	update_effects(dt)
	update_soul_orbs(dt)
	for b in loot_bags:
		b.node.rotation.y += dt
	update_portals(dt)
	_update_revive_wait(dt)
	_update_view(dt)

	# 죽은 몬스터/봇 정리 (시체는 잠시 남김)
	var keep := []
	for a in actors:
		if a.kind == "player" or a.alive:
			keep.append(a)
		elif a.extracted:
			continue
		elif a.death_t < (30.0 if a.kind == "bot" else 8.0):
			if not a.visible:
				a.death_t += dt
			keep.append(a)
		else:
			a.remove_from_world()
			_bc("actor_del", [a.nid])
	actors = keep

	if online():
		snap_t -= dt
		if snap_t <= 0.0:
			snap_t = 0.05
			_send_snapshots()

	if result != null and end_timer >= 0.0:
		end_timer -= dt
		if end_timer <= 0.0:
			end_timer = -1.0
			raid_ended.emit(result)
			if net == "offline":
				running = false
	# 함께하기: 모두 끝났고 내 결과 화면도 넘어갔으면 레이드 종료
	if over and net != "offline" and (player == null or (result != null and end_timer < 0.0)):
		_finish_raid()


# 쓰러진 파티원: 부활 대기 시간이 끝나면 사망 처리
func _update_revive_wait(dt: float) -> void:
	for p in players:
		if not p.alive and not p.done and p.revive_wait > 0.0:
			p.revive_wait -= dt
			channel_for(p, "부활 대기 중... 파티원이 부활석이나 '부활'로 살릴 수 있습니다", p.revive_wait / 20.0)
			if p.revive_wait <= 0.0:
				finish_player(p, false, p.killer_name)


func _finish_raid() -> void:
	if not running:
		return
	running = false
	Net.raid_finished()
	raid_over.emit()


# 캐릭터 표시: 보이지 않는 캐릭터는 그리지 않음 (멀거나 벽 너머)
func _draw_actors(dt: float) -> void:
	cull_t -= dt
	var do_cull := cull_t <= 0.0
	if do_cull:
		cull_t = 0.15
	var cam_pos := camera.global_position if camera != null else Vector3.ZERO
	var viewer = player
	for a in actors:
		if a == player or a.extracted:
			continue
		var v = a if a is AIActor else a.puppet
		if v == null or v.node == null:
			continue
		if v != a:
			v.mirror(a)
		if viewer == null:
			if v.visible:
				v.set_visible(false)
			continue
		if do_cull:
			var d: float = absf(a.pos.x - viewer.pos.x) + absf(a.pos.z - viewer.pos.z)
			v.set_visible(d < 70.0 and (d < 8.0 or dungeon.los(viewer.pos.x, viewer.pos.z, a.pos.x, a.pos.z)))
		if v.visible:
			v.animate(dt)
			v.update_hp_bar(cam_pos)
		else:
			v.node.position = a.pos


func _update_view(dt: float) -> void:
	if player == null or camera == null or hud == null:
		return
	player.update_camera(camera, view_model, shield_bubble, dt)
	player_light.position = camera.position + Vector3(0, 0.6, 0) - Actor.fwd(player.yaw) * 0.5
	player_light.light_energy = 1.3 + sin(time * 13.0) * 0.08 + sin(time * 7.3) * 0.1
	dungeon.animate_torches(time, camera.global_position)
	update_explored()
	hud.update_hud(dt)


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
		if a.stealth > 0.0 and a.pos.distance_to(player.pos) > 4.0:
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
	if net == "client":
		Net.send_inv("abandon", [])
		return
	player.hp = 0.0
	player.alive = false
	finish_player(player, false, "포기")
	end_timer = 0.0


# ------------------------------------------------------------------ 멀티플레이: 서버
func _player_by_peer(id: int):
	for p in players:
		if p.peer_id == id:
			return p
	return null


func net_input(id: int, p: Vector3, yaw: float, pitch: float, bits: int, can_act_flag: bool, panel: bool) -> void:
	var pl = _player_by_peer(id)
	if pl == null or pl.done:
		return
	pl.net_pos = p
	pl.has_net = true
	if pl.alive and pl.frozen <= 0.0:
		pl.yaw = yaw
		pl.pitch = clampf(pitch, -1.5, 1.5)
	pl.inp.set_held_bits(bits)
	pl.inp.can_act = can_act_flag
	pl.inp.panel = panel


func net_press(id: int, action: String) -> void:
	var pl = _player_by_peer(id)
	if pl != null and action in InputState.PRESS:
		pl.inp.push_press(action)


func net_inv(id: int, op: String, args: Array) -> void:
	var pl = _player_by_peer(id)
	if pl != null:
		inv_op(pl, op, args)


# 스냅샷 한 줄 (float 10개): id, x, y, z, yaw, hp, flags, move, windup_k, attack
const ACT_STRIDE := 10
const PROJ_STRIDE := 10
const PROJ_KINDS := ["arrow", "knife", "blade", "bolt", "firebolt", "pyroblast", "icebolt", "thorn", "poison", "grasp", "fireball", "holy", "spit", "magic_orb"]


func _pack_actor(out: PackedFloat32Array, a) -> void:
	var f := 0
	if a.alive:
		f |= 1
	if a.get("aim_anim") == true:
		f |= 2
	if a.blocking:
		f |= 4
	if a.panther:
		f |= 8
	if a.spin_t > 0.0:
		f |= 16
	if a.stealth > 0.0:
		f |= 32
	if a.hit_flash > 0.0:
		f |= 64
	var mv: float = a.move_amt
	var atk: float = a.attack_anim
	if a is Player:
		mv = 1.0 if a.moving else 0.0
		atk = 0.25 if a.swing != null and a.swing.t < 0.1 else 0.0
	var wk: float = (1.0 - a.windup / a.windup_max) if a.windup > 0.0 else -1.0
	out.append_array([a.nid, a.pos.x, a.pos.y, a.pos.z, a.yaw, a.hp, f, mv, wk, atk])


# 서버 -> 각 클라이언트 (초당 20회). UDP 한 패킷(MTU)에 들어가도록 액터를 나눠 보냄
func _send_snapshots() -> void:
	var zs := []
	for z in zones:
		zs.append([z.id, z.kind, z.pos, z.radius])
	for pl in players:
		if pl.peer_id <= 1 or pl.done:
			continue
		var acts := PackedFloat32Array()
		for a in actors:
			if a == pl or a.extracted:
				continue
			if absf(a.pos.x - pl.pos.x) + absf(a.pos.z - pl.pos.z) > 75.0 and a.kind != "player":
				continue
			_pack_actor(acts, a)
		var first := ACT_STRIDE * 10
		var per := ACT_STRIDE * 28
		# 투사체: 가까운 것부터 최대 28개 (별도 패킷)
		var near := projectiles.filter(func(p): return absf(p.pos.x - pl.pos.x) + absf(p.pos.z - pl.pos.z) < 70.0)
		if near.size() > 28:
			near.sort_custom(func(a, b): return a.pos.distance_squared_to(pl.pos) < b.pos.distance_squared_to(pl.pos))
			near.resize(28)
		var projs := PackedFloat32Array()
		for p in near:
			projs.append_array([p.id, PROJ_KINDS.find(p.kind), p.pos.x, p.pos.y, p.pos.z, p.vel.x, p.vel.y, p.vel.z, 1.0 if p.stuck > 0.0 else 0.0, p.gravity])
		Net.send_snap(pl.peer_id, {"t": time_left, "a": acts.slice(0, first), "z": zs}, pl.net_state())
		Net.send_projs(pl.peer_id, projs)
		var i := first
		while i < acts.size():
			Net.send_acts(pl.peer_id, acts.slice(i, i + per))
			i += per
		pl.ch = []


# 클라이언트에게 보내는 레이드 시작 정보
func client_info(p) -> Dictionary:
	var acts := []
	for a in actors:
		if a != p:
			acts.append(describe(a))
	var cs := []
	for c in chests:
		cs.append([c.id, c.pos, c.rot, c.tier, c.name, c.opened])
	return {
		"seed": level_seed, "depth": depth, "time_left": time_left, "pvp": pvp, "map": map_id,
		"fix_used": fixtures.filter(func(f): return f.used).map(func(f): return f.id),
		"me": {"nid": p.nid, "pos": p.pos, "yaw": p.yaw, "cls": p.cls, "equipment": p.equipment, "bag": p.bag, "name": p.name, "faction": p.faction, "skills": p.skills, "wset": p.wset},
		"actors": acts, "chests": cs, "players": players.size(),
	}


# ------------------------------------------------------------------ 멀티플레이: 클라이언트
func start_client(info: Dictionary, hud_node) -> void:
	net = "client"
	hud = hud_node
	pvp = info.pvp
	level_seed = info.seed
	depth = info.depth
	time = 0.0
	level_time = 0.0
	time_left = info.time_left
	result = null
	end_timer = -1.0
	Net.game = self
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	_make_env(depth > 1)
	map_id = info.get("map", map_id)
	dungeon = Dungeon.new(depth, level_seed + depth, map_id)
	dungeon.build(world, false)
	_reset_lists(depth)
	_spawn_fixtures()
	for fid in info.get("fix_used", []):
		_fixture_used(int(fid))
	portal_schedule = []
	var me: Dictionary = info.me
	player = Player.new(self, me.pos, me.cls, me.equipment, me.bag, me.name, me.faction, 0, me.get("skills", {}), int(me.get("wset", 1)))
	player.nid = me.nid
	player.yaw = me.yaw
	players = [player]
	actors.append(player)
	net_actors[player.nid] = player
	for d in info.actors:
		_net_add_actor(d)
	for c in info.chests:
		var node := Models.chest(c[3])
		node.position = c[1]
		node.rotation.y = c[2]
		world.add_child(node)
		var ch := {"id": c[0], "pos": c[1], "node": node, "tier": c[3], "name": c[4], "opened": c[5], "items": [], "kind": "chest"}
		chests.append(ch)
		if c[5]:
			_chest_lid(ch)
	_make_view()
	running = true
	hud.start(self)
	hud.announce("던전에 입장했습니다", "%d명이 함께 입장했습니다 · %s" % [info.players, "개인전 (서로 적)" if pvp else "파티 (서로 아군)"])


func _net_add_actor(d: Dictionary) -> void:
	if net_actors.has(d.id):
		return
	var a := NetActor.new(self, d)
	actors.append(a)
	net_actors[a.nid] = a


func _net_del_actor(id: int) -> void:
	var a = net_actors.get(id)
	if a == null or a == player:
		return
	net_actors.erase(id)
	actors.erase(a)
	a.remove_from_world()


func _process_client(dt: float) -> void:
	time += dt
	level_time += dt
	time_left -= dt
	if time_left <= 120.0:
		warned = true
		env.environment.fog_density = base_fog + (1.0 - maxf(0.0, time_left) / 120.0) * 0.06
	player.update(dt)
	if hud != null and not player.done:
		interact_target = find_interactable(player) if player.alive else null
		hud.prompt(_prompt_for(interact_target))
		# F: 열린 창은 즉시 닫기 (서버도 같은 입력으로 닫음)
		if Input.is_action_just_pressed("interact") and hud.container != null and not menu_open:
			hud.close_container(false)
	_client_send_input(dt)
	for a in actors:
		if a != player:
			a.update(dt)
	_draw_actors(dt)
	_client_projectiles(dt)
	for id in net_zones:
		var z: Dictionary = net_zones[id]
		z.node.position = z.pos
		if z.kind == "orbit_blade":
			z.node.get_node("Pivot").rotation.y += dt * 9.0
	update_effects(dt)
	update_soul_orbs(dt)
	for b in loot_bags:
		b.node.rotation.y += dt
	_animate_portals(dt)
	_update_view(dt)
	if result != null and end_timer >= 0.0:
		end_timer -= dt
		if end_timer <= 0.0:
			end_timer = -1.0
			running = false
			raid_ended.emit(result)


func _client_send_input(dt: float) -> void:
	var acting := can_act() and player.alive
	for a in InputState.PRESS:
		if Input.is_action_just_pressed(a) and (acting or a == "interact" and not menu_open):
			Net.send_press(a)
	input_t -= dt
	if input_t > 0.0:
		return
	input_t = 1.0 / 30.0
	var bits := InputState.pack_held()
	if not acting:
		# 메뉴/인벤토리가 열려 있어도 이동은 가능, 공격은 불가
		bits &= ~((1 << 5) | (1 << 6) | (1 << 8) | (1 << 9))
	var panel: bool = hud.is_panel_open() or menu_open
	Net.send_input(player.pos, player.yaw, player.pitch, bits, acting, panel)


func _client_projectiles(dt: float) -> void:
	for id in net_proj:
		var p: Dictionary = net_proj[id]
		if not p.stuck:
			p.vel.y -= p.gravity * dt
			p.pos += p.vel * dt
		p.node.position = p.pos
		if not p.stuck:
			_orient_proj(p.node, p.kind, p.pos, p.vel)


func net_snapshot(w: Dictionary, me: Dictionary) -> void:
	if net != "client" or not running:
		return
	time_left = w.t
	net_actor_chunk(w.a)
	# 지속 구역
	var zseen := {}
	for s in w.z:
		var id: int = s[0]
		zseen[id] = true
		var z = net_zones.get(id)
		if z == null:
			z = {"kind": s[1], "pos": s[2], "radius": s[3]}
			z["node"] = _zone_node(z)
			z.node.position = z.pos
			world.add_child(z.node)
			net_zones[id] = z
		z.pos = s[2]
	for id in net_zones.keys():
		if not zseen.has(id):
			net_zones[id].node.queue_free()
			net_zones.erase(id)
	if player != null:
		player.apply_net_state(me)
		if me.ch.size() == 2 and hud != null:
			hud.channel(me.ch[0], me.ch[1])


func net_projs(pr: PackedFloat32Array) -> void:
	if net != "client" or not running:
		return
	var seen := {}
	for j in range(0, pr.size(), PROJ_STRIDE):
		var id := int(pr[j])
		seen[id] = true
		var ppos := Vector3(pr[j + 2], pr[j + 3], pr[j + 4])
		var pvel := Vector3(pr[j + 5], pr[j + 6], pr[j + 7])
		var stuck := pr[j + 8] > 0.5
		var p = net_proj.get(id)
		if p == null:
			var kind: String = PROJ_KINDS[clampi(int(pr[j + 1]), 0, PROJ_KINDS.size() - 1)]
			var node := _proj_node(kind)
			node.position = ppos
			world.add_child(node)
			p = {"node": node, "kind": kind, "pos": ppos, "vel": pvel, "stuck": stuck, "gravity": pr[j + 9]}
			net_proj[id] = p
		else:
			# 서버 위치 쪽으로 부드럽게 보정
			p.pos = (p.pos as Vector3).lerp(ppos, 0.5)
			p.vel = pvel
			p.stuck = stuck
	for id in net_proj.keys():
		if not seen.has(id):
			var p: Dictionary = net_proj[id]
			p.node.queue_free()
			net_proj.erase(id)


func net_actor_chunk(acts: PackedFloat32Array) -> void:
	if net != "client" or not running:
		return
	for j in range(0, acts.size(), ACT_STRIDE):
		var a = net_actors.get(int(acts[j]))
		if a != null and a != player:
			a.push_snap(acts.slice(j, j + ACT_STRIDE))


func _find_by_id(list: Array, id: int):
	for o in list:
		if o.id == id:
			return o
	return null


func net_event(n: String, args: Array) -> void:
	if net != "client" or world == null:
		return
	match n:
		"hud":
			if hud != null and hud.has_method(args[0]):
				hud.callv(args[0], args[1])
		"sfx":
			if player != null:
				Sfx.play(args[0], player.pos.distance_to(args[1]), args[2])
		"explode_fx", "spark", "spawn_ring_burst", "spawn_telegraph":
			callv(n, args)
		"frozen_fx":
			var a = net_actors.get(args[0])
			if a != null:
				a.frozen = args[1]
				var ice := Models.ice_block(a.height + 0.4)
				var holder := Node3D.new()
				holder.add_child(ice)
				holder.position = a.pos
				world.add_child(holder)
				effects.append({"node": holder, "t": 0.0, "dur": args[1], "kind": "ice", "follow": a})
		"actor_add":
			_net_add_actor(args[0])
		"actor_del":
			_net_del_actor(args[0])
		"chest_open":
			var c = _find_by_id(chests, args[0])
			if c != null and not c.opened:
				c.opened = true
				_chest_lid(c)
		"bag_add":
			var b := _add_bag_node(args[0], args[1], args[2], args[3])
			b.n = args[4]
		"fix_used":
			_fixture_used(int(args[0]))
		"item_add":
			_add_item_node(args[0], args[1], args[2], args[3])
		"bag_n":
			var b = _find_by_id(loot_bags, args[0])
			if b != null:
				b.n = args[1]
		"bag_del":
			var b = _find_by_id(loot_bags, args[0])
			if b != null:
				b.node.queue_free()
				loot_bags.erase(b)
		"orb_add":
			_add_orb_node(args[0], args[1])
		"orb_del":
			var o = _find_by_id(soul_orbs, args[0])
			if o != null:
				o.node.queue_free()
				soul_orbs.erase(o)
		"portal_add":
			_add_portal_node(args[0], args[1], args[2])
		"portal_del":
			var p = _find_by_id(portals, args[0])
			if p != null:
				p.node.queue_free()
				portals.erase(p)
		"inv":
			player.equipment = args[0]
			player.bag = args[1]
			if args.size() > 2:
				player.wset = int(args[2])
			player.stats = Data.compute_stats(player.cls, player.equipment, player.wset)
			player.armor = player.stats.armor
			_rebuild_view_model()
			if hud != null:
				hud.refresh_panels()
		"cont_open":
			if hud != null:
				hud.open_container(args[0])
		"cont_upd":
			if hud != null and hud.container != null and hud.container.cid == args[0].cid:
				hud.container = args[0]
				hud.refresh_panels()
		"cont_close":
			if hud != null:
				hud.close_container(false)
		"result":
			player.done = true
			result = args[0]
			end_timer = 0.3 if result.success else 2.5
			if hud != null:
				hud.close_container(false)
			if result.success:
				Sfx.play("portal")
