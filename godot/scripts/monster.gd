# 몬스터 (던전본 몬스터 목록, Data.MONSTERS)
# AI 종류: melee 근접 · shield 방패 · ranged 원거리 · caster 마법(마법진/마법탄) · charge 돌진
#          fleeing 도망치는 근접 · stinger 멈춰서 침 · emerge 땅속 잠복 · mimic 상자 위장 · harmless 무해
class_name Monster
extends AIActor

const CREATURES := ["giant_bat", "giant_beetle", "giant_rat", "boar", "demon_eye", "tentacle", "mimic", "mimic_book", "pest"]

var type := ""
var def: Dictionary
var ai := "melee"
var power_mul := 1.0
var home: Dictionary
var home_pos := Vector3.ZERO
var wander_t := 0.0
var wander_goal = null
var lost_t := 0.0
var slam_cd := 6.0
var windup_kind := ""
var combo_left := 0
var flee_t := 0.0 # 도망 중
var fled := false
var dash_t := 0.0 # 돌진 중
var dash_dir := Vector3.ZERO
var dash_hit := false
var recover_t := 0.0 # 공격 후 경직
var hidden := false # 땅속 잠복 / 상자 위장
var emerge_t := 0.0
var guard := 0 # 방패: 막을 수 있는 남은 횟수
var guard_cd := 0.0
var blast: Array = [] # 악마의 눈 마법진 [위치, 남은 시간]
var bob := 0.0
var summoned := false # 미믹 플라스크로 불러낸 내 편 미믹 (전리품 없음)
var life := -1.0


func _init(g, t: String, p: Vector3, room: Dictionary, depth_mul := 1.0) -> void:
	var d: Dictionary = Data.MONSTERS[t]
	var fly: float = d.get("fly", 0.0)
	super(g, {
		"kind": "monster", "name": d.name, "faction": "monster", "pos": p,
		"hp": roundf(d.hp * depth_mul), "radius": 0.45 * d.scale, "height": 1.9 * d.scale + fly * 0.5,
		"armor": 30.0 if d.boss else (20.0 if d.get("elite", false) else 0.0),
	})
	type = t
	def = d
	ai = d.get("ai", "melee")
	power_mul = depth_mul
	home = room
	home_pos = p
	wander_t = randf() * 4.0
	bob = randf() * TAU
	yaw = randf() * TAU
	attach_rig(build_rig(t))
	if d.boss or d.get("elite", false):
		hp_bar.scale = Vector3(2, 2, 2)
	if ai == "shield":
		guard = 3
		block_mul = 0.1
	if ai in ["emerge", "mimic"]:
		hidden = true
		stealth = 999.0 if ai == "emerge" else 0.0


