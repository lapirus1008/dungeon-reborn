# 플레이어: 1인칭 조작, 직업별 스킬, 뷰모델, 보호막 효과
class_name Player
extends Actor

const EYE := 1.65

var cls := ""
var equipment: Dictionary
var bag: Array
var stats: Dictionary
var pitch := 0.0
var vy := 0.0
var stamina := 100.0
var stamina_delay := 0.0
var mana := 0.0
var cd := {"lmb": 0.0, "rmb": 0.0, "q": 0.0, "e": 0.0, "potion": 0.0}
var swing = null # {t, dur, hit_at, done, side}
var swing_side := 1.0
var draw := -1.0
var dash = null # {dir, speed, t, hit, hit_done}
var rage := 0.0
var bob := 0.0
var extract_t := 0.0
var interact_t := 0.0
var kills := 0
var pvp_kills := 0
var step_t := 0.0
var shield_t := 0.0
var shield_max := 50.0
var shield_hit_fx := 0.0
var cast := 0.0
var zoom := false
var sprinting := false
var moving := false
var shake := 0.0


func _init(g, p: Vector3, c: String, eq: Dictionary, b: Array) -> void:
	var st := Data.compute_stats(c, eq)
	super(g, {"kind": "player", "name": "당신", "faction": "player", "pos": p, "hp": st.max_hp, "armor": st.armor, "radius": 0.4})
	cls = c
	equipment = eq
	bag = b
	stats = st
	mana = st.max_mana


func display_name() -> String:
	return "당신"


func recalc() -> void:
	var st := Data.compute_stats(cls, equipment)
	var ratio := hp / max_hp
	stats = st
	max_hp = st.max_hp
	hp = clampf(ratio * max_hp, 1.0, max_hp)
	armor = st.armor
	mana = minf(mana, st.max_mana)


func on_block(amount: float) -> void:
	stamina -= amount * 0.7
	stamina_delay = 0.8
	Sfx.play("block")
	if stamina <= 0.0:
		stamina = 0.0
		blocking = false
		stun = 0.6
		game.hud.toast("방어가 무너졌다!")


func on_shield_hit(amount: float) -> void:
	if amount <= 0.0:
		return
	shield_hit_fx = 1.0
	game.hud.damage_number(center() + fwd(yaw) * 1.2, amount, Color(0.45, 0.75, 1.0), "흡수 ")
	if shield <= 0.0:
		shield_t = 0.0
		Sfx.play("shield_break")
		game.hud.toast("비전 보호막이 깨졌습니다")
	else:
		Sfx.play("shield_hit")


func look(rel: Vector2, sens: float) -> void:
	var k := sens * (0.55 if zoom else 1.0)
	yaw -= rel.x * k
	pitch = clampf(pitch - rel.y * k, -1.5, 1.5)


func update(dt: float) -> void:
	tick_common(dt)
	for k in cd:
		if cd[k] > 0.0:
			cd[k] -= dt
	if rage > 0.0:
		rage -= dt
	if stats.max_mana > 0:
		mana = minf(stats.max_mana, mana + dt * 7.0)
	if shield_t > 0.0:
		shield_t -= dt
		if shield_t <= 0.0 and shield > 0.0:
			shield = 0.0
			game.hud.toast("비전 보호막이 사라졌습니다")
	shield_hit_fx = maxf(0.0, shield_hit_fx - dt * 3.0)
	if not alive:
		return

	var can_act: bool = game.can_act()
	var stunned := stun > 0.0
	# 이동 입력 (메뉴/인벤토리가 열려 있어도 이동 가능 - 던전본처럼 게임은 계속 진행)
	var ix := 0.0
	var iz := 0.0
	if not stunned and not game.typing:
		iz = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
		ix = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var f := fwd(yaw)
	var r := Vector3(cos(yaw), 0, -sin(yaw))
	var wish := f * iz + r * ix
	var wl := wish.length()
	if wl > 0.0:
		wish /= wl
	sprinting = Input.is_action_pressed("sprint") and iz > 0.0 and stamina > 1.0 and not blocking and draw < 0.0
	var speed: float = stats.base_speed * stats.speed_mul
	if sprinting:
		speed *= 1.45
	if blocking:
		speed *= 0.55
	if draw >= 0.0:
		speed *= 0.6
	if rage > 0.0:
		speed *= 1.1
	if slow > 0.0:
		speed *= 0.6
	if iz < 0.0:
		speed *= 0.8

	if dash != null:
		dash.t -= dt
		move(dash.dir.x * dash.speed, dash.dir.z * dash.speed, dt)
		if dash.has("hit") and not dash.hit_done:
			for a in game.actors:
				if not a.alive or a == self or a.extracted:
					continue
				if Vector2(a.pos.x - pos.x, a.pos.z - pos.z).length() < a.radius + 1.2:
					a.take_damage(dash.hit, self, {"knock": dash.dir * 12.0, "stun": 0.9, "from": pos})
					Sfx.play("hit")
					shake = 0.25
					dash.hit_done = true
					dash.t = 0.0
					break
		if dash.t <= 0.0:
			dash = null
	else:
		move(wish.x * speed, wish.z * speed, dt)
	last_vel = wish * speed
	moving = wl > 0.0 and dash == null
	if moving:
		bob += dt * speed * 1.9
		step_t -= dt * speed
		if step_t <= 0.0:
			step_t = 2.6
			Sfx.play("step", -1.0, 0.15)

	# 점프
	if can_act and Input.is_action_just_pressed("jump") and pos.y <= 0.001 and stamina > 10.0 and not stunned:
		vy = 6.2
		stamina -= 10.0
		stamina_delay = 0.6
	vy -= 20.0 * dt
	pos.y = maxf(0.0, pos.y + vy * dt)
	if pos.y == 0.0:
		vy = 0.0

	# 스태미나
	if sprinting and moving:
		stamina -= 18.0 * dt
		stamina_delay = 0.7
	elif stamina_delay > 0.0:
		stamina_delay -= dt
	else:
		stamina = minf(100.0, stamina + (8.0 if blocking else 28.0) * dt)
	stamina = maxf(0.0, stamina)

	var act := can_act and not stunned
	var dm: float = stats.dmg_mul * (1.35 if rage > 0.0 else 1.0)
	zoom = false
	match cls:
		"fighter":
			_fighter(dt, act, dm, f)
		"ranger":
			_ranger(dt, act, dm, f, wish, wl)
		"mage":
			_mage(dt, act, dm)

	# 물약
	if not stunned and can_act and cd.potion <= 0.0:
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


