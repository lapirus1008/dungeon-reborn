# 직업 스킬 공용 로직 - 플레이어와 AI 모험가가 같은 규칙을 사용
# aim: {"origin": Vector3, "dir": Vector3, "target": Actor 또는 null, "point": Vector3(선택)}
class_name Skills
extends RefCounted

const GOLD := Color(1.0, 0.85, 0.4)
const NATURE := Color(0.45, 0.95, 0.4)
const ARCANE := Color(0.35, 0.65, 1.0)


# ------------------------------------------------------------------ 조회
static func skill_def(c, slot: String) -> Dictionary:
	var sk: Dictionary = Data.CLASSES[c.cls].skills
	if c.panther and sk.has(slot + "_p"):
		return sk[slot + "_p"]
	return sk[slot]


static func is_melee(c) -> bool:
	return c.cls in ["fighter", "swordmaster", "rogue", "deathknight", "priest"] or (c.cls == "druid" and c.panther)


static func uses_block(c) -> bool:
	return c.cls in ["fighter", "deathknight"]


# 근접 공격 수치 (bash = 지팡이 치기)
static func melee_profile(c, bash := false) -> Dictionary:
	if bash:
		return {"dmg": 12.0, "range": 2.6, "arc": 1.3, "cd": 0.8, "stamina": 8.0, "knock": 10.0, "hit_at": 0.14, "dur": 0.36}
	if c.panther:
		return {"dmg": 18.0, "range": 2.6, "arc": 1.4, "cd": 0.34, "stamina": 4.0, "knock": 2.0, "hit_at": 0.1, "dur": 0.28}
	match c.cls:
		"fighter":
			return {"dmg": 26.0, "range": 3.1, "arc": 1.5, "cd": 0.48, "stamina": 9.0, "knock": 5.0, "hit_at": 0.17, "dur": 0.42}
		"swordmaster":
			return {"dmg": 21.0, "range": 3.3, "arc": 1.8, "cd": 0.36, "stamina": 6.0, "knock": 3.0, "hit_at": 0.12, "dur": 0.32}
		"rogue":
			return {"dmg": 15.0, "range": 2.5, "arc": 1.2, "cd": 0.3, "stamina": 5.0, "knock": 1.0, "hit_at": 0.1, "dur": 0.26}
		"deathknight":
			return {"dmg": 34.0, "range": 3.4, "arc": 1.6, "cd": 0.8, "stamina": 12.0, "knock": 6.0, "hit_at": 0.3, "dur": 0.62}
		"priest":
			return {"dmg": 22.0, "range": 2.9, "arc": 1.3, "cd": 0.58, "stamina": 8.0, "knock": 4.0, "hit_at": 0.18, "dur": 0.45}
	return {"dmg": 12.0, "range": 2.6, "arc": 1.3, "cd": 0.8, "stamina": 8.0, "knock": 10.0, "hit_at": 0.14, "dur": 0.36}


# 원거리 기본 공격 (드루이드 인간형, 파이로맨서, 크라이오맨서)
static func ranged_profile(c) -> Dictionary:
	match c.cls:
		"druid":
			return {"kind": "thorn", "speed": 40.0, "dmg": 16.0, "cd": 0.5, "cost": 0.0}
		"pyromancer":
			return {"kind": "firebolt", "speed": 30.0, "dmg": 18.0, "cd": 0.45, "cost": 8.0, "homing": 3.0}
		"cryomancer":
			return {"kind": "icebolt", "speed": 40.0, "dmg": 15.0, "cd": 0.45, "cost": 8.0, "slow": 1.5}
	return {}


static func pay(c, cost: float) -> bool:
	if cost <= 0.0:
		return true
	if c.res < cost:
		if true:
			c.game.notify(c, "toast", ["%s이(가) 부족합니다" % Data.RES_NAMES.get(c.res_type(), "자원")])
		return false
	c.res -= cost
	return true


static func gain(c, amount: float) -> void:
	if c.res_type() != "":
		c.res = minf(c.res_max(), c.res + amount)


