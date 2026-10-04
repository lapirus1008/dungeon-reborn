# 직업 스킬 공용 로직 - 플레이어와 AI 모험가가 같은 규칙을 사용 (던전본 Q/E 스킬과 패시브)
# aim: {"origin": Vector3, "dir": Vector3, "target": Actor 또는 null, "point": Vector3(선택)}
class_name Skills
extends RefCounted

const GOLD := Color(1.0, 0.85, 0.4)
const NATURE := Color(0.45, 0.95, 0.4)
const ARCANE := Color(0.35, 0.65, 1.0)
const SOUL := Color(0.35, 0.95, 0.55)
const SHADOW := Color(0.55, 0.25, 0.95)
const FIRE := Color(1.0, 0.45, 0.12)
const FROST := Color(0.6, 0.9, 1.0)

# 누르고 있다가 놓으면 발동하는 스킬
const HOLD_SKILLS := ["pyro_pyroblast", "priest_heal"]


# ------------------------------------------------------------------ 조회
static func skill_id(c, slot: String) -> String:
	if slot == "e" and c.panther:
		return "druid_shadow_assault"
	var sk = c.get("skills")
	if sk is Dictionary and sk.has(slot):
		return sk[slot]
	return Data.CLASSES[c.cls][slot][0]


static func skill_def(c, slot: String) -> Dictionary:
	if slot == "q" or slot == "e":
		return Data.SKILLS[skill_id(c, slot)]
	var sk: Dictionary = Data.CLASSES[c.cls].skills
	if c.panther and sk.has(slot + "_p"):
		return sk[slot + "_p"]
	return sk[slot]


static func has_fx(c, fx: String) -> bool:
	return c.stats.get("flags", {}).has(fx)


static func wcat(c) -> String:
	return c.stats.get("wcat", "")


static func is_caster_weapon(c) -> bool:
	return wcat(c) in ["staff", "orb"]


static func is_melee(c) -> bool:
	if c.panther:
		return true
	var w := wcat(c)
	if w in ["staff", "orb", "crossbow"]:
		return false
	return true


# 우클릭 = 방어 자세 (방패, 한손검, 장검, 단검, 철퇴 모두 각자 방어 자세)
static func uses_block(c) -> bool:
	if c.panther:
		return false
	var off := Data.offhand_cat(c.equipment, c.wset) if c.get("equipment") != null else ""
	return off == "shield" or wcat(c) in ["sword", "longsword", "mace", "dagger"]


# 무기 종류별 근접 공격 (bash = 지팡이 치기)
static func melee_profile(c, bash := false) -> Dictionary:
	var spd: float = c.stats.get("act_mul", 1.0)
	var p := {}
	# hit_at: 휘두르기 시작부터 칼날이 닿는 순간까지 (예비 동작이 있어 바로 맞지 않음)
	if bash:
		p = {"dmg": 14.0, "range": 2.6, "arc": 1.3, "cd": 0.9, "knock": 10.0, "hit_at": 0.24, "dur": 0.48}
	elif c.panther:
		p = {"dmg": 22.0, "range": 2.6, "arc": 1.4, "cd": 0.4, "knock": 2.0, "hit_at": 0.16, "dur": 0.34, "claw": true}
	else:
		match wcat(c):
			"longsword":
				p = {"dmg": 46.0, "range": 3.4, "arc": 1.6, "cd": 0.95, "knock": 6.0, "hit_at": 0.42, "dur": 0.85}
			"dagger":
				p = {"dmg": 21.0, "range": 2.5, "arc": 1.2, "cd": 0.34, "knock": 1.0, "hit_at": 0.16, "dur": 0.32}
			"mace":
				p = {"dmg": 33.0, "range": 2.8, "arc": 1.3, "cd": 0.7, "knock": 4.0, "hit_at": 0.3, "dur": 0.6}
			"":
				p = {"dmg": 12.0, "range": 2.2, "arc": 1.2, "cd": 0.55, "knock": 2.0, "hit_at": 0.18, "dur": 0.36}
			_:
				p = {"dmg": 31.0, "range": 3.0, "arc": 1.6, "cd": 0.55, "knock": 4.0, "hit_at": 0.26, "dur": 0.52}
		if c.cls == "deathknight":
			p.dmg *= 1.1
	p.cd /= spd
	return p


# 원거리 기본 공격 (중석궁, 지팡이·오브를 든 술사)
static func ranged_profile(c) -> Dictionary:
	if wcat(c) == "crossbow":
		return {"kind": "bolt", "speed": 55.0, "dmg": 62.0, "cd": 1.4, "cost": 0.0, "gravity": 1.5}
	match c.cls:
		"druid":
			return {"kind": "thorn", "speed": 40.0, "dmg": 20.0, "cd": 0.5, "cost": 0.0}
		"pyromancer":
			return {"kind": "firebolt", "speed": 30.0, "dmg": 22.0, "cd": 0.45, "cost": 6.0, "homing": 3.0, "dtype": "fire"}
		"cryomancer":
			return {"kind": "icebolt", "speed": 40.0, "dmg": 19.0, "cd": 0.45, "cost": 0.0, "slow": 1.0, "dtype": "cold"}
		"priest":
			return {"kind": "holy", "speed": 38.0, "dmg": 20.0, "cd": 0.5, "cost": 3.0, "dtype": "holy"}
	return {}


static func pay(c, cost: float) -> bool:
	if cost <= 0.0:
		return true
	# Q/E 스킬은 마나를 쓰지 않음 (마나는 지팡이 기본 공격용 장전량)
	if c.skill_casting and c.res_type() == "mana":
		return true
	if c.res < cost:
		c.game.notify(c, "toast", ["%s이(가) 부족합니다" % Data.RES_NAMES.get(c.res_type(), "자원")])
		return false
	c.res -= cost
	c.res_idle = 0.0
	return true


