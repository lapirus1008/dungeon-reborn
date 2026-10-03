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
# 멀티플레이
var peer_id := 0 # 0: 오프라인/호스트 본인, 그 외: 접속한 친구의 피어 ID
var inp: InputState
var container = null # 서버 측: 이 플레이어가 열어 둔 상자/전리품
var net_pos := Vector3.ZERO
var has_net := false
var forced_t := 0.0 # 넉백/돌진 중에는 서버 위치를 우선
var done := false # 탈출/사망으로 레이드 종료
var revive_wait := 0.0 # 쓰러진 뒤 부활을 기다리는 시간 (파티)
var killer_name := ""
var char_id := ""
var hold_q := -1.0 # 누르고 있는 Q/E (화염 폭발, 치료)
var hold_e := -1.0
var puppet = null # 호스트 화면에 원격 플레이어를 그리는 NetActor
var ch: Array = [] # 이번 프레임 진행 바 [문구, 비율] (원격 전송용)


func _init(g, p: Vector3, c: String, eq: Dictionary, b: Array, pname := "당신", fac := "player", peer := 0, sk := {}, ws := 1) -> void:
	var st := Data.compute_stats(c, eq, ws)
	super(g, {"kind": "player", "name": pname, "faction": fac, "pos": p, "hp": st.max_hp, "armor": st.armor, "radius": 0.4})
	peer_id = peer
	inp = InputState.new(peer > 1)
	cls = c
	equipment = eq
	for k in Data.ALL_SLOTS:
		if not equipment.has(k):
			equipment[k] = null
	bag = b
	wset = ws
	skills = sk.duplicate() if sk.size() else Account.default_skills(c)
	stats = st
	res = st.res_max if st.res == "mana" else st.res_max * 0.4
	block_mul = 1.0 - st.block_pct / 100.0 if st.block_pct > 0.0 else 0.4
	charges = 1
	if c == "druid" and Skills.has_fx(self, "nature_seed"):
		charges = 2


func display_name() -> String:
	return name if game.online() else "당신"


func is_remote() -> bool:
	return inp.remote


func recalc() -> void:
	var st := Data.compute_stats(cls, equipment, wset)
	var ratio := hp / max_hp
	stats = st
	max_hp = st.max_hp
	hp = clampf(ratio * max_hp, 1.0, max_hp)
	armor = st.armor
	res = minf(res, st.res_max)
	block_mul = 1.0 - st.block_pct / 100.0 if st.block_pct > 0.0 else 0.4
	game.on_weapon_changed(self)


# 무기 세트 교체 (X)
func swap_weapon_set() -> void:
	if swing != null or spin_t > 0.0 or dash != null:
		return
	wset = 2 if wset == 1 else 1
	if panther and Skills.wcat(self) == "":
		Skills.set_panther(self, false)
	recalc()
	game.notify(self, "toast", ["무기 세트 %d" % wset])
	game.inv_changed(self)
	game.on_weapon_changed(self)


func on_block(amount: float) -> void:
	stamina -= amount * 0.7 * (1.0 - stats.get("flags", {}).get("block_eff", 0.0))
	stamina_delay = 0.8
	game.sfx("block", pos)
	if stamina <= 0.0:
		stamina = 0.0
		exhausted = true
		blocking = false
		add_stun(0.6)
		game.notify(self, "toast", ["방어가 무너졌다!"])


func on_parry(_src) -> void:
	game.notify(self, "toast", ["패링!"])
	shake = 0.15


func on_shield_hit(amount: float) -> void:
	if amount <= 0.0:
		return
	shield_hit_fx = 1.0
	game.notify(self, "damage_number", [center() + fwd(yaw) * 1.2, amount, Color(0.45, 0.75, 1.0), "흡수 "])
	if shield <= 0.0:
		shield_t = 0.0
		game.sfx("shield_break", pos)
		game.notify(self, "toast", ["보호막이 깨졌습니다"])
	else:
		game.sfx("shield_hit", pos)