# 매 프레임 자원 회복/소모
static func tick_resource(c, dt: float) -> void:
	match c.res_type():
		"mana":
			c.res = minf(c.res_max(), c.res + dt * 7.0 * c.stats.get("regen_mul", 1.0))
		"primal":
			if c.panther:
				c.res -= dt * 4.0
				if c.res <= 0.0:
					c.res = 0.0
					set_panther(c, false)
			else:
				c.res = minf(c.res_max(), c.res + dt * 5.0 * c.stats.get("regen_mul", 1.0))


# ------------------------------------------------------------------ 근접
# 근접 타격 판정 (로그 기습/은신, 데스나이트 흡혈/영혼 포함). 가한 총 피해 반환
static func melee_strike(c, prof: Dictionary, mult := 1.0) -> float:
	var g = c.game
	var total := 0.0
	var stealth_bonus := 2.5 if (c.cls == "rogue" and c.stealth > 0.0) else 1.0
	var hits := 0
	for a in g.actors:
		if not a.alive or a.extracted or not g.hostile(c, a):
			continue
		var dx: float = a.pos.x - c.pos.x
		var dz: float = a.pos.z - c.pos.z
		var d := sqrt(dx * dx + dz * dz)
		if d > prof.range + a.radius:
			continue
		if d > 0.6 and absf(angle_difference(c.yaw, Actor.yaw_to(dx, dz))) > prof.arc / 2.0:
			continue
		if not g.dungeon.los(c.pos.x, c.pos.z, a.pos.x, a.pos.z):
			continue
		var dmg: float = prof.dmg * c.dmg_mul() * mult * stealth_bonus
		# 로그: 등 뒤 공격 1.6배
		if c.cls == "rogue":
			var facing_away := absf(angle_difference(a.yaw, Actor.yaw_to(-dx, -dz))) > 2.0
			if facing_away:
				dmg *= 1.6 + c.stats.get("flags", {}).get("backstab", 0.0)
		if c.panther:
			dmg *= 1.0 + c.stats.get("flags", {}).get("beast", 0.0)
		var nd := maxf(d, 0.001)
		var k: float = prof.knock
		total += a.take_damage(dmg, c, {"knock": Vector3(dx / nd * k, 0, dz / nd * k), "from": c.pos, "crit": stealth_bonus > 1.0})
		hits += 1
	if hits:
		g.sfx("hit", c.pos)
		if c.cls == "deathknight":
			c.heal_now(total * (0.1 + c.stats.get("flags", {}).get("lifesteal", 0.0)))
			gain(c, 8.0 * hits)
		if c.cls == "rogue" and c.stealth > 0.0:
			c.break_stealth()
	return total


# ------------------------------------------------------------------ 기본 원거리 / 우클릭
static func fire_basic(c, aim: Dictionary) -> bool:
	var prof := ranged_profile(c)
	if prof.is_empty() or c.cd.lmb > 0.0:
		return false
	if not pay(c, prof.cost):
		return false
	c.cd.lmb = prof.cd / c.stats.get("act_mul", 1.0)
	var extra := {}
	if prof.has("homing"):
		extra["homing"] = prof.homing
	if prof.has("slow"):
		extra["slow"] = prof.slow
	c.game.spawn_projectile(c, prof.kind, aim.origin, aim.dir, prof.speed, prof.dmg * c.dmg_mul(), extra)
	return true


static func throw_knife(c, aim: Dictionary) -> bool:
	if c.cd.rmb > 0.0:
		return false
	c.cd.rmb = skill_def(c, "rmb").cd * c.stats.get("cd_mul", 1.0)
	c.game.spawn_projectile(c, "knife", aim.origin, aim.dir, 45.0, 14.0 * c.dmg_mul(), {})
	return true


static func start_parry(c) -> bool:
	if c.cd.rmb > 0.0:
		return false
	c.cd.rmb = skill_def(c, "rmb").cd * c.stats.get("cd_mul", 1.0)
	c.parry = 0.35
	return true


static func roar(c) -> bool:
	if c.cd.rmb > 0.0:
		return false
	c.cd.rmb = skill_def(c, "rmb").cd * c.stats.get("cd_mul", 1.0)
	var g = c.game
	for a in g.actors:
		if a.alive and g.hostile(c, a) and a.pos.distance_to(c.pos) < 4.5:
			var dir: Vector3 = (a.pos - c.pos).normalized()
			a.take_damage(6.0 * c.dmg_mul(), c, {"knock": dir * 14.0, "from": c.pos})
	g.sfx("growl", c.pos)
	g.spawn_ring_burst(c.pos + Vector3(0, 0.3, 0), NATURE, 4.5)
	return true