static func gain(c, amount: float) -> void:
	if c.res_type() != "":
		c.res = minf(c.res_max(), c.res + amount)


static func cd_of(c, sid: String) -> float:
	return Data.SKILLS[sid].cd * c.stats.get("cd_mul", 1.0)


static func _req_ok(c, sid: String) -> bool:
	var req: String = Data.SKILLS[sid].get("req", "")
	match req:
		"2h":
			if not (wcat(c) in ["longsword"]):
				c.game.notify(c, "toast", ["양손 무기를 착용해야 합니다"])
				return false
		"caster":
			if not is_caster_weapon(c):
				c.game.notify(c, "toast", ["지팡이나 오브를 착용해야 합니다"])
				return false
		"sword_slot":
			if sword_count(c) <= 0:
				c.game.notify(c, "toast", ["검 슬롯에 검이 없습니다"])
				return false
	return true


# 매 프레임 자원 회복
static func tick_resource(c, dt: float) -> void:
	var rm: float = c.stats.get("regen_mul", 1.0)
	match c.res_type():
		"mana":
			# 마나: 쓰지 않을 때만 천천히 재생 (마지막 사용 후 1.5초부터)
			c.res_idle += dt
			if c.res_idle >= 1.5:
				c.res = minf(c.res_max(), c.res + dt * 2.5 * rm)
		"soul":
			# 영혼 에너지는 쓰러진 적의 영혼을 흡수해서 얻음 (아주 느린 자연 회복)
			c.res = minf(c.res_max(), c.res + dt * 0.4 * rm)
		"primal":
			c.res = minf(c.res_max(), c.res + dt * 1.0 * rm)
	# 자연의 힘 충전
	if c.cls == "druid":
		var mx := nature_max(c)
		if c.charges < mx:
			c.charge_cd -= dt
			if c.charge_cd <= 0.0:
				c.charges += 1
				c.charge_cd = nature_recharge(c)
	if c.cls == "priest":
		var mx := 2 if has_fx(c, "saint") else 1
		if c.charges < mx:
			c.charge_cd -= dt
			if c.charge_cd <= 0.0:
				c.charges += 1
				c.charge_cd = cd_of(c, "priest_protection")
	for k in ["pursuit_t", "quick_cast_t", "petrify_coat", "soul_shield_cd"]:
		var v: float = c.get(k)
		if v > 0.0:
			c.set(k, v - dt)


static func nature_max(c) -> int:
	return 2 if has_fx(c, "nature_seed") else 1


static func nature_recharge(c) -> float:
	return 30.0 if has_fx(c, "nature_agility") else 60.0


static func sword_count(c) -> int:
	var n := 0
	for s in Data.SWORD_SLOTS:
		if c.equipment.get(s) != null:
			n += 1
	return n


# ------------------------------------------------------------------ 근접
# 근접 타격 판정. 가한 총 피해 반환
static func melee_strike(c, prof: Dictionary, mult := 1.0) -> float:
	var g = c.game
	var total := 0.0
	var hits := 0
	var hit_list := []
	for a in g.actors:
		if not a.alive or a.extracted or a == c:
			continue
		if not g.hostile(c, a) and not g.friendly_fire(c, a):
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
		var dmg: float = prof.dmg * c.dmg_mul() * mult
		var nd := maxf(d, 0.001)
		var k: float = prof.knock
		var dealt: float = g.hit(c, a, dmg, {"knock": Vector3(dx / nd * k, 0, dz / nd * k), "from": c.pos, "melee": true, "weapon": true, "dtype": c.stats.get("dtype", "phys"), "backstab": prof.get("backstab", false) or prof.get("power", false)})
		total += dealt
		hits += 1
		hit_list.append(a)
	if hits:
		g.sfx("hit", c.pos)
		if c.cls == "deathknight":
			c.heal_now(total * 0.1)
		# 표범 공격: 암흑 에너지 +20
		if prof.get("claw", false):
			gain(c, 20.0)
	return total


# 로그 단검 콤보: 1페이즈 우·좌·우 / 2페이즈 우·좌·우·좌·우 / 3페이즈 양손 X자 베기
const ROGUE_COMBO := [
	{"side": 1.0}, {"side": -1.0}, {"side": 1.0, "end": true},
	{"side": 1.0}, {"side": -1.0}, {"side": 1.0}, {"side": -1.0}, {"side": 1.0, "end": true},
	{"side": 0.0, "x": true, "end": true},
]


static func rogue_combo_profile(c, i: int) -> Dictionary:
	var st: Dictionary = ROGUE_COMBO[i % ROGUE_COMBO.size()]
	var spd: float = c.stats.get("act_mul", 1.0)
	var p := {"dmg": 15.0, "range": 2.5, "arc": 1.1, "cd": 0.22, "knock": 0.5, "hit_at": 0.11, "dur": 0.22}
	if st.get("x", false):
		p = {"dmg": 42.0, "range": 2.7, "arc": 1.9, "cd": 0.9, "knock": 5.0, "hit_at": 0.24, "dur": 0.55, "xslash": true}
	elif st.get("end", false):
		p.cd = 0.5 # 페이즈 사이 짧은 숨 고르기
	p.cd /= spd
	p["side"] = st.side
	return p


# 뒤를 잡은 대상 (로그 기습 내려찍기): 대상이 등을 보이고 있으면 (몬스터는 나를 노리지 않거나 묶여 있을 때 등이 보임)
static func backstab_target(c):
	var best = null
	var bd := 3.0
	for a in c.game.actors:
		if not a.alive or a.extracted or a == c or not c.game.hostile(c, a):
			continue
		var dx: float = a.pos.x - c.pos.x
		var dz: float = a.pos.z - c.pos.z
		var d := sqrt(dx * dx + dz * dz)
		if d > 2.6 + a.radius or d >= bd:
			continue
		if absf(angle_difference(c.yaw, Actor.yaw_to(dx, dz))) > 0.6:
			continue
		# 대상이 보는 방향과 대상→나 방향이 110도 이상 벌어지면 등 뒤
		if absf(angle_difference(a.yaw, Actor.yaw_to(-dx, -dz))) < 1.9:
			continue
		best = a
		bd = d
	return best