# 몬스터 모델 (멀티플레이 클라이언트의 대리 액터도 사용)
static func build_rig(t: String) -> CharacterRig:
	var d: Dictionary = Data.MONSTERS[t]
	var builder: Callable
	if t in CREATURES:
		builder = func(): return Models.creature(t)
	elif t == "treant_wild":
		return Models.treant_rig()
	else:
		var look: Dictionary = {
			"skeleton_swordsman": {"skeletal": true, "head": Color(0.88, 0.85, 0.75), "body": Color(0.72, 0.69, 0.6), "weapon": "sword", "eyes": Color(1, 0.27, 0.13)},
			"skeleton_spearman": {"skeletal": true, "head": Color(0.88, 0.85, 0.75), "body": Color(0.7, 0.66, 0.58), "weapon": "staff", "eyes": Color(1, 0.27, 0.13)},
			"skeleton_warrior": {"skeletal": true, "head": Color(0.88, 0.85, 0.75), "body": Color(0.6, 0.58, 0.5), "weapon": "sword", "shield": true, "helmet": Color(0.4, 0.4, 0.42), "eyes": Color(1, 0.27, 0.13)},
			"skeleton_archer": {"skeletal": true, "head": Color(0.88, 0.85, 0.75), "body": Color(0.66, 0.63, 0.54), "weapon": "bow", "eyes": Color(0.27, 1, 0.4)},
			"zombie": {"skin": Color(0.42, 0.52, 0.36), "body": Color(0.3, 0.28, 0.22), "legs": Color(0.22, 0.2, 0.16), "weapon": "claws", "eyes": Color(0.9, 0.9, 0.2), "hunch": 0.4},
			"goblin_axeman": {"skin": Color(0.36, 0.54, 0.23), "body": Color(0.35, 0.25, 0.16), "legs": Color(0.23, 0.16, 0.09), "weapon": "club", "scale": 0.75, "head_scale": 1.35, "eyes": Color(1, 0.93, 0)},
			"goblin_thief": {"skin": Color(0.33, 0.5, 0.22), "body": Color(0.18, 0.16, 0.14), "legs": Color(0.15, 0.12, 0.1), "weapon": "dagger", "scale": 0.72, "head_scale": 1.35, "eyes": Color(1, 0.93, 0)},
			"goblin_crossbowman": {"skin": Color(0.38, 0.55, 0.25), "body": Color(0.4, 0.3, 0.18), "legs": Color(0.23, 0.16, 0.09), "weapon": "bow", "scale": 0.75, "head_scale": 1.35, "eyes": Color(1, 0.93, 0)},
			"living_armor_warrior": {"skin": Color(0.3, 0.32, 0.36), "body": Color(0.4, 0.42, 0.48), "legs": Color(0.32, 0.33, 0.38), "helmet": Color(0.42, 0.44, 0.5), "weapon": "sword", "shield": true, "metal": 0.8, "eyes": Color(0.4, 0.7, 1.0)},
			"living_armor_swordsman": {"skin": Color(0.3, 0.32, 0.36), "body": Color(0.44, 0.42, 0.5), "legs": Color(0.32, 0.33, 0.38), "helmet": Color(0.42, 0.44, 0.5), "weapon": "longsword", "metal": 0.8, "eyes": Color(0.4, 0.7, 1.0)},
			"apparition": {"skin": Color(0.55, 0.7, 0.9), "body": Color(0.35, 0.45, 0.65), "legs": Color(0.25, 0.3, 0.45), "weapon": "claws", "eyes": Color(0.7, 0.9, 1.0), "hunch": 0.3},
			"khazra": {"skin": Color(0.55, 0.3, 0.25), "body": Color(0.35, 0.18, 0.12), "legs": Color(0.25, 0.14, 0.1), "weapon": "greatsword", "scale": 1.25, "eyes": Color(1, 0.4, 0.1)},
			"reaper": {"skin": Color(0.15, 0.13, 0.18), "body": Color(0.1, 0.09, 0.12), "legs": Color(0.08, 0.07, 0.1), "helmet": Color(0.12, 0.1, 0.14), "weapon": "staff", "scale": 1.4, "eyes": Color(0.6, 1.0, 0.4)},
			"headsman": {"skin": Color(0.5, 0.38, 0.3), "body": Color(0.2, 0.15, 0.12), "legs": Color(0.18, 0.13, 0.1), "helmet": Color(0.12, 0.1, 0.1), "weapon": "boss_sword", "scale": 1.45, "eyes": Color(1, 0.13, 0), "metal": 0.3},
		}.get(t, {"skin": Color(0.5, 0.5, 0.5)})
		builder = func(): return Models.humanoid(look)
	var r := CharacterRig.create(t, builder)
	if not r.procedural and not AssetRegistry.config("characters", t).has("scale"):
		r.node.scale = Vector3.ONE * float(d.scale)
	return r