func on_stealth_end() -> void:
	game.notify(self, "toast", ["은신이 풀렸습니다"])


func look(rel: Vector2, sens: float) -> void:
	if frozen > 0.0:
		return
	var k := sens * (0.55 if zoom else 1.0)
	yaw -= rel.x * k
	pitch = clampf(pitch - rel.y * k, -1.5, 1.5)


func eye_height() -> float:
	return EYE * (0.7 if panther else 1.0)


# 조준: 시선 위치와 방향 (원격 플레이어도 같은 계산)
func aim() -> Dictionary:
	var b := Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)
	var dir := -b.z
	var eye := Vector3(pos.x, pos.y + eye_height(), pos.z)
	return {"origin": eye + dir * 0.5 + Vector3(0, -0.12, 0), "dir": dir, "target": null}


func update(dt: float) -> void:
	if game.net == "client":
		update_client(dt)
		return
	inp.begin_frame()
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
	Skills.tick_soul_storm(self, dt)
	Skills.tick_barrier(self, dt)
	if cast > 0.0:
		cast -= dt

	var can_act: bool = inp.can_act if inp.remote else game.can_act()
	var locked := incapacitated()
	_movement(dt, locked, can_act)

	var act := can_act and not locked and channel_t <= 0.0
	_combat(dt, act)

	# 소모품 칸 1/2/3 (비어 있으면 가방에서 같은 종류)
	if not locked and can_act and cd.potion <= 0.0:
		for i in 3:
			if inp.just_pressed("potion%d" % (i + 1)):
				var it = equipment.get("q%d" % (i + 1))
				if it == null:
					game.notify(self, "toast", ["소모품 칸 %d이 비어 있습니다" % (i + 1)])
				else:
					var b: Dictionary = Data.base_of(it)
					if b.has("heal") and hp >= max_hp:
						game.notify(self, "toast", ["체력이 가득 찼습니다"])
					elif b.has("mana") and (res_type() != "mana" or res >= res_max()):
						game.notify(self, "toast", ["마나가 가득 찼거나 쓸 수 없습니다"])
					else:
						use_consumable(it.id)
	# 무기 세트 교체 / 투척
	if can_act and not locked and inp.just_pressed("swap_weapon"):
		swap_weapon_set()
	if can_act and not locked and inp.just_pressed("throw"):
		Skills.throw_utility(self, aim())

	# 원격 플레이어: 클라이언트가 보낸 위치를 검증 후 채택 (넉백/돌진 중에는 서버 위치 유지)
	if inp.remote and has_net:
		if knock.length_squared() > 0.5 or dash != null:
			forced_t = 0.35
		if forced_t > 0.0:
			forced_t -= dt
		elif Vector2(net_pos.x - pos.x, net_pos.z - pos.z).length() < 4.0:
			var np = game.dungeon.resolve_circle(net_pos, radius)
			pos = Vector3(np.x, maxf(0.0, net_pos.y), np.z)


# 클라이언트 본인: 이동은 즉시 로컬에서 처리하고, 전투 결과/상태는 서버(me 패킷)에서 받음
func update_client(dt: float) -> void:
	shield_hit_fx = maxf(0.0, shield_hit_fx - dt * 3.0)
	for k in cd:
		if cd[k] > 0.0:
			cd[k] -= dt
	for k in ["stun", "root", "slow", "parry", "immune", "frozen", "stealth", "shield_t", "channel_t", "spin_t", "hit_flash"]:
		var v: float = get(k)
		if v > 0.0:
			set(k, maxf(0.0, v - dt))
	if cast > 0.0:
		cast -= dt
	if swing != null:
		swing.t += dt
		if swing.t >= swing.prof.dur:
			swing = null
	swinging = swing != null or spin_t > 0.0
	if not alive:
		return
	_movement(dt, incapacitated(), game.can_act())


