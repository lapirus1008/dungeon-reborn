# 액터 공통: 체력, 피해 처리, 상태이상, 직업 자원, 이동
class_name Actor
extends RefCounted

var game # Game (순환 참조 방지를 위해 타입 미지정)
var nid := 0 # 네트워크 식별자
var kind := "" # "player" | "monster" | "bot" | "summon"
var name := ""
var faction := ""
var pos := Vector3.ZERO
var yaw := 0.0
var radius := 0.45
var height := 1.9
var max_hp := 100.0
var hp := 100.0
var armor := 0.0
var alive := true
var extracted := false
var knock := Vector3.ZERO
var last_attacker = null
var hit_flash := 0.0
var heal := 0.0
var heal_rate := 0.0
var death_t := 0.0
var move_amt := 0.0
var walk_phase := 0.0
var attack_anim := 0.0
var windup := 0.0
var windup_max := 1.0
var swinging := false
var last_vel := Vector3.ZERO
var last_pos := Vector3.ZERO

# 직업 (플레이어/봇)
var cls := ""
var stats: Dictionary = {}
var res := 0.0 # 마나/영혼/원시 에너지
var cd := {"lmb": 0.0, "rmb": 0.0, "q": 0.0, "e": 0.0, "potion": 0.0, "util": 0.0}
var skills: Dictionary = {} # {"q": 스킬 id, "e": 스킬 id}
var wset := 1 # 사용 중인 무기 세트
var channel_kind := "" # 은신 준비 종류 (stealth/veil)
var soul_storm := false
var storm_tick := 0.0
var barrier := false # 얼음 베리어
var charges := 1 # 자연의 힘 / 수호 충전
var charge_cd := 0.0
var pursuit_t := 0.0 # 승리의 추격
var quick_cast_t := 0.0 # 급속 시전
var petrify_coat := 0.0 # 석화 중독 발라 둔 시간
var soul_shield_cd := 0.0
var revive_used := false
var frost_scale := 0
var counter_ready := false # 방어 반격
var dash = null # {dir, speed, t, hit, hit_done, stun}
var spin_t := 0.0 # 파이터 회오리 베기
var spin_tick := 0.0
var panther := false # 드루이드 변신
var channel_t := 0.0 # 로그 은신 집중
var shield_t := 0.0
var shield_max := 50.0
var shield_color := Color(0.35, 0.65, 1.0)

# 상태이상
var stun := 0.0
var slow := 0.0
var slow_mul := 0.6
var root := 0.0
var stealth := 0.0
var frozen := 0.0 # 서리 장벽 (무적, 행동 불가)
var parry := 0.0
var immune := 0.0 # 해로운 효과 면역
var dr := 0.0 # 받는 피해 감소율
var dr_t := 0.0
var invuln := 0.0
var shield := 0.0
var blocking := false
var block_mul := 0.25
var dots: Array = [] # {dps, t, src}
# 던전본 스킬 상태
var burn := 0 # 연소 중첩 (2초마다 1중첩 제거, 10 화염 피해)
var burn_t := 0.0
var burn_src = null
var petrified := 0.0 # 석화: 행동 불가, 피해 무효, 공격받으면 해제
var curse_t := 0.0 # 서리의 저주
var curse_src = null
var curse_dps := 0.0
var speed_buffs: Array = [] # {v: 이동 속도 포인트, t, dur, decay}
var dr_list := {} # 피해 감소 출처 -> [비율, 남은 시간]
var warcry_t := 0.0 # 광기의 포효
var ice_armor := false # 아이스 아머 근접 반격 둔화 (1회)
var combat_t := 99.0 # 마지막 전투 후 시간
var pity_used := false
var dragon_cd := 0.0
var dragon_hits := 0
var vuln_t := 0.0 # 취약 (받는 피해 +20%)


func _init(g, o: Dictionary) -> void:
	game = g
	kind = o.kind
	name = o.name
	faction = o.faction
	pos = o.pos
	pos.y = 0.0
	last_pos = pos
	yaw = randf() * TAU
	radius = o.get("radius", 0.45)
	height = o.get("height", 1.9)
	max_hp = o.hp
	hp = o.hp
	armor = o.get("armor", 0.0)


func display_name() -> String:
	return name


func center() -> Vector3:
	return Vector3(pos.x, pos.y + height * 0.6, pos.z)


static func yaw_to(dx: float, dz: float) -> float:
	return atan2(-dx, -dz)


static func fwd(y: float) -> Vector3:
	return Vector3(-sin(y), 0, -cos(y))


func is_hero() -> bool:
	return cls != ""


func res_type() -> String:
	return stats.get("res", "")


func res_max() -> float:
	return stats.get("res_max", 0.0)


func dmg_mul() -> float:
	return stats.get("dmg_mul", 1.0)


# 스킬/공격 가능 여부 (기절·빙결·은신 집중 중 불가)
func incapacitated() -> bool:
	return stun > 0.0 or frozen > 0.0


func can_move() -> bool:
	return not incapacitated() and root <= 0.0 and channel_t <= 0.0