# 프리스트 정화: charge 0~1
static func cleanse_heal(c, charge: float) -> bool:
	if c.cd.rmb > 0.0:
		return false
	if not pay(c, 15.0):
		return false
	c.cd.rmb = skill_def(c, "rmb").cd * c.stats.get("cd_mul", 1.0)
	c.cleanse()
	c.apply_heal(lerpf(10.0, 30.0, clampf(charge, 0.0, 1.0)) * c.stats.get("heal_mul", 1.0), 0.6)
	c.game.sfx("heal", c.pos)
	c.game.spawn_ring_burst(c.pos + Vector3(0, 0.2, 0), GOLD, 1.6)
	return true


# ------------------------------------------------------------------ Q / E
static func use_q(c, aim: Dictionary) -> bool:
	if c.cd.q > 0.0 or c.incapacitated():
		return false
	var ok := false
	match c.cls:
		"fighter":
			ok = _whirlwind(c)
		"swordmaster":
			ok = _psionic_blades(c, aim)
		"rogue":
			ok = _poison(c, aim)
		"deathknight":
			ok = _soul_shroud(c)
		"druid":
			ok = _toggle_panther(c)
		"pyromancer":
			ok = _pyroblast(c, aim)
		"cryomancer":
			ok = _ice_storm(c, aim)
		"priest":
			ok = _divine_guidance(c)
	if ok:
		c.cd.q = skill_def(c, "q").cd * c.stats.get("cd_mul", 1.0)
	return ok


static func use_e(c, aim: Dictionary) -> bool:
	if c.cd.e > 0.0 or c.incapacitated():
		return false
	var ok := false
	match c.cls:
		"fighter":
			ok = _charge(c)
		"swordmaster":
			ok = _whirling_blade(c)
		"rogue":
			ok = _vanish(c)
		"deathknight":
			ok = _grasp(c, aim)
		"druid":
			ok = _shadow_assault(c) if c.panther else _force_of_nature(c)
		"pyromancer":
			ok = _fire_blast(c)
		"cryomancer":
			ok = _frostbite(c)
		"priest":
			ok = _guard(c)
	if ok:
		c.cd.e = skill_def(c, "e").cd * c.stats.get("cd_mul", 1.0)
	return ok


static func _whirlwind(c) -> bool:
	if c.get("stamina") != null and c.stamina < 20.0:
		if true:
			c.game.notify(c, "toast", ["스태미나가 부족합니다"])
		return false
	if c.get("stamina") != null:
		c.stamina -= 20.0
	c.spin_t = 2.0
	c.spin_tick = 0.0
	return true


# 회오리 베기 진행 (매 프레임)
static func tick_spin(c, dt: float) -> void:
	if c.spin_t <= 0.0:
		return
	c.spin_t -= dt
	c.spin_tick -= dt
	if c.spin_tick <= 0.0:
		c.spin_tick = 0.25
		var g = c.game
		g.sfx("swing", c.pos, 0.15)
		var hits := 0
		for a in g.actors:
			if not a.alive or a.extracted or not g.hostile(c, a):
				continue
			var d: float = a.pos.distance_to(c.pos)
			if d < 3.2 + a.radius and g.dungeon.los(c.pos.x, c.pos.z, a.pos.x, a.pos.z):
				var dir: Vector3 = (a.pos - c.pos).normalized()
				a.take_damage(13.0 * c.dmg_mul(), c, {"knock": dir * 2.0, "from": c.pos})
				hits += 1
		if hits:
			g.sfx("hit", c.pos)


static func _charge(c) -> bool:
	c.dash = {"dir": Actor.fwd(c.yaw), "speed": 22.0, "t": 0.32, "hit": 30.0 * c.dmg_mul(), "stun": 0.9, "hit_done": false}
	c.game.sfx("swing", c.pos)
	return true