static func backstab_profile(c) -> Dictionary:
	return {"dmg": 21.0 * 3.2, "range": 2.6, "arc": 0.9, "cd": 1.0 / c.stats.get("act_mul", 1.0), "knock": 3.0, "hit_at": 0.3, "dur": 0.62, "backstab": true, "side": 2.0}


# ------------------------------------------------------------------ 기본 원거리 / 우클릭
static func fire_basic(c, aim: Dictionary) -> bool:
	var prof := ranged_profile(c)
	if prof.is_empty() or c.cd.lmb > 0.0:
		return false
	if not pay(c, prof.cost):
		return false
	c.cd.lmb = prof.cd / c.stats.get("act_mul", 1.0)
	var extra := {"dtype": prof.get("dtype", c.stats.get("dtype", "phys")), "weapon": true}
	for k in ["homing", "slow", "gravity"]:
		if prof.has(k):
			extra[k] = prof[k]
	c.game.spawn_projectile(c, prof.kind, aim.origin, aim.dir, prof.speed, prof.dmg * c.dmg_mul(), extra)
	return true


# 지팡이 기본 공격: 화염 지팡이 = 누르고 있으면 레이저 4타 후 조준점 폭발, 번개 지팡이 = 조준점에 번개
static func staff_mode(c) -> String:
	if c.panther or wcat(c) != "staff":
		return ""
	match str(c.stats.get("dtype", "")):
		"fire":
			return "fire"
		"lightning":
			return "lightning"
	return ""


# 조준선을 따라가다 처음 맞는 적(또는 벽)까지
static func ray_hit(c, aim: Dictionary, max_d := 18.0) -> Dictionary:
	var g = c.game
	var p: Vector3 = aim.origin
	var dir: Vector3 = aim.dir
	var d := 0.0
	while d < max_d:
		p += dir * 0.3
		d += 0.3
		if g.dungeon.is_solid(p.x, p.z) or p.y <= 0.0:
			return {"point": p, "actor": null}
		for a in g.actors:
			if a.alive and not a.extracted and a != c and g.hostile(c, a):
				if Vector2(a.pos.x - p.x, a.pos.z - p.z).length() < a.radius + 0.35 and p.y > a.pos.y - 0.2 and p.y < a.pos.y + a.height + 0.3:
					return {"point": p, "actor": a}
	return {"point": p, "actor": null}


const BEAM_TICK := 0.32
const BEAM_TICKS := 4
const MANA_CELL := 20.0 # 마나 바 1칸
# 레이저 한 번은 아주 조금, 마지막 폭발까지 쓰면 합쳐서 정확히 1칸
const BEAM_TICK_COST := 1.0
const BEAM_BLAST_COST := MANA_CELL - BEAM_TICK_COST * BEAM_TICKS


static func tick_beam(c, dt: float, holding: bool, aim: Dictionary) -> void:
	var g = c.game
	if not holding:
		if c.beam_on:
			c.beam_on = false
			c.cd.lmb = 0.35
		return
	if not c.beam_on:
		if c.cd.lmb > 0.0:
			return
		c.beam_on = true
		c.beam_t = 0.0
		c.beam_n = 0
	c.beam_t += dt
	c.cast = 0.15
	if c.beam_n < BEAM_TICKS and c.beam_t >= BEAM_TICK * (c.beam_n + 1):
		if not pay(c, BEAM_TICK_COST):
			c.beam_on = false
			c.cd.lmb = 0.5
			return
		c.beam_n += 1
		var h := ray_hit(c, aim)
		g.beam_fx(aim.origin + Vector3(0, -0.15, 0), h.point, FIRE, BEAM_TICK + 0.05)
		if h.actor != null:
			g.hit(c, h.actor, 13.0 * c.dmg_mul(), {"from": c.pos, "ranged": true, "dtype": "fire", "weapon": true})
		g.sfx("fire", c.pos, 0.1)
	elif c.beam_n >= BEAM_TICKS and c.beam_t >= BEAM_TICK * (BEAM_TICKS + 1):
		# 마지막: 조준한 곳에 큰 폭발 (마나가 모자라면 폭발 없이 끝)
		if not pay(c, BEAM_BLAST_COST):
			c.beam_on = false
			c.cd.lmb = 0.5
			return
		var h := ray_hit(c, aim)
		g.beam_fx(aim.origin + Vector3(0, -0.15, 0), h.point, Color(1.0, 0.75, 0.3), 0.25)
		g.explode(Vector3(h.point.x, maxf(0.3, h.point.y), h.point.z), 2.6, 58.0 * c.dmg_mul(), c, "fire", {"dtype": "fire", "burn": 2})
		c.beam_on = false
		c.cd.lmb = 1.0 / c.stats.get("act_mul", 1.0)


static func lightning_strike(c, aim: Dictionary) -> bool:
	if c.cd.lmb > 0.0 or not pay(c, 8.0):
		return false
	var g = c.game
	var p: Vector3 = g.aim_point(aim.origin, aim.dir, 22.0)
	c.cd.lmb = 1.2 / c.stats.get("act_mul", 1.0)
	c.cast = 0.3
	g.spawn_telegraph(p, 2.2, 0.35)
	g.add_zone({"pos": p, "radius": 2.2, "dur": 0.6, "delay": 0.35, "owner": c, "kind": "lightning", "dmg": 50.0 * c.dmg_mul(), "once": true, "dtype": "lightning"})
	g.sfx("magic", c.pos, 0.1)
	return true