func speed_factor() -> float:
	var f := slow_mul if slow > 0.0 else 1.0
	var bonus := 0.0
	for b in speed_buffs:
		bonus += b.v * (b.t / b.dur if b.decay else 1.0)
	return maxf(0.2, f * (1.0 + bonus / 300.0))


# 이동 속도 증감 (던전본 이동 속도 포인트, 300 = 기본 속도)
func add_speed(v: float, t: float, decay := false) -> void:
	speed_buffs.append({"v": v, "t": t, "dur": t, "decay": decay})


func add_dr(key: String, amount: float, t: float) -> void:
	dr_list[key] = [amount, t]


func add_burn(stacks: int, src) -> void:
	if immune > 0.0 or frozen > 0.0:
		return
	burn = mini(10, burn + stacks)
	burn_src = src
	if burn_t <= 0.0:
		burn_t = 2.0


func petrify(t: float) -> void:
	if immune > 0.0 or frozen > 0.0:
		return
	petrified = t
	stun = maxf(stun, t)


# ------------------------------------------------------------------ 상태이상
func add_slow(t: float, mul := 0.55) -> void:
	if immune > 0.0 or frozen > 0.0:
		return
	if slow <= 0.0:
		slow_mul = mul
	else:
		slow_mul = minf(slow_mul, mul)
	slow = maxf(slow, t)


func add_root(t: float) -> void:
	if immune > 0.0 or frozen > 0.0 or panther:
		return
	root = maxf(root, t)


func add_stun(t: float) -> void:
	if immune > 0.0 or frozen > 0.0:
		return
	stun = maxf(stun, t)


func add_dot(dps: float, t: float, src) -> void:
	if immune > 0.0 or frozen > 0.0:
		return
	dots.append({"dps": dps, "t": t, "src": src})


func cleanse() -> void:
	slow = 0.0
	root = 0.0
	stun = 0.0
	dots.clear()
	burn = 0
	curse_t = 0.0
	petrified = 0.0
	speed_buffs = speed_buffs.filter(func(b): return b.v > 0)


func break_stealth() -> void:
	if stealth > 0.0:
		stealth = 0.0
		on_stealth_end()


func on_stealth_end() -> void:
	pass


func give_shield(amount: float, t: float, color := Color(0.35, 0.65, 1.0)) -> void:
	shield = maxf(shield, amount)
	shield_max = maxf(amount, 1.0)
	shield_t = t
	shield_color = color


# ------------------------------------------------------------------ 피해
func take_damage(amount: float, src, info: Dictionary = {}) -> float:
	if not alive or invuln > 0.0 or frozen > 0.0:
		return 0.0
	combat_t = 0.0
	# 석화: 공격을 받으면 해제되고 그 피해는 무효
	if petrified > 0.0:
		petrified = 0.0
		stun = 0.0
		hit_flash = 0.15
		return 0.0
	var from = info.get("from", src.pos if src != null else null)
	# 패링: 모든 피해 무효, 가까운 근접 공격자는 기절
	if parry > 0.0:
		game.sfx("block", pos)
		if src != null and src != self and src.pos.distance_to(pos) < 4.0 and not info.get("ranged", false):
			src.add_stun(1.2)
		on_parry(src)
		return 0.0
	var dmg := amount
	var blocked := false
	if blocking and from != null:
		var y := yaw_to(from.x - pos.x, from.z - pos.z)
		if absf(angle_difference(yaw, y)) < 1.25:
			blocked = true
			dmg *= block_mul
			on_block(amount)
			if is_hero():
				# 방어 반격: 블로킹 성공 시 다음 공격 치명타 / 고유 방패 효과
				if Skills.has_fx(self, "counter"):
					counter_ready = true
				var u: Array = stats.get("uniques", [])
				if "block_slow" in u and src != null and src != self:
					src.add_slow(1.5, 0.5)
				if "block_speed" in u:
					add_speed(150.0, 2.0, true)
	info["blocked"] = blocked
	var st: Dictionary = stats
	var dtype: String = info.get("dtype", "phys")
	if dtype == "phys":
		dmg *= 100.0 / (100.0 + armor)
		dmg *= 1.0 - st.get("pres", 0.0) - (0.3 if warcry_t > 0.0 else 0.0)
	elif dtype != "true":
		dmg *= 1.0 - st.get("mres", 0.0)
	if dr > 0.0:
		dmg *= 1.0 - dr
	for k in dr_list:
		dmg *= 1.0 - dr_list[k][0]
	if vuln_t > 0.0:
		dmg *= 1.2
	# 용비늘 세트: 피격 시 50% 감소 (60초마다, 2단계는 3회/3초)
	var dragon := Data.set_tier(st, "dragon") if st.has("sets") else 0
	if dragon > 0 and dmg > 0.0:
		if dragon_hits > 0:
			dmg *= 0.5
			dragon_hits -= 1
		elif dragon_cd <= 0.0:
			dmg *= 0.5
			dragon_cd = 30.0 if "cloudwall" in st.get("uniques", []) else 60.0
			dragon_hits = 2 if dragon >= 2 else 0
	var absorbed := 0.0
	if shield > 0.0:
		absorbed = minf(shield, dmg)
		shield -= absorbed
		dmg -= absorbed
		on_shield_hit(absorbed)
	dmg = maxf(0.0, dmg)
	# 아이스 아머: 근접 공격자 둔화 (1회)
	if ice_armor and absorbed > 0.0 and src != null and src != self and not info.get("ranged", false):
		ice_armor = false
		src.add_slow(2.0, 0.4)
	hp -= dmg
	hit_flash = 0.15
	if dmg > 0.0:
		break_stealth()
		channel_t = 0.0
	if src != null and src != self:
		last_attacker = src
	if info.has("knock") and not blocked:
		knock += info.knock
	if info.get("stun", 0.0) > 0.0 and not blocked:
		add_stun(info.stun)
	if info.get("slow", 0.0) > 0.0:
		add_slow(info.slow)
	info["absorbed"] = absorbed
	game.on_damage(self, dmg, src, blocked, info)
	on_hurt(src)
	if hp <= 0.0:
		# 죽음의 연민 세트: 치명상을 1회 버팀
		var pity := Data.set_tier(st, "pity") if st.has("sets") else 0
		if pity > 0 and not pity_used:
			pity_used = true
			hp = 70.0
			game.notify(self, "toast", ["죽음의 연민: 치명상을 버텼습니다"])
			return dmg
		hp = 0.0
		alive = false
		game.on_death(self, src)
	return dmg