func _movement(dt: float, locked: bool, can_act: bool) -> void:
	# 이동 입력 (메뉴/인벤토리가 열려 있어도 이동 가능 - 던전본처럼 게임은 계속 진행)
	var ix := 0.0
	var iz := 0.0
	if not locked and not game.typing:
		iz = inp.strength("move_forward") - inp.strength("move_back")
		ix = inp.strength("move_right") - inp.strength("move_left")
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
	var want_sprint := inp.pressed("sprint") and iz > 0.0 and not locked
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

	var dashing := forced_t > 0.0 if game.net == "client" else Skills.tick_dash(self, dt)
	if not dashing:
		move(wish.x * speed, wish.z * speed, dt)
	last_vel = wish * speed
	moving = wl > 0.0 and dash == null and root <= 0.0 and not locked
	if moving:
		bob += dt * speed * 1.9
		step_t -= dt * speed
		if step_t <= 0.0:
			step_t = 2.6
			if stealth <= 0.0 and self == game.player:
				Sfx.play("step", -1.0, 0.15)

	# 점프
	if can_act and inp.just_pressed("jump") and pos.y <= 0.001 and stamina > SPRINT_MIN and not locked and root <= 0.0:
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


func _start_swing(prof: Dictionary, bash := false) -> void:
	swing_side = -swing_side
	swing = {"t": 0.0, "prof": prof, "done": false, "side": swing_side, "bash": bash}
	stamina -= prof.stamina
	stamina_delay = 0.6
	cd.lmb = prof.cd / stats.get("act_mul", 1.0)
	game.sfx("swing", pos)
	if inp.remote:
		game.notify(self, "swing", [swing_side, bash, prof.dur])


func _combat(dt: float, act: bool) -> void:
	var melee := Skills.is_melee(self)
	var rmb_pressed := act and inp.just_pressed("secondary")
	var rmb_held := act and inp.pressed("secondary")
	var lmb_held := act and inp.pressed("attack")
	var free := swing == null and spin_t <= 0.0 and dash == null

	# 우클릭: 방패/무기 방어, 패링, 단검 투척, 지팡이 치기, 표범 포효
	blocking = false
	if Skills.uses_block(self):
		blocking = rmb_held and stamina > 0.0 and free
	elif rmb_pressed:
		if cls == "swordmaster":
			Skills.start_parry(self)
		elif cls == "rogue":
			Skills.throw_knife(self, aim())
		elif panther:
			Skills.roar(self)
		elif free and cd.rmb <= 0.0:
			cd.rmb = 0.8
			_start_swing(Skills.melee_profile(self, true), true)

	# 좌클릭
	if lmb_held and free and not blocking and cd.lmb <= 0.0:
		if melee:
			var prof := Skills.melee_profile(self)
			if stamina >= prof.stamina:
				_start_swing(prof)
		elif Skills.fire_basic(self, aim()):
			cast = 0.2

	# Q / E (화염 폭발·치료는 누르고 있다가 놓으면 발동, F를 누른 채면 자신에게)
	for slot in ["q", "e"]:
		var key = "skill_" + slot
		var sid := Skills.skill_id(self, slot)
		var holding: float = hold_q if slot == "q" else hold_e
		if sid in Skills.HOLD_SKILLS:
			if act and inp.pressed(key) and cd[slot] <= 0.0:
				holding = maxf(holding, 0.0) + dt
				charge_t = holding
			elif holding >= 0.0:
				var a := aim()
				a["self"] = inp.pressed("interact")
				var charge := holding if sid == "pyro_pyroblast" else clampf(holding / 1.5, 0.0, 1.0)
				if Skills._use(self, slot, a, charge):
					cast = 0.3
				holding = -1.0
				charge_t = -1.0
			if slot == "q":
				hold_q = holding
			else:
				hold_e = holding
		elif act and inp.just_pressed(key):
			var a := aim()
			a["self"] = inp.pressed("interact")
			if Skills._use(self, slot, a, 1.0):
				cast = 0.3

	swinging = swing != null or spin_t > 0.0
	if swing != null:
		swing.t += dt
		if not swing.done and swing.t >= swing.prof.hit_at:
			swing.done = true
			Skills.melee_strike(self, swing.prof)
		if swing.t >= swing.prof.dur:
			swing = null