static func throw_knife(c, aim: Dictionary) -> bool:
	if c.cd.rmb > 0.0:
		return false
	c.cd.rmb = 1.5 * c.stats.get("cd_mul", 1.0)
	c.game.spawn_projectile(c, "knife", aim.origin, aim.dir, 45.0, 16.0 * c.dmg_mul(), {"weapon": true})
	return true


static func start_parry(c) -> bool:
	if c.cd.rmb > 0.0:
		return false
	c.cd.rmb = 1.2 * c.stats.get("cd_mul", 1.0)
	c.parry = 0.35
	return true


static func roar(c) -> bool:
	if c.cd.rmb > 0.0:
		return false
	c.cd.rmb = 6.0 * c.stats.get("cd_mul", 1.0)
	var g = c.game
	for a in g.actors:
		if a.alive and g.hostile(c, a) and a.pos.distance_to(c.pos) < 4.5:
			var dir: Vector3 = (a.pos - c.pos).normalized()
			g.hit(c, a, 8.0 * c.dmg_mul(), {"knock": dir * 14.0, "from": c.pos})
	g.sfx("growl", c.pos)
	g.spawn_ring_burst(c.pos + Vector3(0, 0.3, 0), NATURE, 4.5)
	return true


# 플라스크 던지기 (소모품 칸 3/4): 화염 / 바위 / 번개 / 미믹
static func throw_flask(c, aim: Dictionary, it: Dictionary, slot: String) -> bool:
	if c.cd.get("util", 0.0) > 0.0 or c.incapacitated():
		return false
	c.cd["util"] = 0.9
	var g = c.game
	var b: Dictionary = Data.base_of(it)
	var dir: Vector3 = aim.dir
	dir.y += 0.15
	var ex := {"gravity": 9.0}
	match b.throw:
		"fire":
			ex.merge({"aoe": 3.0, "burn": 3, "dtype": "fire", "fire_aoe": true, "color": Color(1.0, 0.45, 0.12)})
		"rock":
			ex.merge({"aoe": 2.5, "dtype": "phys", "stun": 1.5, "color": Color(0.6, 0.55, 0.45)})
		"lightning":
			ex.merge({"aoe": 3.5, "dtype": "lightning", "slow": 2.0, "color": Color(0.55, 0.75, 1.0)})
		"mimic":
			ex.merge({"summon_mimic": true})
	g.spawn_projectile(c, "flask", aim.origin, dir.normalized(), 20.0, float(b.get("dmg", 0)) * c.stats.get("dmg_mul", 1.0), ex)
	g.sfx("swing", c.pos)
	it.count = int(it.get("count", 1)) - 1
	if it.count <= 0:
		c.equipment[slot] = null
	g.inv_changed(c)
	return true


# ------------------------------------------------------------------ Q / E
static func use_q(c, aim: Dictionary, charge := 1.0) -> bool:
	return _use(c, "q", aim, charge)


static func use_e(c, aim: Dictionary, charge := 1.0) -> bool:
	return _use(c, "e", aim, charge)


static func _use(c, slot: String, aim: Dictionary, charge: float) -> bool:
	var sid := skill_id(c, slot)
	# 다시 누르면 끄는 스킬 (재사용 대기와 무관)
	match sid:
		"dk_soul_storm":
			if c.soul_storm:
				stop_soul_storm(c)
				return true
		"cryo_ice_barrier":
			if c.frozen > 0.0 and c.barrier:
				c.frozen = 0.0
				c.barrier = false
				return true
		"druid_primal":
			if c.panther:
				set_panther(c, false)
				c.cd.q = cd_of(c, sid)
				return true
	var cd_key := slot
	if c.cd[cd_key] > 0.0 or c.incapacitated():
		return false
	if not _req_ok(c, sid):
		return false
	var ok := false
	var custom_cd := -1.0
	c.skill_casting = true
	ok = _cast(c, sid, slot, aim, charge)
	c.skill_casting = false
	custom_cd = c.get_meta("custom_cd", -1.0)
	c.remove_meta("custom_cd")
	if ok:
		c.cd[cd_key] = custom_cd if custom_cd >= 0.0 else cd_of(c, sid)
	return ok


static func _cast(c, sid: String, slot: String, aim: Dictionary, charge: float) -> bool:
	var ok := false
	var custom_cd := -1.0
	match sid:
		"fighter_whirlwind":
			ok = _whirlwind(c)
		"fighter_warcry":
			ok = _warcry(c)
		"fighter_charge":
			ok = _charge(c)
		"fighter_inspire":
			ok = _inspire(c)
		"priest_revelation":
			ok = _revelation(c, aim)
		"priest_heal":
			ok = _heal(c, aim, charge)
		"priest_holy_ward":
			ok = _holy_ward(c, aim)
		"priest_protection":
			ok = _protection(c)
			if ok:
				custom_cd = 1.0
		"pyro_pyroblast":
			ok = _pyroblast(c, aim, charge)
		"pyro_fireshock":
			ok = _fireshock(c)
		"rogue_petrify":
			ok = _petrify(c)
		"rogue_blades":
			ok = _blades(c, aim)
		"rogue_stealth":
			ok = _stealth(c, 3.0, "stealth")
		"rogue_quick_conceal":
			ok = _quick_conceal(c)
		"rogue_shadow_veil":
			ok = _stealth(c, 3.0, "veil")
		"dk_wraith_guard":
			ok = _wraith_guard(c)
		"dk_soul_storm":
			ok = _soul_storm(c)
		"dk_soul_chain":
			ok = _soul_chain(c, aim)
		"cryo_blizzard":
			ok = _blizzard(c, aim)
		"cryo_frost_curse":
			ok = _frost_curse(c, aim)
		"cryo_ice_armor":
			ok = _ice_armor(c, aim)
		"cryo_ice_barrier":
			ok = _ice_barrier(c)
		"sm_psionic":
			# 검 슬롯의 검을 한 자루씩 소환 (좌클릭: 소환된 만큼 발사 · 우클릭: 취소)
			if c.psi_on:
				return false
			c.psi_on = true
			c.psi_n = 0
			c.psi_t = 0.0
			c.psi_aim = aim
			c.set_meta("custom_cd", 0.0)
			return true
		"sm_blade_dance":
			ok = _blade_dance(c)
		"druid_primal":
			ok = _toggle_panther(c)
		"druid_nature":
			ok = _nature(c, aim)
			if ok:
				custom_cd = 1.0
		"druid_shadow_assault":
			ok = _shadow_assault(c)
	if custom_cd >= 0.0:
		c.set_meta("custom_cd", custom_cd)
	return ok


