# 플레이어: 1인칭 조작, 직업별 스킬 입력, 스태미나, 뷰모델
class_name Player
extends Actor

const EYE := 1.65
# 스태미나: 10 미만이면 Shift를 눌러도 걷기, 바닥나면 30까지 회복해야 다시 달리기
# (걷기/달리기가 짧게 반복되는 현상 방지)
const SPRINT_MIN := 10.0
const SPRINT_RESUME := 30.0

var equipment: Dictionary
var bag: Array
var pitch := 0.0
var vy := 0.0
var stamina := 100.0
var stamina_delay := 0.0
var exhausted := false
var swing = null # {t, prof, done, side, bash}
var swing_side := 1.0
var charge_t := -1.0 # 프리스트 정화 충전
var bob := 0.0
var extract_t := 0.0
var interact_t := 0.0
var kills := 0
var pvp_kills := 0
var step_t := 0.0
var shield_hit_fx := 0.0
var cast := 0.0
var sprinting := false
var moving := false
var shake := 0.0
var zoom := false


func _init(g, p: Vector3, c: String, eq: Dictionary, b: Array) -> void:
	var st := Data.compute_stats(c, eq)
	super(g, {"kind": "player", "name": "당신", "faction": "player", "pos": p, "hp": st.max_hp, "armor": st.armor, "radius": 0.4})
	cls = c
	equipment = eq
	bag = b
	stats = st
	res = st.res_max if st.res != "soul" else 30.0
	block_mul = 0.25 if c == "fighter" else 0.4


func display_name() -> String:
	return "당신"


func recalc() -> void:
	var st := Data.compute_stats(cls, equipment)
	var ratio := hp / max_hp
	stats = st
	max_hp = st.max_hp
	hp = clampf(ratio * max_hp, 1.0, max_hp)
	armor = st.armor
	res = minf(res, st.res_max)
	game.on_weapon_changed()


func on_block(amount: float) -> void:
	stamina -= amount * 0.7
	stamina_delay = 0.8
	Sfx.play("block")
	if stamina <= 0.0:
		stamina = 0.0
		exhausted = true
		blocking = false
		add_stun(0.6)
		game.hud.toast("방어가 무너졌다!")


func on_parry(_src) -> void:
	game.hud.toast("패링!")
	shake = 0.15


func on_shield_hit(amount: float) -> void:
	if amount <= 0.0:
		return
	shield_hit_fx = 1.0
	game.hud.damage_number(center() + fwd(yaw) * 1.2, amount, Color(0.45, 0.75, 1.0), "흡수 ")
	if shield <= 0.0:
		shield_t = 0.0
		Sfx.play("shield_break")
		game.hud.toast("보호막이 깨졌습니다")
	else:
		Sfx.play("shield_hit")


func on_stealth_end() -> void:
	game.hud.toast("은신이 풀렸습니다")


func look(rel: Vector2, sens: float) -> void:
	if frozen > 0.0:
		return
	var k := sens * (0.55 if zoom else 1.0)
	yaw -= rel.x * k
	pitch = clampf(pitch - rel.y * k, -1.5, 1.5)


# 조준: 카메라 위치와 시선 방향
func aim() -> Dictionary:
	var cam: Camera3D = game.camera
	var b := Basis.from_euler(Vector3(cam.rotation.x, cam.rotation.y, 0.0), EULER_ORDER_YXZ)
	var dir := -b.z
	return {"origin": cam.position + dir * 0.5 + Vector3(0, -0.12, 0), "dir": dir, "target": null}


