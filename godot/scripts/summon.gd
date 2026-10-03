# 소환수 (드루이드 트렌트): 소환자를 따라다니며 근처 적을 공격, 30초 후 사라짐
class_name Summon
extends AIActor

var owner_actor
var life := 30.0


func _init(g, o, p: Vector3) -> void:
	super(g, {"kind": "summon", "name": "트렌트", "faction": o.faction, "pos": p, "hp": 200.0, "radius": 0.7, "height": 3.0, "armor": 20.0})
	owner_actor = o
	attach_rig(Models.treant_rig())
	if not rig.procedural:
		rig.node.scale = Vector3.ONE * 1.5


func display_name() -> String:
	return "트렌트 (%s)" % owner_actor.display_name()


func update(dt: float) -> void:
	tick_common(dt)
	if not alive:
		return
	life -= dt
	if life <= 0.0 or not owner_actor.alive or owner_actor.extracted:
		alive = false
		game.on_death(self, null)
		return
	if atk_cd > 0.0:
		atk_cd -= dt
	if incapacitated():
		windup = 0.0
		move_amt = 0.0
		return
	sense_timer -= dt
	if sense_timer <= 0.0:
		sense_timer = 0.3
		if target != null and (not target.alive or target.extracted or target.pos.distance_to(owner_actor.pos) > 18.0):
			target = null
		if target == null:
			target = sense(14.0)
	if target != null:
		var dx: float = target.pos.x - pos.x
		var dz: float = target.pos.z - pos.z
		var d := sqrt(dx * dx + dz * dz)
		if windup > 0.0:
			windup -= dt
			turn_to(yaw_to(dx, dz), dt, 4.0)
			move_amt = 0.0
			if windup <= 0.0:
				attack_anim = 0.25
				game.sfx("hit", pos)
				game.melee_hit(self, 14.0, 3.0, 1.6, {"knock": 6.0})
				atk_cd = 1.4
			return
		if d < 2.8 + target.radius:
			turn_to(yaw_to(dx, dz), dt, 4.0)
			move_amt = 0.0
			if atk_cd <= 0.0:
				windup = 0.6
				windup_max = 0.6
		else:
			nav_to(target.pos, 3.6 * speed_factor(), dt, 1.0)
	else:
		# 소환자 따라가기
		if pos.distance_to(owner_actor.pos) > 3.5:
			nav_to(owner_actor.pos, 4.6, dt, 2.5)
		else:
			move_amt = 0.0