# ---- 파이터
static func _whirlwind(c) -> bool:
	c.spin_t = 2.4
	c.spin_tick = 0.0
	return true


# 소용돌이 진행 (매 프레임): 매회 51.12 직접 피해
static func tick_spin(c, dt: float) -> void:
	if c.spin_t <= 0.0:
		return
	c.spin_t -= dt
	c.spin_tick -= dt
	if c.spin_tick <= 0.0:
		c.spin_tick = 0.3
		var g = c.game
		g.sfx("swing", c.pos, 0.15)
		var hits := 0
		for a in g.actors:
			if not a.alive or a.extracted or not g.hostile(c, a):
				continue
			var d: float = a.pos.distance_to(c.pos)
			if d < 3.3 + a.radius and g.dungeon.los(c.pos.x, c.pos.z, a.pos.x, a.pos.z):
				var dir: Vector3 = (a.pos - c.pos).normalized()
				g.hit(c, a, 51.12 * c.dmg_mul() / 1.6, {"knock": dir * 2.0, "from": c.pos, "melee": true, "weapon": true})
				hits += 1
		if hits:
			g.sfx("hit", c.pos)


static func _warcry(c) -> bool:
	c.warcry_t = 5.0
	if has_fx(c, "weapon_master"):
		c.give_shield(200.0, 5.0, Color(1.0, 0.5, 0.3))
	c.game.spawn_ring_burst(c.pos + Vector3(0, 1.0, 0), Color(1.0, 0.35, 0.2), 3.5)
	c.game.sfx("growl", c.pos)
	return true


static func _charge(c) -> bool:
	c.dash = {"dir": Actor.fwd(c.yaw), "speed": 22.0, "t": 0.3, "hit_done": true}
	c.game.sfx("swing", c.pos)
	return true


static func _inspire(c) -> bool:
	var g = c.game
	for a in g.actors:
		if a.alive and (a == c or (a.faction == c.faction and a.kind in ["player", "bot"])) and a.pos.distance_to(c.pos) < 10.0:
			a.add_speed(150.0, 3.0)
	g.spawn_ring_burst(c.pos + Vector3(0, 0.3, 0), GOLD, 6.0)
	g.sfx("bell", c.pos)
	return true


# ---- 프리스트
static func _aimed_ally(c, aim: Dictionary, rng := 25.0, allow_dead := false):
	var g = c.game
	var best = null
	var bs := 0.95
	for a in g.actors:
		if a == c or a.extracted or not (a.kind in ["player", "bot"]) or a.faction != c.faction:
			continue
		if not a.alive and not allow_dead:
			continue
		var to: Vector3 = a.center() - aim.origin
		var d := to.length()
		if d > rng:
			continue
		var dot: float = to.normalized().dot(aim.dir)
		if dot > bs and g.dungeon.los(c.pos.x, c.pos.z, a.pos.x, a.pos.z):
			bs = dot
			best = a
	return best


static func _revelation(c, aim: Dictionary) -> bool:
	if not pay(c, Data.SKILLS.priest_revelation.cost):
		return false
	var g = c.game
	var point: Vector3 = aim.get("point", g.aim_point(aim.origin, aim.dir, 20.0))
	g.spawn_telegraph(point, 4.5, 1.0)
	g.add_zone({"pos": point, "radius": 4.5, "dur": 1.2, "delay": 1.0, "owner": c, "kind": "revelation", "dmg": 49.78 * c.dmg_mul(), "heal": 89.41 * c.stats.get("heal_mul", 1.0), "once": true, "dtype": "holy"})
	g.sfx("magic", point)
	return true


static func _heal(c, aim: Dictionary, charge: float) -> bool:
	if not pay(c, Data.SKILLS.priest_heal.cost):
		return false
	var g = c.game
	var self_cast: bool = aim.get("self", false)
	var t = null if self_cast else _aimed_ally(c, aim, 25.0, has_fx(c, "resurrect"))
	if t == null:
		t = c
	var amount: float = lerpf(53.64, 143.05, clampf(charge, 0.0, 1.0)) * c.stats.get("heal_mul", 1.0)
	if not t.alive:
		# 부활 패시브: 모험 중 1회
		if c.revive_used or not (t is Player) or t.done:
			g.notify(c, "toast", ["부활시킬 수 없습니다"])
			return false
		c.revive_used = true
		g.revive_player(t, c)
		return true
	t.apply_heal(amount, 0.5)
	g.spawn_ring_burst(t.pos + Vector3(0, 0.2, 0), GOLD, 1.6)
	g.sfx("heal", t.pos)
	return true


static func _holy_ward(c, aim: Dictionary) -> bool:
	if not pay(c, Data.SKILLS.priest_holy_ward.cost):
		return false
	var t = null if aim.get("self", false) else _aimed_ally(c, aim)
	if t == null:
		t = c
	t.invuln = maxf(t.invuln, 3.0)
	t.give_shield(1.0, 3.0, Color(1.0, 0.95, 0.6))
	c.game.spawn_ring_burst(t.pos + Vector3(0, 1.0, 0), GOLD, 2.0)
	c.game.sfx("shield", t.pos)
	return true