func on_block(_amount: float) -> void:
	pass


func on_parry(_src) -> void:
	pass


func on_shield_hit(_amount: float) -> void:
	pass


func on_hurt(_src) -> void:
	pass


func apply_heal(amount: float, duration: float) -> void:
	heal += amount
	heal_rate = maxf(heal_rate, amount / duration)


func heal_now(amount: float) -> void:
	hp = minf(max_hp, hp + amount)


func tick_common(dt: float) -> void:
	for k in ["stun", "slow", "root", "invuln", "hit_flash", "parry", "immune"]:
		var v: float = get(k)
		if v > 0.0:
			set(k, v - dt)
	if frozen > 0.0:
		frozen -= dt
	combat_t += dt
	for k in ["petrified", "warcry_t", "dragon_cd", "vuln_t"]:
		var v2: float = get(k)
		if v2 > 0.0:
			set(k, v2 - dt)
	for k in dr_list.keys():
		dr_list[k][1] -= dt
		if dr_list[k][1] <= 0.0:
			dr_list.erase(k)
	if speed_buffs.size():
		for b in speed_buffs:
			b.t -= dt
		speed_buffs = speed_buffs.filter(func(b): return b.t > 0.0)
	# 연소: 2초마다 1중첩 제거하며 10 화염 피해
	if burn > 0:
		burn_t -= dt
		if burn_t <= 0.0:
			burn_t = 2.0
			burn -= 1
			if alive:
				take_damage(10.0, burn_src, {"dtype": "fire", "ranged": true, "dot": true})
	# 서리의 저주: 지속 피해, 시전자 회복
	if curse_t > 0.0:
		curse_t -= dt
		if alive:
			hp -= curse_dps * dt * (1.0 - stats.get("mres", 0.0))
			hit_flash = maxf(hit_flash, 0.02)
			if curse_src != null and curse_src.alive:
				curse_src.heal_now(6.55 * dt)
			if hp <= 0.0:
				hp = 0.0
				alive = false
				game.on_death(self, curse_src)
	# 비전투 생명력 재생
	if combat_t > 6.0 and stats.get("regen_ooc", 0.0) > 0.0 and alive:
		hp = minf(max_hp, hp + stats.regen_ooc * dt)
	if dr_t > 0.0:
		dr_t -= dt
		if dr_t <= 0.0:
			dr = 0.0
	if stealth > 0.0:
		stealth -= dt
		if stealth <= 0.0:
			on_stealth_end()
	if shield_t > 0.0:
		shield_t -= dt
		if shield_t <= 0.0:
			shield = 0.0
	if heal > 0.0:
		var h := minf(heal, heal_rate * dt)
		heal -= h
		hp = minf(max_hp, hp + h)
		if heal <= 0.0:
			heal_rate = 0.0
	# 지속 피해 (중독)
	var i := dots.size() - 1
	while i >= 0:
		var d: Dictionary = dots[i]
		d.t -= dt
		if alive:
			var dmg: float = d.dps * dt
			hp -= dmg
			if hp <= 0.0:
				hp = 0.0
				alive = false
				game.on_death(self, d.src)
		if d.t <= 0.0:
			dots.remove_at(i)
		i -= 1
	if knock.length_squared() > 0.001:
		pos.x += knock.x * dt
		pos.z += knock.z * dt
		knock *= maxf(0.0, 1.0 - dt * 8.0)
		pos = game.dungeon.resolve_circle(pos, radius)


func move(dx: float, dz: float, dt: float) -> void:
	if root > 0.0 or frozen > 0.0:
		return
	pos.x += dx * dt
	pos.z += dz * dt
	pos = game.dungeon.resolve_circle(pos, radius)


func update(_dt: float) -> void:
	pass
