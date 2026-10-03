# AI 공용: 경로 이동, 적 감지, 모델 애니메이션, 체력바
class_name AIActor
extends Actor

var path: Array = []
var path_goal := Vector3.ZERO
var path_timer := 0.0
var direct_timer := 0.0
var direct := false
var target = null
var sense_timer := 0.0
var atk_cd := 0.0
var node: Node3D
var meshes: Array = []
var hp_bar: MeshInstance3D
var aim_anim := false
var _flashing := false
var visible := true


func _init(g, o: Dictionary) -> void:
	super(g, o)
	sense_timer = randf() * 0.3
	hp_bar = Models.hp_bar()
	g.world.add_child(hp_bar)


func attach_model(m: Node3D) -> void:
	node = m
	meshes = m.get_meta("meshes")
	game.world.add_child(node)
	node.position = pos


func turn_to(y: float, dt: float, rate := 8.0) -> void:
	var d := angle_difference(yaw, y)
	yaw += signf(d) * minf(absf(d), rate * dt)


# 목표 지점까지 경로를 따라 이동. 도착하면 true
func nav_to(goal: Vector3, speed: float, dt: float, stop_dist := 0.6, face := true) -> bool:
	var dg = game.dungeon
	var dx0 := goal.x - pos.x
	var dz0 := goal.z - pos.z
	var dist := sqrt(dx0 * dx0 + dz0 * dz0)
	if dist < stop_dist:
		move_amt = 0.0
		return true
	direct_timer -= dt
	path_timer -= dt
	if direct_timer <= 0.0:
		direct = dist < 40.0 and dg.wide_los(pos, goal)
		direct_timer = 0.3 + randf() * 0.1
	var tx := goal.x
	var tz := goal.z
	if not direct:
		if path.is_empty() or path_timer <= 0.0 or path_goal.distance_squared_to(goal) > 9.0:
			path = dg.path(pos, goal)
			path_goal = goal
			path_timer = 1.2
		if not path.is_empty():
			var wp: Vector3 = path[0]
			if Vector2(wp.x - pos.x, wp.z - pos.z).length() < 0.9 and path.size() > 1:
				path.pop_front()
				wp = path[0]
			tx = wp.x
			tz = wp.z
	var dx := tx - pos.x
	var dz := tz - pos.z
	var d := maxf(0.001, sqrt(dx * dx + dz * dz))
	var sp := speed * (0.55 if slow > 0.0 else 1.0)
	move(dx / d * sp, dz / d * sp, dt)
	if face:
		turn_to(yaw_to(dx, dz), dt)
	move_amt = 1.0
	return false


func hostile_to(o) -> bool:
	return game.hostile(self, o)


# 시야 내 가장 가까운 적
func sense(rng: float):
	var best = null
	var bd := rng
	for a in game.actors:
		if not a.alive or a == self or a.extracted or not hostile_to(a):
			continue
		var d := Vector2(a.pos.x - pos.x, a.pos.z - pos.z).length()
		if d >= bd:
			continue
		if not game.dungeon.los(pos.x, pos.z, a.pos.x, a.pos.z):
			continue
		var ang := absf(angle_difference(yaw, yaw_to(a.pos.x - pos.x, a.pos.z - pos.z)))
		if ang > 1.9 and d > 6.0:
			continue
		best = a
		bd = d
	return best


func animate(dt: float) -> void:
	var p: Dictionary = node.get_meta("parts")
	node.position = pos
	node.rotation.y = yaw
	if not alive:
		death_t += dt
		p.rig.rotation.x = maxf(-PI / 2, -death_t * 5.0)
		p.rig.position.y = minf(0.25, death_t)
		return
	walk_phase += dt * 9.0 * move_amt
	var sw := sin(walk_phase) * 0.7 * move_amt
	p.leg_l.rotation.x = sw
	p.leg_r.rotation.x = -sw
	p.arm_l.rotation.x = -sw * 0.6
	p.arm_r.rotation.x = sw * 0.6
	p.arm_r.rotation.z = 0.0
	if windup > 0.0:
		p.arm_r.rotation.x = 2.6 * minf(1.0, 1.0 - windup / windup_max + 0.3)
		p.arm_r.rotation.z = 0.3
	elif attack_anim > 0.0:
		attack_anim -= dt
		p.arm_r.rotation.x = 2.6 - (1.0 - attack_anim / 0.25) * 3.2
	if aim_anim:
		p.arm_l.rotation.x = PI / 2
		p.arm_r.rotation.x = PI / 2
	if blocking:
		p.arm_l.rotation.x = 1.3
	var flash := hit_flash > 0.0
	if flash != _flashing:
		_flashing = flash
		for m in meshes:
			(m as GeometryInstance3D).material_overlay = game.flash_mat if flash else null


func update_hp_bar(cam_pos: Vector3) -> void:
	var show := alive and hp < max_hp and visible and cam_pos.distance_to(pos) < 25.0
	hp_bar.visible = show
	if not show:
		return
	hp_bar.position = Vector3(pos.x, pos.y + height + 0.35, pos.z)
	hp_bar.set_instance_shader_parameter("fill", clampf(hp / max_hp, 0.0, 1.0))


func set_visible(v: bool) -> void:
	visible = v
	if node:
		node.visible = v
	if not v:
		hp_bar.visible = false


func remove_from_world() -> void:
	if node and is_instance_valid(node):
		node.queue_free()
	if hp_bar and is_instance_valid(hp_bar):
		hp_bar.queue_free()