# 수호: 충전(성자 패시브 2회)을 쓰는 실드
static func _protection(c) -> bool:
	if c.charges <= 0:
		c.game.notify(c, "toast", ["'수호'를 아직 사용할 수 없습니다"])
		return false
	if not pay(c, Data.SKILLS.priest_protection.cost):
		return false
	c.charges -= 1
	if c.charge_cd <= 0.0:
		c.charge_cd = cd_of(c, "priest_protection")
	var g = c.game
	var targets := []
	for a in g.actors:
		if a.alive and (a == c or (a.faction == c.faction and a.kind in ["player", "bot"])) and a.pos.distance_to(c.pos) < 8.0:
			targets.append(a)
	for a in targets:
		a.give_shield(133.85 * c.stats.get("heal_mul", 1.0), 60.0, GOLD)
		if a is Player:
			a.shield_hit_fx = 1.0
		if has_fx(c, "baptism"):
			a.cleanse()
			a.immune = maxf(a.immune, 2.0)
		if has_fx(c, "answer") and targets.size() >= 2:
			a.add_speed(100.0, 1.0)
	g.spawn_ring_burst(c.pos + Vector3(0, 1.0, 0), GOLD, 4.0)
	g.sfx("shield", c.pos)
	return true


# ---- 파이로맨서
static func pyro_stage_time(c, stage: int) -> float:
	var t := 0.45 if stage == 1 else 1.4
	if c.quick_cast_t > 0.0:
		t *= 0.5
	return t


static func _pyroblast(c, aim: Dictionary, charge: float) -> bool:
	# charge: 누른 시간 (초)
	var g = c.game
	if charge < pyro_stage_time(c, 1):
		return false
	var stage2: bool = charge >= pyro_stage_time(c, 2)
	if not pay(c, 35.0 if stage2 else 15.0):
		return false
	c.quick_cast_t = 0.0
	if stage2:
		g.spawn_projectile(c, "pyroblast", aim.origin, aim.dir, 22.0, 182.82 * c.dmg_mul(), {"aoe": 4.5, "dtype": "fire", "burn": 5 if has_fx(c, "ignite") else 0, "fire_aoe": true})
	else:
		for i in 3:
			var dir: Vector3 = aim.dir.rotated(Vector3.UP, (i - 1) * 0.16)
			dir.y += 0.04 * i
			g.spawn_projectile(c, "firebolt", aim.origin + Vector3(0, 0.1 * i, 0), dir.normalized(), 26.0, 45.70 * c.dmg_mul(), {"homing": 5.0, "dtype": "fire"})
	if has_fx(c, "fire_eye"):
		g.add_zone({"follow": c, "radius": 6.0, "dur": 8.0, "tick": 1.0, "dmg": 10.0, "burn": 3, "owner": c, "kind": "fire_eye", "dtype": "fire", "nearest": true})
	return true


static func _fireshock(c) -> bool:
	if not pay(c, Data.SKILLS.pyro_fireshock.cost):
		return false
	var g = c.game
	var hits := 0
	for a in g.actors:
		if not a.alive or a.extracted or not g.hostile(c, a):
			continue
		var dx: float = a.pos.x - c.pos.x
		var dz: float = a.pos.z - c.pos.z
		var d := sqrt(dx * dx + dz * dz)
		if d > 5.5 + a.radius or not g.dungeon.los(c.pos.x, c.pos.z, a.pos.x, a.pos.z):
			continue
		var nd := maxf(d, 0.001)
		g.hit(c, a, 48.82 * c.dmg_mul(), {"knock": Vector3(dx / nd * 16.0, 0, dz / nd * 16.0), "from": c.pos, "dtype": "fire"})
		a.add_slow(1.0, 0.15)
		if has_fx(c, "ignite"):
			a.add_burn(5, c)
		hits += 1
	if hits and has_fx(c, "quick_cast"):
		c.quick_cast_t = 10.0
	if has_fx(c, "fire_heal"):
		c.heal_now(minf(200.0, 50.0 + 50.0 * hits))
	g.spawn_ring_burst(c.pos + Vector3(0, 0.6, 0), FIRE, 5.5)
	g.explode_fx(c.pos + Vector3(0, 0.8, 0), 2.0, FIRE)
	g.sfx("fire", c.pos)
	return true


# ---- 로그
static func _petrify(c) -> bool:
	c.petrify_coat = 12.0
	c.game.notify(c, "toast", ["무기에 석화 독을 발랐습니다"])
	c.game.sfx("magic", c.pos)
	return true


static func _blades(c, aim: Dictionary) -> bool:
	var g = c.game
	for i in 6:
		var dir: Vector3 = aim.dir.rotated(Vector3.UP, (i - 2.5) * 0.12)
		g.spawn_projectile(c, "knife", aim.origin, dir.normalized(), 40.0, 8.60 * c.dmg_mul(), {"slow": 3.0, "slow_mul": 0.3, "gravity": 2.0})
	if has_fx(c, "formless"):
		enter_stealth(c, 6.0)
	return true


static func _stealth(c, prep: float, kind: String) -> bool:
	c.channel_t = prep
	c.channel_kind = kind
	c.break_stealth()
	c.game.notify(c, "toast", ["은신 준비 중... (피격 시 취소)" if kind == "stealth" else "어둠의 장막 준비 중..."])
	return true


static func _quick_conceal(c) -> bool:
	enter_stealth(c, 6.0)
	return true


static func enter_stealth(c, t: float) -> void:
	c.stealth = maxf(c.stealth, t)
	if has_fx(c, "feather"):
		c.add_speed(200.0, 5.0, true)
	c.game.sfx("magic", c.pos, 0.0)