func update(dt: float) -> void:
	tick_common(dt)
	for k in cd:
		if cd[k] > 0.0:
			cd[k] -= dt
	shield_hit_fx = maxf(0.0, shield_hit_fx - dt * 3.0)
	if not alive:
		return
	Skills.tick_resource(self, dt)
	Skills.tick_channel(self, dt)
	Skills.tick_spin(self, dt)
	if cast > 0.0:
		cast -= dt

	var can_act: bool = game.can_act()
	var locked := incapacitated()
	# 이동 입력 (메뉴/인벤토리가 열려 있어도 이동 가능 - 던전본처럼 게임은 계속 진행)
	var ix := 0.0
	var iz := 0.0
	if not locked and not game.typing:
		iz = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
		ix = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var f := fwd(yaw)
	var r := Vector3(cos(yaw), 0, -sin(yaw))
	var wish := f * iz + r * ix
	var wl := wish.length()
	if wl > 0.0:
		wish /= wl

	# 달리기 판정 (히스테리시스)
	if stamina <= 0.5:
		exhausted = true
	elif exhausted and stamina >= SPRINT_RESUME:
		exhausted = false
	var want_sprint := Input.is_action_pressed("sprint") and iz > 0.0 and not locked
	var busy := blocking or spin_t > 0.0 or channel_t > 0.0 or charge_t >= 0.0
	if not want_sprint or busy or exhausted:
		sprinting = false
	elif not sprinting:
		sprinting = stamina >= SPRINT_MIN
	var speed: float = stats.base_speed * stats.speed_mul
	if sprinting:
		speed *= 1.45
	if blocking:
		speed *= 0.55
	if spin_t > 0.0:
		speed *= 0.75
	if channel_t > 0.0 or charge_t >= 0.0:
		speed *= 0.45
	if panther:
		speed *= 1.7
	if stealth > 0.0:
		speed *= 1.1
	speed *= speed_factor()
	if iz < 0.0:
		speed *= 0.8

	if not Skills.tick_dash(self, dt):
		move(wish.x * speed, wish.z * speed, dt)
	last_vel = wish * speed
	moving = wl > 0.0 and dash == null and root <= 0.0 and not locked
	if moving:
		bob += dt * speed * 1.9
		step_t -= dt * speed
		if step_t <= 0.0:
			step_t = 2.6
			if stealth <= 0.0:
				Sfx.play("step", -1.0, 0.15)

	# 점프
	if can_act and Input.is_action_just_pressed("jump") and pos.y <= 0.001 and stamina > SPRINT_MIN and not locked and root <= 0.0:
		vy = 6.2
		stamina -= 10.0
		stamina_delay = 0.6
	vy -= 20.0 * dt
	pos.y = maxf(0.0, pos.y + vy * dt)
	if pos.y == 0.0:
		vy = 0.0

	# 스태미나: 달리는 중에만 소모, 그 외에는 잠시 후 회복
	if sprinting and moving:
		stamina -= 18.0 * dt
		stamina_delay = 0.7
	elif stamina_delay > 0.0:
		stamina_delay -= dt
	else:
		stamina = minf(100.0, stamina + (8.0 if blocking else 28.0) * dt)
	stamina = maxf(0.0, stamina)

	var act := can_act and not locked and channel_t <= 0.0
	_combat(dt, act)

	# 물약
	if not locked and can_act and cd.potion <= 0.0:
		var want := ""
		if Input.is_action_just_pressed("potion1"):
			want = "health_potion"
		elif Input.is_action_just_pressed("potion2"):
			want = "bandage"
		if want != "":
			var idx := -1
			for i in bag.size():
				if bag[i].base == want:
					idx = i
					break
			if idx < 0:
				game.hud.toast("%s이(가) 없습니다" % Data.ITEM_BASES[want].name)
			elif hp >= max_hp:
				game.hud.toast("체력이 가득 찼습니다")
			else:
				use_consumable(idx)


func _start_swing(prof: Dictionary, bash := false) -> void:
	swing_side = -swing_side
	swing = {"t": 0.0, "prof": prof, "done": false, "side": swing_side, "bash": bash}
	stamina -= prof.stamina
	stamina_delay = 0.6
	cd.lmb = prof.cd
	Sfx.play("swing")