func _fighter(dt: float, act: bool, dm: float, f: Vector3) -> void:
	blocking = act and Input.is_action_pressed("secondary") and stamina > 0.0 and swing == null and dash == null
	if act and Input.is_action_pressed("attack") and swing == null and not blocking and cd.lmb <= 0.0 and stamina >= 6.0:
		swing_side = -swing_side
		swing = {"t": 0.0, "dur": 0.42, "hit_at": 0.17, "done": false, "side": swing_side}
		stamina -= 9.0
		stamina_delay = 0.6
		cd.lmb = 0.48
		Sfx.play("swing")
	if act and Input.is_action_just_pressed("skill_q") and cd.q <= 0.0 and stamina >= 15.0:
		cd.q = Data.CLASSES.fighter.skills.q.cd
		stamina -= 15.0
		dash = {"dir": f, "speed": 22.0, "t": 0.32, "hit": 36.0 * dm, "hit_done": false}
		Sfx.play("swing")
	if act and Input.is_action_just_pressed("skill_e") and cd.e <= 0.0:
		cd.e = Data.CLASSES.fighter.skills.e.cd
		rage = 6.0
		Sfx.play("growl")
		game.hud.toast("분노!")
	swinging = swing != null
	if swing != null:
		swing.t += dt
		if not swing.done and swing.t >= swing.hit_at:
			swing.done = true
			game.melee_hit(self, 26.0 * dm, 3.1, 1.5, {"knock": 5.0})
		if swing.t >= swing.dur:
			swing = null


func _ranger(dt: float, act: bool, dm: float, f: Vector3, wish: Vector3, wl: float) -> void:
	zoom = act and Input.is_action_pressed("secondary")
	if act and Input.is_action_pressed("attack") and cd.lmb <= 0.0:
		if draw < 0.0:
			draw = 0.0
		draw += dt
	elif draw >= 0.0:
		if draw > 0.15 and stun <= 0.0:
			var charge := minf(1.0, draw / 0.9)
			game.fire_player_projectile("arrow", 32.0 + 36.0 * charge, (14.0 + 30.0 * charge) * dm, 0.0)
			cd.lmb = 0.25
		draw = -1.0
	if act and Input.is_action_just_pressed("skill_q") and cd.q <= 0.0:
		cd.q = Data.CLASSES.ranger.skills.q.cd
		for s in [-0.12, 0.0, 0.12]:
			game.fire_player_projectile("arrow", 52.0, 24.0 * dm, s)
	if act and Input.is_action_just_pressed("skill_e") and cd.e <= 0.0 and stamina >= 12.0:
		cd.e = Data.CLASSES.ranger.skills.e.cd
		stamina -= 12.0
		var dir := wish if wl > 0.0 else -f
		dash = {"dir": dir, "speed": 17.0, "t": 0.3}
		invuln = 0.3