func use_consumable(id: String) -> void:
	var it = null
	var slot := Inv.slot_of(equipment, id)
	var i := Inv.index_of(bag, id)
	if slot != "":
		it = equipment[slot]
	elif i >= 0:
		it = bag[i]
	if it == null:
		return
	var b: Dictionary = Data.ITEM_BASES[it.base]
	it.count = int(it.get("count", 1)) - 1
	if it.count <= 0:
		if slot != "":
			equipment[slot] = null
		else:
			bag.remove_at(i)
	if b.has("heal"):
		apply_heal(b.heal * stats.get("heal_mul", 1.0), 3.0 if it.base == "health_potion" else 2.0)
	if b.has("mana"):
		Skills.gain(self, b.mana)
	cd.potion = 1.2
	add_slow(1.0, 0.6)
	game.sfx("heal", pos)
	game.notify(self, "toast", ["%s 사용" % b.name])
	game.inv_changed(self)


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
	var eye := eye_height()
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


# ------------------------------------------------------------------ 멀티플레이 동기화
func client_swing(side: float, bash: bool, dur: float) -> void:
	swing_side = side
	swing = {"t": 0.0, "prof": {"dur": dur, "hit_at": 99.0}, "done": true, "side": side, "bash": bash}


# 서버 -> 해당 클라이언트: 본인 상태 (초당 20회)
func net_state() -> Dictionary:
	return {
		"p": pos, "f": forced_t > 0.0 or dash != null, "a": alive,
		"hp": hp, "mh": max_hp, "he": heal, "sh": shield, "sm": shield_max, "st": shield_t, "sc": shield_color, "shf": shield_hit_fx,
		"r": res, "sta": stamina, "ex": exhausted,
		"cd": [cd.lmb, cd.rmb, cd.q, cd.e, cd.potion, cd.util],
		"chg": charges, "hold": [hold_q, hold_e],
		"s": [stun, slow, root, stealth, frozen, parry, immune, dr, spin_t, channel_t, charge_t, cast],
		"sm2": slow_mul, "dot": dots.size(), "bl": blocking, "pa": panther,
		"k": [kills, pvp_kills], "ch": ch,
	}


func apply_net_state(d: Dictionary) -> void:
	var sp: Vector3 = d.p
	if d.f or pos.distance_to(sp) > 2.5 or not d.a:
		pos = pos.lerp(sp, 0.5) if pos.distance_to(sp) < 3.0 else sp
	forced_t = 0.2 if d.f else 0.0
	alive = d.a
	hp = d.hp
	max_hp = d.mh
	heal = d.he
	shield = d.sh
	shield_max = d.sm
	shield_t = d.st
	shield_color = d.sc
	shield_hit_fx = maxf(shield_hit_fx, d.shf)
	res = d.r
	if absf(stamina - d.sta) > 4.0:
		stamina = d.sta
	exhausted = d.ex
	var c: Array = d.cd
	cd.lmb = c[0]
	cd.rmb = c[1]
	cd.q = c[2]
	cd.e = c[3]
	cd.potion = c[4]
	if c.size() > 5:
		cd.util = c[5]
	charges = int(d.get("chg", charges))
	var hold: Array = d.get("hold", [-1.0, -1.0])
	hold_q = hold[0]
	hold_e = hold[1]
	var s: Array = d.s
	stun = s[0]
	slow = s[1]
	root = s[2]
	stealth = s[3]
	frozen = s[4]
	parry = s[5]
	immune = s[6]
	dr = s[7]
	spin_t = s[8]
	channel_t = s[9]
	charge_t = s[10]
	cast = maxf(cast, s[11])
	slow_mul = d.sm2
	dots.resize(int(d.dot))
	blocking = d.bl
	if panther != d.pa:
		panther = d.pa
		game.on_shapeshift(self)
	kills = d.k[0]
	pvp_kills = d.k[1]
