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
var rig: CharacterRig
var alt_rig: CharacterRig # 드루이드 표범 형태
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


func attach_rig(r: CharacterRig) -> void:
	rig = r
	node = r.node
	meshes = r.meshes
	game.world.add_child(node)
	node.position = pos


# 변신용 두 번째 모델 (같은 위치에 붙여 두고 보이기만 전환)
func attach_alt_rig(r: CharacterRig) -> void:
	alt_rig = r
	game.world.add_child(r.node)
	r.node.visible = false


func active_rig() -> CharacterRig:
	return alt_rig if panther and alt_rig != null else rig


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
		# 은신: 몬스터는 전혀 알아채지 못함, 모험가(AI)는 아주 가까이서만
		if a.stealth > 0.0 and (kind == "monster" or d > 3.0):
			continue
		# 미믹 플라스크로 상자가 된 모험가: 몬스터는 알아채지 못함
		if a.mimic_form and kind == "monster":
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
	var r := active_rig()
	var other: CharacterRig = rig if r == alt_rig else alt_rig
	if other != null and other.node.visible:
		other.node.visible = false
	r.node.visible = visible and _stealth_visible() and not mimic_form
	r.node.position = pos
	r.node.rotation.y = yaw
	_update_mimic_box()
	if not alive:
		death_t += dt
	var st := {
		"move": move_amt,
		"windup": (1.0 - windup / windup_max) if windup > 0.0 else -1.0,
		"attack": (1.0 - attack_anim / 0.25) if attack_anim > 0.0 else -1.0,
		"aim": aim_anim,
		"block": blocking,
		"dead_t": death_t if not alive else -1.0,
		"cast": cls in ["pyromancer", "cryomancer", "druid"] and not panther,
		"spin": spin_t > 0.0,
	}
	if attack_anim > 0.0:
		attack_anim -= dt
	r.animate(dt, st)
	# 피격 시 붉게, 은신 중 반투명, 서리 장벽 중 푸르게
	var flash := hit_flash > 0.0
	if flash != _flashing:
		_flashing = flash
		for m in r.meshes:
			(m as GeometryInstance3D).material_overlay = game.flash_mat if flash else null
	# 은신: 완전히 투명하지 않고 아지랑이처럼 흐물거림 (자세히 보면 보임)
	var tr := 0.0
	if stealth > 0.0:
		tr = 0.78 + sin(game.time * 7.0 + nid) * 0.07 + sin(game.time * 13.0) * 0.04
	if absf(r.node.get_meta("tr", -1.0) - tr) > 0.01:
		r.node.set_meta("tr", tr)
		for m in r.meshes:
			(m as GeometryInstance3D).transparency = tr
	if not r.node.has_meta("base_scale"):
		r.node.set_meta("base_scale", r.node.scale)
	var bs: Vector3 = r.node.get_meta("base_scale")
	if stealth > 0.0 and kind != "monster":
		r.node.scale = bs * Vector3(1.0 + sin(game.time * 9.0) * 0.03, 1.0 + sin(game.time * 6.0 + 1.0) * 0.02, 1.0)
	elif r.node.scale != bs:
		r.node.scale = bs


# 미믹 플라스크: 모험가 대신 상자가 보임
var mimic_box: Node3D


func _update_mimic_box() -> void:
	if mimic_form and visible and alive:
		if mimic_box == null:
			mimic_box = Models.chest(1)
			game.world.add_child(mimic_box)
		mimic_box.position = pos
		mimic_box.rotation.y = yaw
	elif mimic_box != null:
		mimic_box.queue_free()
		mimic_box = null


# 은신 중인 적은 플레이어와 가까울 때만 희미하게 보인다
func _stealth_visible() -> bool:
	return true


func update_hp_bar(cam_pos: Vector3) -> void:
	var show := alive and hp < max_hp and visible and _stealth_visible() and cam_pos.distance_to(pos) < 25.0
	hp_bar.visible = show
	if not show:
		return
	hp_bar.position = Vector3(pos.x, pos.y + height + 0.35, pos.z)
	hp_bar.set_instance_shader_parameter("fill", clampf(hp / max_hp, 0.0, 1.0))


func set_visible(v: bool) -> void:
	visible = v
	if node:
		active_rig().node.visible = v and _stealth_visible()
		active_rig().set_active(v)
	if not v:
		hp_bar.visible = false
		if mimic_box != null:
			mimic_box.queue_free()
			mimic_box = null


func remove_from_world() -> void:
	if mimic_box != null and is_instance_valid(mimic_box):
		mimic_box.queue_free()
	if node and is_instance_valid(node):
		node.queue_free()
	if alt_rig != null and is_instance_valid(alt_rig.node):
		alt_rig.node.queue_free()
	if hp_bar and is_instance_valid(hp_bar):
		hp_bar.queue_free()