# 은신 준비 진행 (매 프레임)
static func tick_channel(c, dt: float) -> void:
	if c.channel_t <= 0.0:
		return
	c.channel_t -= dt
	if c.channel_t <= 0.0:
		if c.channel_kind == "veil":
			for a in c.game.actors:
				if a.alive and (a == c or (a.faction == c.faction and a.kind in ["player", "bot"])) and a.pos.distance_to(c.pos) < 8.0:
					if a == c:
						enter_stealth(c, 15.0)
					else:
						a.stealth = maxf(a.stealth, 15.0)
			c.game.notify(c, "toast", ["어둠의 장막: 주변 아군 은신"])
		else:
			enter_stealth(c, 30.0)
			c.game.notify(c, "toast", ["은신! (치명타 피해 증가)"])


# ---- 데스나이트
static func _wraith_guard(c) -> bool:
	if not pay(c, Data.SKILLS.dk_wraith_guard.cost):
		return false
	var g = c.game
	for a in g.actors:
		if a.alive and g.hostile(c, a) and a.pos.distance_to(c.pos) < 5.0:
			a.add_slow(1.0, 0.75)
	g.add_zone({"follow": c, "radius": 4.5, "dur": 6.0, "tick": 1.0, "dmg": 27.20 * c.dmg_mul(), "owner": c, "kind": "soul_shroud", "dtype": "shadow"})
	c.add_dr("wraith", 0.15, 6.0)
	g.sfx("growl", c.pos)
	return true


static func _soul_storm(c) -> bool:
	if c.res < 10.0:
		c.game.notify(c, "toast", ["영혼 에너지가 부족합니다"])
		return false
	c.soul_storm = true
	c.storm_tick = 0.0
	c.game.add_zone({"follow": c, "radius": 5.0, "dur": 999.0, "tick": 0.5, "dmg": 13.60 * c.dmg_mul(), "owner": c, "kind": "soul_storm", "dtype": "shadow",
		"slow": 0.5 if has_fx(c, "decay") else 0.0, "slow_mul": 0.85})
	if has_fx(c, "soul_shield") and c.soul_shield_cd <= 0.0:
		c.soul_shield_cd = 30.0
		c.give_shield(200.0, 3.0, SOUL)
	c.game.sfx("magic", c.pos)
	return true


static func stop_soul_storm(c) -> void:
	c.soul_storm = false
	c.game.end_zone(c, "soul_storm")


# 영혼폭풍 유지: 영혼 에너지 소모, 받는 피해 15% 감소
static func tick_soul_storm(c, dt: float) -> void:
	if not c.soul_storm:
		return
	c.res -= 10.0 * dt
	c.add_dr("storm", 0.15, 0.2)
	if c.res <= 0.0 or not c.alive or c.incapacitated():
		c.res = maxf(0.0, c.res)
		stop_soul_storm(c)


static func _soul_chain(c, aim: Dictionary) -> bool:
	c.game.spawn_projectile(c, "grasp", aim.origin, aim.dir, 34.0, 73.38 * c.dmg_mul(), {"pull": true, "life": 0.7, "dtype": "shadow", "soul_gain": 30.0 if has_fx(c, "soul_harvest") else 10.0})
	c.game.sfx("magic", c.pos)
	return true


# ---- 크라이오맨서
static func _blizzard(c, aim: Dictionary) -> bool:
	if not pay(c, Data.SKILLS.cryo_blizzard.cost):
		return false
	var g = c.game
	var target: Vector3 = aim.get("point", g.aim_point(aim.origin, aim.dir, 22.0))
	var start: Vector3 = c.pos + Actor.fwd(c.yaw) * 2.0
	start = g.dungeon.resolve_circle(start, 0.5)
	g.add_zone({"pos": start, "move_to": target, "speed": 6.0, "radius": 2.5, "dur": 6.5, "move_dur": 3.0, "tick": 0.5,
		"dmg": 6.55 * c.dmg_mul(), "slow": 0.6, "slow_mul": 0.6, "owner": c, "kind": "ice_storm", "dtype": "cold",
		"end_radius": 4.5, "end_dmg": 9.83 * c.dmg_mul(), "end_slow_mul": 0.2, "blizzard": true})
	g.sfx("magic", target)
	return true


static func _frost_curse(c, aim: Dictionary) -> bool:
	if not pay(c, Data.SKILLS.cryo_frost_curse.cost):
		return false
	var mult := 1.5 if has_fx(c, "bitter_cold") else 1.0
	c.game.spawn_projectile(c, "icebolt", aim.origin, aim.dir, 38.0, 24.56 * mult * c.dmg_mul(), {"slow": 1.0, "slow_mul": 0.4, "curse": true, "dtype": "cold", "far_bonus": has_fx(c, "extreme_cold")})
	return true


static func _ice_armor(c, aim: Dictionary) -> bool:
	if not pay(c, Data.SKILLS.cryo_ice_armor.cost):
		return false
	var t = null if aim.get("self", false) else _aimed_ally(c, aim)
	if t == null:
		t = c
	var amt = 150.63 + c.frost_scale * 0.5
	c.frost_scale = 0
	t.give_shield(amt, 60.0, FROST)
	t.ice_armor = true
	c.game.spawn_ring_burst(t.pos + Vector3(0, 1.0, 0), FROST, 2.0)
	c.game.sfx("shield", t.pos)
	return true


static func _ice_barrier(c) -> bool:
	c.cleanse()
	c.frozen = 8.0
	c.barrier = true
	c.game.on_frozen(c)
	c.game.sfx("shield", c.pos)
	return true


# 얼음 베리어 중 초당 2.61% 회복
static func tick_barrier(c, dt: float) -> void:
	if c.barrier:
		if c.frozen <= 0.0:
			c.barrier = false
		else:
			c.heal_now(c.max_hp * 0.0261 * dt)