func _combat(dt: float, act: bool) -> void:
	var melee := Skills.is_melee(self)
	var rmb_pressed := act and Input.is_action_just_pressed("secondary")
	var rmb_held := act and Input.is_action_pressed("secondary")
	var lmb_held := act and Input.is_action_pressed("attack")
	var free := swing == null and spin_t <= 0.0 and dash == null

	# 우클릭
	blocking = false
	if Skills.uses_block(self):
		blocking = rmb_held and stamina > 0.0 and free
	elif rmb_pressed:
		match cls:
			"swordmaster":
				Skills.start_parry(self)
			"rogue":
				Skills.throw_knife(self, aim())
			"druid":
				if panther:
					Skills.roar(self)
				elif free and cd.rmb <= 0.0:
					cd.rmb = Skills.skill_def(self, "rmb").cd
					_start_swing(Skills.melee_profile(self, true), true)
			"pyromancer", "cryomancer":
				if free and cd.rmb <= 0.0:
					cd.rmb = Skills.skill_def(self, "rmb").cd
					_start_swing(Skills.melee_profile(self, true), true)
	# 프리스트 정화: 누르고 있다 놓으면 발동
	if cls == "priest":
		if rmb_held and cd.rmb <= 0.0:
			charge_t = maxf(charge_t, 0.0) + dt
		elif charge_t >= 0.0:
			Skills.cleanse_heal(self, charge_t / 1.2)
			charge_t = -1.0

	# 좌클릭
	if lmb_held and free and not blocking and cd.lmb <= 0.0:
		if melee:
			var prof := Skills.melee_profile(self)
			if stamina >= prof.stamina:
				_start_swing(prof)
		elif Skills.fire_basic(self, aim()):
			cast = 0.2

	# Q / E
	if act and Input.is_action_just_pressed("skill_q"):
		if Skills.use_q(self, aim()):
			cast = 0.3
	if act and Input.is_action_just_pressed("skill_e"):
		if Skills.use_e(self, aim()):
			cast = 0.3

	swinging = swing != null or spin_t > 0.0
	if swing != null:
		swing.t += dt
		if not swing.done and swing.t >= swing.prof.hit_at:
			swing.done = true
			Skills.melee_strike(self, swing.prof)
		if swing.t >= swing.prof.dur:
			swing = null


func use_consumable(i: int) -> void:
	var it: Dictionary = bag[i]
	var b: Dictionary = Data.ITEM_BASES[it.base]
	bag.remove_at(i)
	apply_heal(b.heal, 3.0 if it.base == "health_potion" else 2.0)
	cd.potion = 1.2
	add_slow(1.0, 0.6)
	Sfx.play("heal")
	game.hud.toast("%s 사용" % b.name)
	game.hud.refresh_panels()


# 카메라와 뷰모델 갱신
func update_camera(cam: Camera3D, vm: Node3D, bubble: MeshInstance3D, dt: float) -> void:
	if not alive:
		vm.visible = false
		bubble.visible = false
		pitch = minf(1.2, pitch + dt)
		cam.position.y = maxf(0.3, cam.position.y - dt * 2.0)
		cam.rotation.z = minf(0.8, cam.rotation.z + dt)
		cam.rotation.x = pitch
		return
	var b := sin(bob) * 0.05 if pos.y == 0.0 and moving else 0.0
	var eye := EYE * (0.7 if panther else 1.0)
	cam.position = Vector3(pos.x, pos.y + eye + b, pos.z)
	var sx := 0.0
	var sy := 0.0
	if shake > 0.0:
		shake -= dt
		sx = randf_range(-0.5, 0.5) * shake * 0.15
		sy = randf_range(-0.5, 0.5) * shake * 0.15
	var spin_roll := sin(spin_t * 18.0) * 0.03 if spin_t > 0.0 else 0.0
	cam.rotation = Vector3(pitch + sx, yaw + sy, spin_roll)
	var target_fov := 82.0 if (sprinting and moving) or panther else 75.0
	cam.fov = lerpf(cam.fov, target_fov, minf(1.0, dt * 10.0))

	# 보호막 구체
	bubble.visible = shield > 0.0
	if bubble.visible:
		var sm: ShaderMaterial = bubble.material_override
		var remain := clampf(shield / shield_max, 0.0, 1.0)
		var fade := clampf(shield_t / 1.5, 0.0, 1.0)
		sm.set_shader_parameter("tint", shield_color)
		sm.set_shader_parameter("strength", (0.35 + remain * 0.65) * (0.5 + 0.5 * fade if shield_t < 1.5 else 1.0))
		sm.set_shader_parameter("hit", shield_hit_fx)

	# 뷰모델 (은신 중 반투명)
	vm.visible = frozen <= 0.0
	var tr := 0.65 if stealth > 0.0 or channel_t > 0.0 else 0.0
	if vm.get_meta("transparency", -1.0) != tr:
		vm.set_meta("transparency", tr)
		for n in vm.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).transparency = tr
	ViewAnim.animate(self, vm, b, dt)
