# 몬스터: 스켈레톤 전사/궁수, 고블린, 구울, 보스 망령 기사
class_name Monster
extends AIActor

var type := ""
var def: Dictionary
var power_mul := 1.0
var home: Dictionary
var home_pos := Vector3.ZERO
var wander_t := 0.0
var wander_goal = null
var lost_t := 0.0
var slam_cd := 6.0
var windup_kind := ""


func _init(g, t: String, p: Vector3, room: Dictionary, depth_mul := 1.0) -> void:
	var d: Dictionary = Data.MONSTERS[t]
	super(g, {
		"kind": "monster", "name": d.name, "faction": "monster", "pos": p,
		"hp": roundf(d.hp * depth_mul), "radius": 0.45 * d.scale, "height": 1.9 * d.scale,
		"armor": 30.0 if d.boss else 0.0,
	})
	type = t
	def = d
	power_mul = depth_mul
	home = room
	home_pos = p
	wander_t = randf() * 4.0
	var m: Node3D
	match t:
		"skeleton":
			m = Models.humanoid({"skeletal": true, "head": Color(0.88, 0.85, 0.75), "body": Color(0.72, 0.69, 0.6), "weapon": "sword", "eyes": Color(1, 0.27, 0.13), "shield": randf() < 0.5})
		"skeleton_archer":
			m = Models.humanoid({"skeletal": true, "head": Color(0.88, 0.85, 0.75), "body": Color(0.66, 0.63, 0.54), "weapon": "bow", "eyes": Color(0.27, 1, 0.4)})
		"goblin":
			m = Models.humanoid({"skin": Color(0.36, 0.54, 0.23), "body": Color(0.35, 0.25, 0.16), "legs": Color(0.23, 0.16, 0.09), "weapon": "club", "scale": 0.75, "head_scale": 1.35, "eyes": Color(1, 0.93, 0)})
		"ghoul":
			m = Models.humanoid({"skin": Color(0.48, 0.54, 0.42), "body": Color(0.29, 0.31, 0.25), "legs": Color(0.23, 0.25, 0.19), "weapon": "claws", "scale": 1.1, "eyes": Color(1, 0, 0), "hunch": 0.5})
		_:
			m = Models.humanoid({"skin": Color(0.13, 0.13, 0.2), "body": Color(0.11, 0.11, 0.15), "legs": Color(0.08, 0.08, 0.11), "helmet": Color(0.16, 0.16, 0.21), "weapon": "boss_sword", "scale": 1.55, "eyes": Color(1, 0.13, 0), "metal": 0.6})
	attach_rig(CharacterRig.create(t, func(): return m))
	if d.boss:
		hp_bar.scale = Vector3(2, 2, 2)


func on_hurt(src) -> void:
	if src != null and src.alive and hostile_to(src):
		if target == null or randf() < 0.5:
			target = src
		lost_t = 0.0


func update(dt: float) -> void:
	tick_common(dt)
	if not alive:
		return
	# 멀리 있으면 휴면
	if game.nearest_adventurer_dist(pos) > 50.0:
		move_amt = 0.0
		return
	if atk_cd > 0.0:
		atk_cd -= dt
	if stun > 0.0:
		windup = 0.0
		move_amt = 0.0
		return
	sense_timer -= dt
	if sense_timer <= 0.0:
		sense_timer = 0.35
		var t = sense(def.sight)
		if t != null and (target == null or not target.alive):
			target = t
			if randf() < 0.5:
				Sfx.play("growl", game.dist_to_player(pos))
		if target != null and (not target.alive or target.extracted or (target.stealth > 0.0 and target.pos.distance_to(pos) > 3.0)):
			target = null
	if target != null:
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
		if def.boss:
			slam_cd -= dt
			if slam_cd <= 0.0 and d < 7.0:
				slam_cd = randf_range(7.0, 10.0)
				start_windup(1.1, "slam")
				return
		if def.ranged:
			aim_anim = d < def.range and seen
			if aim_anim:
				turn_to(yaw_to(dx, dz), dt)
				if d < 4.0:
					move(-dx / d * def.speed * 0.7, -dz / d * def.speed * 0.7, dt)
				else:
					move_amt = 0.0
				if atk_cd <= 0.0:
					start_windup(0.7, "shoot")
			else:
				nav_to(tg.pos, def.speed, dt, 1.0)
		else:
			if d < def.range * 0.85 + tg.radius and seen:
				move_amt = 0.0
				turn_to(yaw_to(dx, dz), dt)
				if atk_cd <= 0.0:
					start_windup(0.7 if def.boss else 0.5, "melee")
			else:
				nav_to(tg.pos, def.speed, dt, 0.5)
	else:
		aim_anim = false
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


func start_windup(time: float, k: String) -> void:
	windup = time
	windup_max = time
	windup_kind = k
	if k == "slam":
		game.spawn_telegraph(pos, 5.5, time)


func release_attack() -> void:
	var dmg: float = def.dmg * power_mul
	attack_anim = 0.25
	match windup_kind:
		"shoot":
			atk_cd = def.cd
			if target != null:
				game.shoot_at(self, target, "arrow", dmg, 30.0, 0.04)
		"slam":
			atk_cd = 1.0
			game.explode(pos, 5.5, dmg * 1.3, self, "slam")
		_:
			atk_cd = def.cd
			Sfx.play("swing", game.dist_to_player(pos))
			game.melee_hit(self, dmg, def.range + 0.3, 1.4, {"knock": 9.0 if def.boss else 3.0})
