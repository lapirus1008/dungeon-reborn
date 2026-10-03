# 소환수 (드루이드 '자연의 힘' 나무 정령): 지정 위치에 30초 동안 머무르며 주변 적을 공격
class_name Summon
extends AIActor

const RANGE := 6.5

var owner_actor
var life := 30.0
var hit_dmg := 98.37


func _init(g, o, p: Vector3, dmg := 98.37) -> void:
	super(g, {"kind": "summon", "name": "나무 정령", "faction": o.faction, "pos": p, "hp": 260.0, "radius": 0.7, "height": 3.0, "armor": 25.0})
	owner_actor = o
	hit_dmg = dmg
	attach_rig(Models.treant_rig())
	if not rig.procedural:
		rig.node.scale = Vector3.ONE * 1.5


func display_name() -> String:
	return "나무 정령 (%s)" % owner_actor.display_name()


func update(dt: float) -> void:
	tick_common(dt)
	move_amt = 0.0
	if not alive:
		return
	life -= dt
	if life <= 0.0 or owner_actor.extracted:
		alive = false
		game.on_death(self, null)
		return
	if atk_cd > 0.0:
		atk_cd -= dt
	if incapacitated():
		windup = 0.0
		return
	sense_timer -= dt
	if sense_timer <= 0.0:
		sense_timer = 0.3
		if target != null and (not target.alive or target.extracted or target.pos.distance_to(pos) > RANGE + 1.0):
			target = null
		if target == null:
			target = sense(RANGE)
	if target == null:
		return
	var dx: float = target.pos.x - pos.x
	var dz: float = target.pos.z - pos.z
	turn_to(yaw_to(dx, dz), dt, 4.0)
	if windup > 0.0:
		windup -= dt
		if windup <= 0.0:
			attack_anim = 0.25
			atk_cd = 2.2
			# 뿌리가 솟아 대상과 그 주변을 공격
			for a in game.actors:
				if a.alive and game.hostile(self, a) and a.pos.distance_to(target.pos) < 1.8 + a.radius:
					game.hit(owner_actor if owner_actor.alive else self, a, hit_dmg, {"from": pos, "ranged": true, "dtype": "phys", "can_crit": false})
			game.spawn_ring_burst(target.pos + Vector3(0, 0.2, 0), Skills.NATURE, 1.8)
			game.sfx("hit", target.pos)
		return
	if atk_cd <= 0.0:
		windup = 0.6
		windup_max = 0.6