static func _psionic_blades(c, aim: Dictionary) -> bool:
	var g = c.game
	for i in 4:
		var off := (i - 1.5) * 0.18
		var dir: Vector3 = aim.dir.rotated(Vector3.UP, off)
		dir.y += 0.08
		g.spawn_projectile(c, "blade", aim.origin + Vector3(0, 0.15 * (i % 2), 0), dir.normalized(), 24.0 + i * 2.0, 16.0 * c.dmg_mul(), {"homing": 6.0, "heal_owner": 8.0, "life": 3.0})
	g.sfx("magic", c.pos)
	return true


static func _whirling_blade(c) -> bool:
	c.game.add_zone({"follow": c, "radius": 2.4, "dur": 8.0, "tick": 0.3, "dmg": 8.0 * c.dmg_mul(), "owner": c, "kind": "orbit_blade"})
	c.dr = 0.25
	c.dr_t = 8.0
	c.game.sfx("swing", c.pos)
	return true


static func _poison(c, aim: Dictionary) -> bool:
	var dir: Vector3 = aim.dir
	dir.y += 0.12
	c.game.spawn_projectile(c, "poison", aim.origin, dir.normalized(), 24.0, 8.0 * c.dmg_mul(), {"gravity": 9.0, "aoe": 2.8, "root": 2.0, "dot": 5.0 * (1.0 + c.stats.get("flags", {}).get("poison", 0.0))})
	return true


static func _vanish(c) -> bool:
	c.channel_t = 1.5
	c.break_stealth()
	if c.kind == "player":
		c.game.notify(c, "toast", ["은신 집중 중... (피격 시 취소)"])
	return true


# 은신 집중 진행 (매 프레임)
static func tick_channel(c, dt: float) -> void:
	if c.channel_t <= 0.0:
		return
	c.channel_t -= dt
	if c.channel_t <= 0.0:
		c.stealth = 15.0
		c.game.sfx("magic", c.pos, 0.0)
		if true:
			c.game.notify(c, "toast", ["은신! 첫 공격 2.5배"])


static func _soul_shroud(c) -> bool:
	if not pay(c, 40.0):
		return false
	c.game.add_zone({"follow": c, "radius": 4.5, "dur": 5.0, "tick": 0.5, "dmg": 6.0 * c.dmg_mul(), "slow": 0.8, "owner": c, "kind": "soul_shroud"})
	c.game.sfx("growl", c.pos)
	return true


static func _grasp(c, aim: Dictionary) -> bool:
	c.game.spawn_projectile(c, "grasp", aim.origin, aim.dir, 32.0, 10.0 * c.dmg_mul(), {"pull": true, "life": 0.6})
	c.game.sfx("magic", c.pos)
	return true


static func set_panther(c, on: bool) -> void:
	if c.panther == on:
		return
	c.panther = on
	c.game.on_shapeshift(c)
	c.game.sfx("growl", c.pos)


static func _toggle_panther(c) -> bool:
	if c.panther:
		set_panther(c, false)
		return true
	if not pay(c, 30.0):
		return false
	c.cleanse()
	set_panther(c, true)
	c.game.spawn_ring_burst(c.pos + Vector3(0, 0.3, 0), NATURE, 2.0)
	return true


static func _force_of_nature(c) -> bool:
	var g = c.game
	# 시야를 가리지 않도록 시전자 오른쪽 옆에 소환
	var right := Vector3(cos(c.yaw), 0, -sin(c.yaw))
	var p: Vector3 = c.pos + right * 1.8 - Actor.fwd(c.yaw) * 0.3
	p = g.dungeon.resolve_circle(p, 0.6)
	g.spawn_summon(c, p)
	c.give_shield(30.0, 8.0, NATURE)
	g.sfx("heal", c.pos)
	return true


static func _shadow_assault(c) -> bool:
	if not pay(c, 15.0):
		return false
	c.dash = {"dir": Actor.fwd(c.yaw), "speed": 20.0, "t": 0.4, "hit": 28.0 * c.dmg_mul(), "stun": 0.3, "hit_done": false}
	c.game.sfx("growl", c.pos)
	return true


static func _pyroblast(c, aim: Dictionary) -> bool:
	if not pay(c, 35.0):
		return false
	c.game.spawn_projectile(c, "pyroblast", aim.origin, aim.dir, 22.0, 55.0 * c.dmg_mul(), {"aoe": 4.0})
	return true