func on_hurt(src) -> void:
	if src != null and src.alive and hostile_to(src):
		if target == null or randf() < 0.5:
			target = src
		lost_t = 0.0
	if hidden:
		_reveal()
	# 도망치는 몬스터: 체력이 낮아지면 한동안 도망
	if not fled and (ai == "fleeing" or ai == "harmless" or def.get("flee", false)) and hp < max_hp * (0.95 if ai == "harmless" else 0.4):
		fled = ai != "harmless"
		flee_t = randf_range(3.0, 4.5)


func on_block(_amount: float) -> void:
	if ai == "shield":
		guard -= 1
		if guard <= 0:
			# 방패가 무너짐: 잠시 기절
			blocking = false
			guard_cd = 4.0
			add_stun(1.5)
			game.sfx("shield_break", pos)


func _reveal() -> void:
	if not hidden:
		return
	hidden = false
	stealth = 0.0
	emerge_t = 0.9 if ai == "emerge" else 0.4
	game.sfx("growl", pos)


func animate(dt: float) -> void:
	super(dt)
	var r := active_rig()
	var fly: float = def.get("fly", 0.0)
	if fly > 0.0 and alive:
		bob += dt * 3.0
		r.node.position.y = fly + sin(bob) * 0.15
		var p: Dictionary = r.parts
		if p.has("arm_l") and type == "giant_bat":
			p.arm_l.rotation.z = sin(bob * 6.0) * 0.8
			p.arm_r.rotation.z = -sin(bob * 6.0) * 0.8
	elif hidden and ai == "emerge":
		r.node.position.y = -1.6
	elif emerge_t > 0.0:
		r.node.position.y = -1.6 * (emerge_t / 0.9)
	if type == "mimic" and r.parts.has("arm_r"):
		# 미믹 뚜껑: 위장 중에는 닫힘, 공격할 때 크게 벌림
		var open := 0.0 if hidden else (0.9 if windup > 0.0 or attack_anim > 0.0 else 0.35 + sin(bob * 4.0) * 0.1)
		bob += dt
		r.parts.arm_r.rotation.x = lerpf(r.parts.arm_r.rotation.x, -open, minf(1.0, dt * 10.0))


func update(dt: float) -> void:
	tick_common(dt)
	if not alive:
		return
	if life > 0.0:
		life -= dt
		if life <= 0.0:
			alive = false
			hp = 0.0
			game.on_death(self, null)
			return
	_tick_blasts(dt)
	# 멀리 있으면 휴면
	if game.nearest_adventurer_dist(pos) > 50.0:
		move_amt = 0.0
		return
	if atk_cd > 0.0:
		atk_cd -= dt
	if guard_cd > 0.0:
		guard_cd -= dt
		if guard_cd <= 0.0:
			guard = 3
	if stun > 0.0 or petrified > 0.0:
		windup = 0.0
		dash_t = 0.0
		move_amt = 0.0
		blocking = false
		return
	if emerge_t > 0.0:
		emerge_t -= dt
		move_amt = 0.0
		return
	if dash_t > 0.0:
		_tick_dash(dt)
		return
	if recover_t > 0.0:
		recover_t -= dt
		move_amt = 0.0
		return
	sense_timer -= dt
	if sense_timer <= 0.0:
		sense_timer = 0.35
		_sense()
	if hidden:
		move_amt = 0.0
		return
	if flee_t > 0.0:
		flee_t -= dt
		blocking = false
		var away = target if target != null else null
		if away != null:
			var dx: float = pos.x - away.pos.x
			var dz: float = pos.z - away.pos.z
			var d := maxf(0.1, sqrt(dx * dx + dz * dz))
			nav_to(pos + Vector3(dx / d, 0, dz / d) * 6.0, def.speed * 1.15, dt, 0.3)
		else:
			move_amt = 0.0
		return
	if target != null:
		_fight(dt)
	else:
		_wander(dt)