func _mage(dt: float, act: bool, dm: float) -> void:
	if act and Input.is_action_pressed("attack") and cd.lmb <= 0.0 and mana >= 10.0:
		mana -= 10.0
		cd.lmb = 0.42
		game.fire_player_projectile("bolt", 44.0, 21.0 * dm, 0.0)
		cast = 0.2
	if act and Input.is_action_just_pressed("secondary"):
		cast_shield()
	if act and Input.is_action_just_pressed("skill_q") and cd.q <= 0.0:
		if mana < 30.0:
			game.hud.toast("마나가 부족합니다")
		else:
			mana -= 30.0
			cd.q = Data.CLASSES.mage.skills.q.cd
			game.fire_player_projectile("fireball", 26.0, 48.0 * dm, 0.0)
			cast = 0.3
	if act and Input.is_action_just_pressed("skill_e") and cd.e <= 0.0:
		if mana < 35.0:
			game.hud.toast("마나가 부족합니다")
		else:
			mana -= 35.0
			cd.e = Data.CLASSES.mage.skills.e.cd
			apply_heal(50.0, 4.0)
			Sfx.play("heal")
			game.spawn_ring_burst(pos + Vector3(0, 0.1, 0), Color(0.5, 1.0, 0.5), 2.0)
	if cast > 0.0:
		cast -= dt


# 마법사 비전 보호막: 구체 + 화면 가장자리 푸른 일렁임 + HUD 보호막 바 + 효과음
func cast_shield() -> bool:
	if cd.rmb > 0.0:
		return false
	if mana < 30.0:
		game.hud.toast("마나가 부족합니다")
		return false
	mana -= 30.0
	cd.rmb = Data.CLASSES.mage.skills.rmb.cd
	shield = shield_max
	shield_t = 8.0
	shield_hit_fx = 1.0
	Sfx.play("shield")
	game.hud.toast("비전 보호막 (50)")
	game.spawn_ring_burst(pos + Vector3(0, 1.0, 0), Color(0.35, 0.65, 1.0), 2.5)
	return true


func use_consumable(i: int) -> void:
	var it: Dictionary = bag[i]
	var b: Dictionary = Data.ITEM_BASES[it.base]
	bag.remove_at(i)
	apply_heal(b.heal, 3.0 if it.base == "health_potion" else 2.0)
	cd.potion = 1.2
	slow = 1.0
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
	cam.position = Vector3(pos.x, pos.y + EYE + b, pos.z)
	var sx := 0.0
	var sy := 0.0
	if shake > 0.0:
		shake -= dt
		sx = randf_range(-0.5, 0.5) * shake * 0.15
		sy = randf_range(-0.5, 0.5) * shake * 0.15
	cam.rotation = Vector3(pitch + sx, yaw + sy, 0)
	var target_fov := 45.0 if zoom else (82.0 if sprinting and moving else 75.0)
	cam.fov = lerpf(cam.fov, target_fov, minf(1.0, dt * 10.0))

	# 보호막 구체 (카메라를 감싸는 막 + 화면 가장자리 효과는 HUD에서)
	bubble.visible = shield > 0.0
	if bubble.visible:
		var sm: ShaderMaterial = bubble.material_override
		var remain := clampf(shield / shield_max, 0.0, 1.0)
		var fade := clampf(shield_t / 1.5, 0.0, 1.0)
		sm.set_shader_parameter("strength", (0.35 + remain * 0.65) * (0.5 + 0.5 * fade if shield_t < 1.5 else 1.0))
		sm.set_shader_parameter("hit", shield_hit_fx)

	# 뷰모델 애니메이션
	var R: Node3D = vm.get_meta("R")
	var L: Node3D = vm.get_meta("L")
	var w: Node3D = vm.get_meta("weapon")
	vm.position = Vector3(sin(bob * 0.5) * (0.015 if moving else 0.0), b * 0.4, 0)
	match cls:
		"fighter":
			R.rotation = Vector3.ZERO
			R.position = Vector3(0.3, -0.34, -0.6)
			if swing != null:
				var k: float = swing.t / swing.dur
				var s: float = swing.side
				var a := k / 0.35 if k < 0.35 else 1.0 - (k - 0.35) / 0.65
				R.rotation = Vector3(-0.6 * a, s * (1.4 - k * 2.8) * a, s * 0.6 * a)
				R.position.x = 0.3 - s * 0.1 * a
			L.position = Vector3(-0.14, -0.2, -0.5) if blocking else Vector3(-0.3, -0.36, -0.6)
			L.rotation.y = 0.5 if blocking else 0.0
		"ranger":
			var k := minf(1.0, draw / 0.9) if draw >= 0.0 else 0.0
			L.position = Vector3(-0.2, -0.3, -0.66)
			R.position = Vector3(0.18, -0.34, -0.56 + k * 0.12)
			var ar: Node3D = vm.get_meta("arrow")
			ar.visible = cd.lmb <= 0.05
			ar.position = Vector3(-0.04, -0.22, -0.7 + k * 0.15)
			w.rotation.z = 0.15 - k * 0.1
		_:
			var c := 1.0 if cast > 0.0 else 0.0
			R.position = Vector3(0.3, -0.34 + c * 0.08, -0.6 - c * 0.1)
			L.position = Vector3(-0.3, -0.36, -0.6)