static func _fire_blast(c) -> bool:
	if not pay(c, 25.0):
		return false
	var g = c.game
	var f := Actor.fwd(c.yaw)
	for a in g.actors:
		if not a.alive or a.extracted or not g.hostile(c, a):
			continue
		var dx: float = a.pos.x - c.pos.x
		var dz: float = a.pos.z - c.pos.z
		var d := sqrt(dx * dx + dz * dz)
		if d > 5.5 + a.radius:
			continue
		if d > 0.8 and absf(angle_difference(c.yaw, Actor.yaw_to(dx, dz))) > 1.1:
			continue
		if not g.dungeon.los(c.pos.x, c.pos.z, a.pos.x, a.pos.z):
			continue
		var nd := maxf(d, 0.001)
		a.take_damage(28.0 * c.dmg_mul(), c, {"knock": Vector3(dx / nd * 16.0, 0, dz / nd * 16.0), "from": c.pos})
	g.explode_fx(c.pos + f * 2.5 + Vector3(0, 1.0, 0), 3.0, Color(1.0, 0.42, 0.1))
	g.sfx("fire", c.pos)
	return true


static func _ice_storm(c, aim: Dictionary) -> bool:
	if not pay(c, 35.0):
		return false
	var g = c.game
	var point: Vector3 = aim.get("point", g.aim_point(aim.origin, aim.dir, 18.0))
	g.add_zone({"pos": point, "radius": 4.0, "dur": 4.0, "tick": 0.5, "dmg": 7.0 * c.dmg_mul(), "slow": 1.0, "owner": c, "kind": "ice_storm"})
	g.sfx("magic", point)
	return true


static func _frostbite(c) -> bool:
	if not pay(c, 30.0):
		return false
	c.cleanse()
	c.frozen = 3.0
	c.apply_heal(40.0, 3.0)
	c.game.on_frozen(c)
	c.game.sfx("shield", c.pos)
	return true


static func _divine_guidance(c) -> bool:
	if not pay(c, 35.0):
		return false
	var g = c.game
	for a in g.actors:
		if not a.alive or a.extracted or a.pos.distance_to(c.pos) > 6.0:
			continue
		if a == c or a.faction == c.faction:
			a.cleanse()
			a.immune = 2.0
			a.apply_heal(25.0 * c.stats.get("heal_mul", 1.0), 0.8)
		elif g.hostile(c, a) and g.dungeon.los(c.pos.x, c.pos.z, a.pos.x, a.pos.z):
			a.take_damage(20.0 * c.dmg_mul(), c, {"from": c.pos})
	g.spawn_ring_burst(c.pos + Vector3(0, 0.2, 0), GOLD, 6.0)
	g.sfx("heal", c.pos)
	return true


static func _guard(c) -> bool:
	if not pay(c, 30.0):
		return false
	var g = c.game
	for a in g.actors:
		if a.alive and (a == c or a.faction == c.faction) and a.pos.distance_to(c.pos) < 6.0:
			a.give_shield(50.0, 8.0, GOLD)
			if a.kind == "player":
				a.shield_hit_fx = 1.0
	g.spawn_ring_burst(c.pos + Vector3(0, 1.0, 0), GOLD, 3.0)
	g.sfx("shield", c.pos)
	return true


# 돌진류(돌진, 그림자 습격) 진행. 이동 처리 후 true면 돌진 중
static func tick_dash(c, dt: float) -> bool:
	if c.dash == null:
		return false
	var dash: Dictionary = c.dash
	dash.t -= dt
	c.move(dash.dir.x * dash.speed, dash.dir.z * dash.speed, dt)
	if dash.has("hit") and not dash.hit_done:
		var g = c.game
		for a in g.actors:
			if not a.alive or a == c or a.extracted or not g.hostile(c, a):
				continue
			if Vector2(a.pos.x - c.pos.x, a.pos.z - c.pos.z).length() < a.radius + 1.2:
				a.take_damage(dash.hit, c, {"knock": dash.dir * 12.0, "stun": dash.get("stun", 0.0), "from": c.pos})
				g.sfx("hit", c.pos)
				c.game.notify(c, "shake", [0.25])
				dash.hit_done = true
				dash.t = 0.0
				break
	if dash.t <= 0.0:
		c.dash = null
	return true