func _sense() -> void:
	if ai == "harmless":
		return
	var rng: float = def.sight
	if hidden:
		rng = 3.2 if ai == "mimic" else 6.0
	var t = sense(rng)
	if t != null and (target == null or not target.alive):
		target = t
		if hidden:
			_reveal()
		elif randf() < 0.5:
			game.sfx("growl", pos)
	if target != null and (not target.alive or target.extracted or target.stealth > 0.0):
		target = null


func _wander(dt: float) -> void:
	aim_anim = false
	blocking = false
	if def.get("rooted", false) or hidden:
		move_amt = 0.0
		return
	wander_t -= dt
	if wander_goal == null or wander_t <= 0.0:
		wander_t = randf_range(3.0, 8.0)
		wander_goal = null if randf() < 0.4 else game.dungeon.random_point_in_room(home, 1)
		if pos.distance_to(home_pos) > 20.0:
			wander_goal = home_pos
	if wander_goal != null:
		if nav_to(wander_goal, def.speed * 0.4, dt, 0.8):
			wander_goal = null
	else:
		move_amt = 0.0


func _fight(dt: float) -> void:
	var tg = target
	var dx: float = tg.pos.x - pos.x
	var dz: float = tg.pos.z - pos.z
	var d := sqrt(dx * dx + dz * dz)
	var seen: bool = game.dungeon.los(pos.x, pos.z, tg.pos.x, tg.pos.z)
	lost_t = 0.0 if seen else lost_t + dt
	if lost_t > 7.0 or d > 45.0:
		target = null
		return
	if windup > 0.0:
		windup -= dt
		move_amt = 0.0
		turn_to(yaw_to(dx, dz), dt, 2.5 if def.boss else 4.0)
		if windup <= 0.0:
			release_attack()
		return
	var rooted: bool = def.get("rooted", false)
	if def.boss:
		slam_cd -= dt
		if slam_cd <= 0.0 and d < 7.0:
			slam_cd = randf_range(7.0, 10.0)
			start_windup(1.1, "slam")
			return
	match ai:
		"ranged", "caster":
			var rng: float = def.range
			aim_anim = d < rng and seen and ai == "ranged"
			if d < rng and seen:
				turn_to(yaw_to(dx, dz), dt)
				if d < 4.5 and not rooted:
					move(-dx / d * def.speed * 0.7, -dz / d * def.speed * 0.7, dt)
				else:
					move_amt = 0.0
				if atk_cd <= 0.0:
					start_windup(0.9 if ai == "caster" else 0.7, "blast" if type == "demon_eye" else ("orb" if ai == "caster" else "shoot"))
			else:
				nav_to(tg.pos, def.speed, dt, 1.0)
		"charge":
			# 거리를 둔 뒤 예고하고 일직선으로 돌진
			if d < 9.0 and d > 2.5 and seen and atk_cd <= 0.0:
				start_windup(0.75, "dash")
				game.spawn_telegraph(pos + Vector3(dx / d, 0, dz / d) * minf(d + 2.0, 9.0) * 0.5, 1.2, 0.75)
			elif d <= 2.5 and atk_cd <= 0.0:
				start_windup(0.5, "melee")
			elif d < 4.0 and atk_cd > 0.0:
				# 다음 돌진 준비: 물러남
				move(-dx / d * def.speed * 0.6, -dz / d * def.speed * 0.6, dt)
				turn_to(yaw_to(dx, dz), dt)
			else:
				nav_to(tg.pos, def.speed, dt, 2.0)
		"stinger":
			if d < 5.5 and seen:
				move_amt = 0.0
				turn_to(yaw_to(dx, dz), dt)
				if atk_cd <= 0.0:
					start_windup(0.8, "sting")
			else:
				nav_to(tg.pos, def.speed, dt, 1.0)
		"harmless":
			_wander(dt)
		_:
			# melee / shield / fleeing / emerge / mimic
			blocking = ai == "shield" and guard > 0 and d < 8.0
			if d < def.range * 0.85 + tg.radius and seen:
				move_amt = 0.0
				turn_to(yaw_to(dx, dz), dt)
				if atk_cd <= 0.0:
					combo_left = int(def.get("combo", 1)) - 1
					start_windup(0.7 if def.boss else 0.5, "melee")
			elif not rooted:
				nav_to(tg.pos, def.speed * (0.75 if blocking else 1.0), dt, 0.5)
			else:
				move_amt = 0.0
				turn_to(yaw_to(dx, dz), dt)