# ---- 소드마스터
const PSI_STEP := 0.55 # 검 한 자루 소환 시간


static func tick_psionic(c, dt: float) -> void:
	if not c.psi_on:
		return
	var mx := sword_count(c)
	if mx <= 0 or c.incapacitated():
		cancel_psionic(c)
		return
	if c.psi_n < mx:
		c.psi_t += dt
		if c.psi_t >= PSI_STEP:
			c.psi_t = 0.0
			c.psi_n += 1
			c.game.sfx("magic", c.pos, 0.1)
	elif not (c is Player):
		# AI: 다 모으면 바로 발사
		fire_psionic(c, c.psi_aim)


static func fire_psionic(c, aim: Dictionary) -> bool:
	if not c.psi_on or c.psi_n <= 0:
		return false
	var n: int = c.psi_n
	_psionic(c, aim, n)
	c.cd.q = _psionic_cd(c, n)
	c.psi_on = false
	c.psi_n = 0
	return true


static func cancel_psionic(c) -> void:
	c.psi_on = false
	c.psi_n = 0
	c.psi_t = 0.0


static func _psionic_cd(c, n: int) -> float:
	var base: float = [6.0, 6.0, 10.0, 15.0, 20.0][clampi(n, 0, 4)]
	if has_fx(c, "blade_storm"):
		if n == 3:
			base = 10.0
		elif n == 4:
			base = 15.0
	return base * c.stats.get("cd_mul", 1.0)


static func _psionic(c, aim: Dictionary, n: int) -> bool:
	var g = c.game
	var slots := []
	for s in Data.SWORD_SLOTS:
		if c.equipment.get(s) != null:
			slots.append(c.equipment[s])
	for i in n:
		var sword: Dictionary = slots[i]
		var bonus := 1.2 if int(sword.get("rarity", 0)) >= 2 else 1.0
		var off := (i - (n - 1) / 2.0) * 0.18
		var dir: Vector3 = aim.dir.rotated(Vector3.UP, off)
		dir.y += 0.08
		g.spawn_projectile(c, "blade", aim.origin + Vector3(0, 0.15 * (i % 2), 0), dir.normalized(), 24.0 + i * 2.0, 62.75 * bonus * c.dmg_mul(),
			{"homing": 6.0, "life": 3.0, "psionic": true})
	g.sfx("magic", c.pos)
	return true


static func _blade_dance(c) -> bool:
	c.game.add_zone({"follow": c, "radius": 2.6, "dur": 8.0, "tick": 0.5, "dmg": 35.30 * c.dmg_mul(), "owner": c, "kind": "orbit_blade"})
	if has_fx(c, "evasion"):
		c.add_dr("evasion", 0.5, 8.0)
	c.game.sfx("swing", c.pos)
	return true


# ---- 드루이드
static func set_panther(c, on: bool) -> void:
	if c.panther == on:
		return
	c.panther = on
	c.game.on_shapeshift(c)
	c.game.sfx("growl", c.pos)


static func _toggle_panther(c) -> bool:
	if wcat(c) == "" and Data.offhand_cat(c.equipment, c.wset) == "":
		c.game.notify(c, "toast", ["무기를 착용해야 변신할 수 있습니다"])
		return false
	c.cleanse()
	set_panther(c, true)
	c.game.spawn_ring_burst(c.pos + Vector3(0, 0.3, 0), NATURE, 2.0)
	return true


static func _nature(c, aim: Dictionary) -> bool:
	if c.charges <= 0:
		c.game.notify(c, "toast", ["'자연의 힘' 충전 중 (%.0f초)" % c.charge_cd])
		return false
	var g = c.game
	var p: Vector3 = aim.get("point", g.aim_point(aim.origin, aim.dir, 14.0))
	p = g.dungeon.resolve_circle(p, 0.8)
	c.charges -= 1
	if c.charge_cd <= 0.0:
		c.charge_cd = nature_recharge(c)
	g.spawn_summon(c, p)
	c.give_shield(60.0 + (150.0 if has_fx(c, "nature_breath") else 0.0), 10.0, NATURE)
	gain(c, 15.0)
	g.sfx("heal", p)
	return true


static func _shadow_assault(c) -> bool:
	if not pay(c, Data.SKILLS.druid_shadow_assault.cost):
		return false
	c.dash = {"dir": Actor.fwd(c.yaw), "speed": 20.0, "t": 0.42, "land": 74.43 * c.dmg_mul(), "hit_done": false}
	c.game.sfx("growl", c.pos)
	return true


# 돌진류 진행. 이동 처리 후 true면 돌진 중
static func tick_dash(c, dt: float) -> bool:
	if c.dash == null:
		return false
	var dash: Dictionary = c.dash
	dash.t -= dt
	c.move(dash.dir.x * dash.speed, dash.dir.z * dash.speed, dt)
	if dash.t <= 0.0:
		# 그림자 돌격: 착지 지점 주변 피해
		if dash.has("land"):
			var g = c.game
			var hits := 0
			for a in g.actors:
				if a.alive and not a.extracted and g.hostile(c, a) and a.pos.distance_to(c.pos) < 3.0 + a.radius:
					g.hit(c, a, dash.land, {"knock": (a.pos - c.pos).normalized() * 6.0, "from": c.pos, "dtype": "shadow"})
					hits += 1
			if hits:
				gain(c, 20.0 if has_fx(c, "prey_aim") else 0.0)
				gain(c, 20.0)
				g.sfx("hit", c.pos)
				g.notify(c, "shake", [0.25])
				g.summon_focus(c)
			g.spawn_ring_burst(c.pos + Vector3(0, 0.3, 0), SHADOW, 3.0)
		c.dash = null
	return true