func start_windup(time: float, k: String) -> void:
	windup = time
	windup_max = time
	windup_kind = k
	blocking = false
	if k == "slam":
		game.spawn_telegraph(pos, 5.5, time)


func release_attack() -> void:
	var dmg: float = def.dmg * power_mul
	attack_anim = 0.25
	match windup_kind:
		"shoot":
			atk_cd = def.cd
			if target != null:
				game.shoot_at(self, target, "arrow", dmg, 32.0, 0.04)
		"orb":
			atk_cd = def.cd
			if target != null:
				game.shoot_at(self, target, "magic_orb", dmg, 16.0, 0.03)
		"sting":
			atk_cd = def.cd
			recover_t = 1.0
			if target != null:
				var from := pos + Vector3(0, 0.5, 0) + Actor.fwd(yaw) * 0.6
				var to: Vector3 = target.center()
				game.spawn_projectile(self, "spit", from, (to - from).normalized(), 18.0, dmg, {"dot": dmg * 0.25, "slow": 1.0})
		"blast":
			# 악마의 눈: 대상 발밑에 마법진 → 잠시 뒤 폭발
			atk_cd = def.cd
			if target != null:
				var p: Vector3 = Vector3(target.pos.x, 0, target.pos.z)
				blast.append([p, 1.3])
				game.spawn_telegraph(p, 2.6, 1.3)
		"dash":
			atk_cd = def.cd
			dash_t = 0.55
			dash_hit = false
			dash_dir = Actor.fwd(yaw)
			game.sfx("swing", pos)
		"slam":
			atk_cd = 1.0
			game.explode(pos, 5.5, dmg * 1.3, self, "slam")
		_:
			game.sfx("swing", pos)
			var heavy := combo_left == 0 and int(def.get("combo", 1)) > 1
			game.melee_hit(self, dmg * (1.4 if heavy else 1.0), def.range + 0.3, 2.2 if type == "reaper" else 1.4, {"knock": 9.0 if def.boss else 3.0})
			if combo_left > 0:
				combo_left -= 1
				start_windup(0.35, "melee")
				attack_anim = 0.25
			else:
				atk_cd = def.cd


func _tick_dash(dt: float) -> void:
	dash_t -= dt
	var sp: float = def.speed * 3.2
	var before := pos
	move(dash_dir.x * sp, dash_dir.z * sp, dt)
	turn_to(atan2(-dash_dir.x, -dash_dir.z), dt, 20.0)
	if not dash_hit:
		for a in game.actors:
			if a.alive and not a.extracted and game.hostile(self, a) and a.pos.distance_to(pos) < radius + a.radius + 0.4:
				dash_hit = true
				game.hit(self, a, def.dmg * power_mul * 1.3, {"from": pos, "knock": dash_dir * 7.0})
				game.sfx("hit", pos)
				break
	# 벽에 막히거나 맞히면 멈추고 경직
	if dash_hit or pos.distance_to(before) < sp * dt * 0.3 or dash_t <= 0.0:
		dash_t = 0.0
		recover_t = 0.9 if not dash_hit else 0.6


func _tick_blasts(dt: float) -> void:
	for i in range(blast.size() - 1, -1, -1):
		blast[i][1] -= dt
		if blast[i][1] <= 0.0:
			game.explode(blast[i][0], 2.6, def.dmg * power_mul, self, "slam", {"dtype": "shadow"})
			blast.remove_at(i)
