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
var psi_lmb := true
var counter_rmb := true
var psi_rmb := true
var combo_i := 0 # 로그 단검 콤보 단계
var combo_t := 0.0
var mana_item = null # 마나가 장전된 지금 무기
var reload_t := 0.0 # 석궁 재장전 남은 시간
var reload_item = null
var held := "" # 손에 든 것: 소모품 칸("c3"/"c4"/"c5") 또는 "torch", 비어 있으면 무기
var torch_t := 0.0 # 불붙은 횃불 남은 시간
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
	if st.res == "mana":
		# 마나는 지팡이/오브에 장전된 것: 던전에 가지고 들어간 무기는 가득 찬 상태
		for s in ["w1", "w1o", "w2", "w2o"]:
			var w = equipment.get(s)
			if w != null and Data.base_of(w).get("cat", "") in ["staff", "orb"]:
				w["mana"] = st.res_max
		mana_item = _caster_weapon()
	# 던전에 가지고 들어간 석궁은 모두 장전된 상태
	for s2 in ["w1", "w2"]:
		var cb = equipment.get(s2)
		if cb != null and Data.base_of(cb).get("cat", "") == "crossbow":
			cb["loaded"] = true
		res = float(mana_item.get("mana", 0.0)) if mana_item != null else 0.0
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
	_sync_weapon_mana()
	block_mul = 1.0 - st.block_pct / 100.0 if st.block_pct > 0.0 else 0.4
	game.on_weapon_changed(self)


# 석궁: 가방에 든 볼트로 재장전 (장착 칸 없음). 쏘면 가방 볼트 1개를 넣어 다시 장전,
# 석궁을 가방으로 내리면 장전이 풀림. 던전 입장 시 장착한 석궁은 장전된 상태
func active_crossbow():
	var w = equipment.get("w%d" % wset)
	return w if w != null and Data.base_of(w).get("cat", "") == "crossbow" else null


func bolt_count() -> int:
	var n := 0
	for it in bag:
		if it.base == "bolts":
			n += int(it.get("count", 1))
	return n


func _take_bolt() -> bool:
	for i in bag.size():
		var it = bag[i]
		if it.base == "bolts":
			it.count = int(it.get("count", 1)) - 1
			if it.count <= 0:
				bag.remove_at(i)
			return true
	return false


func _tick_reload(dt: float) -> void:
	for it in bag:
		if it.get("loaded", false):
			it.erase("loaded")
	var cb = active_crossbow()
	if cb == null or cb.get("loaded", false):
		reload_t = 0.0
		reload_item = null
		return
	if bolt_count() <= 0:
		reload_t = 0.0
		reload_item = null
		return
	if reload_item != cb:
		reload_item = cb
		reload_t = 1.4 / stats.get("act_mul", 1.0)
		game.sfx("draw_wood", pos, 0.05)
	reload_t -= dt
	if reload_t <= 0.0:
		if _take_bolt():
			cb["loaded"] = true
		reload_item = null
		game.inv_changed(self)


# 지금 손에 든 세트의 마나 무기 (지팡이 또는 오브)
func _caster_weapon():
	for s in ["w%d" % wset, "w%do" % wset]:
		var w = equipment.get(s)
		if w != null and Data.base_of(w).get("cat", "") in ["staff", "orb"]:
			return w
	return null


# 무기를 바꾸면 그 무기에 남은 마나로 (던전 안에서 새로 낀 무기는 0부터 재생)
func _sync_weapon_mana() -> void:
	if res_type() != "mana":
		return
	var w = _caster_weapon()
	if w == mana_item:
		return
	if mana_item != null:
		mana_item["mana"] = res
	mana_item = w
	res = minf(float(w.get("mana", 0.0)), res_max()) if w != null else 0.0


# 무기 세트 교체 (X)
func swap_weapon_set() -> void:
	if swing != null or spin_t > 0.0 or dash != null:
		return
	wset = 2 if wset == 1 else 1
	if panther and Skills.wcat(self) == "":
		Skills.set_panther(self, false)
	recalc()
	draw_weapon()
	game.notify(self, "toast", ["무기 세트 %d (%d키)" % [wset, wset]])
	game.inv_changed(self)
	game.on_weapon_changed(self)


func on_block(_amount: float) -> void:
	game.sfx("block", pos)


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
	Skills.tick_psionic(self, dt)
	_tick_reload(dt)
	if combo_t > 0.0:
		combo_t -= dt
	if cast > 0.0:
		cast -= dt

	var can_act: bool = inp.can_act if inp.remote else game.can_act()
	var locked := incapacitated()
	_movement(dt, locked, can_act)

	var act := can_act and not locked
	_combat(dt, act)

	# 1/2: 무기 세트 선택 · 3/4/5: 소모품 꺼내기(같은 키 = 내려놓기), 좌클릭으로 사용 · G: 횃불
	if can_act and not locked:
		for k in [1, 2]:
			if inp.just_pressed("weapon%d" % k):
				set_held("")
				if wset != k:
					swap_weapon_set()
		for k in ["3", "4", "5"]:
			if inp.just_pressed("use" + k):
				pick_slot("c" + k)
		if inp.just_pressed("torch"):
			toggle_torch()
	if held == "torch":
		torch_t -= dt
		if torch_t <= 0.0:
			torch_t = 0.0
			set_held("")
			game.notify(self, "toast", ["횃불이 다 탔습니다"])

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
	for k in ["stun", "root", "slow", "parry", "immune", "frozen", "stealth", "shield_t", "channel_t", "spin_t", "hit_flash", "draw_t"]:
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

	# 던전본처럼 달리기/스태미나 없음: 이동 속도는 장비·능력치로만 정해짐
	sprinting = false
	var speed: float = stats.base_speed * stats.speed_mul
	if sprinting:
		speed *= 1.45
	if blocking:
		speed *= 0.55
	if spin_t > 0.0:
		speed *= 0.75
	if channel_t > 0.0 or channel_ready or charge_t >= 0.0:
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
	if can_act and inp.just_pressed("jump") and pos.y <= 0.001 and not locked and root <= 0.0:
		vy = 6.2
	vy -= 20.0 * dt
	pos.y = maxf(0.0, pos.y + vy * dt)
	if pos.y == 0.0:
		vy = 0.0

	stamina = 100.0
	exhausted = false


func _start_swing(prof: Dictionary, bash := false) -> void:
	swing_side = prof.side if prof.has("side") else -swing_side
	swing = {"t": 0.0, "prof": prof, "done": false, "side": swing_side, "bash": bash}
	cd.lmb = prof.cd / stats.get("act_mul", 1.0)
	game.sfx("swing", pos)
	if inp.remote:
		game.notify(self, "swing", [swing_side, bash, prof.dur, prof.hit_at])


func _combat(dt: float, act: bool) -> void:
	var melee := Skills.is_melee(self)
	var rmb_pressed := act and inp.just_pressed("secondary")
	var rmb_held := act and inp.pressed("secondary")
	var lmb_held := act and inp.pressed("attack")
	var free := swing == null and spin_t <= 0.0 and dash == null

	# 우클릭: 방패/무기 방어, 패링, 단검 투척, 지팡이 치기, 표범 포효
	blocking = false
	var rmb_new := rmb_held and not counter_rmb
	counter_rmb = rmb_held
	if counter_t > 0.0 and rmb_new and swing == null and held == "":
		# 패링 성공 후 우클릭: 강력한 반격
		counter_t = 0.0
		var cp := Skills.melee_profile(self)
		cp.dmg *= 2.4
		cp.hit_at = 0.16
		cp.dur = 0.45
		cp["side"] = -1.0
		cp["power"] = true
		cp.range += 0.4
		_start_swing(cp)
		game.notify(self, "toast", ["반격!"])
	elif Skills.uses_block(self):
		blocking = rmb_held and free and draw_t <= 0.0 and not psi_on and held == ""
	elif rmb_pressed:
		if panther:
			Skills.roar(self)
		elif free and cd.rmb <= 0.0:
			cd.rmb = 0.8
			_start_swing(Skills.melee_profile(self, true), true)

	block_t = block_t + dt if blocking else 0.0
	# 좌클릭을 새로 누른 순간 (심령의 검: 누른 채로 소환을 시작했으면 한 번 떼야 발사)
	var lmb_edge := lmb_held and not psi_lmb
	psi_lmb = lmb_held
	var rmb_edge := rmb_held and not psi_rmb
	psi_rmb = rmb_held
	# 소모품을 들고 있으면: 좌클릭 = 사용, 우클릭 = 내려놓기
	if held == "torch":
		blocking = false
		if act and inp.just_pressed("attack") and cd.lmb <= 0.0 and free:
			# 횃불 휘두르기: 약한 화염 피해
			cd.lmb = 0.8
			attack_anim = 0.25
			game.sfx("swing", pos)
			game.melee_hit(self, 18.0 * dmg_mul(), 2.4, 1.6, {"knock": 2.0})
		elif rmb_pressed:
			set_held("")
	elif held != "":
		blocking = false
		if equipment.get(held) == null:
			set_held("")
		elif act and inp.just_pressed("attack"):
			use_held()
		elif rmb_pressed:
			set_held("")
	# 지팡이 (화염: 누르는 동안 레이저 / 번개: 조준점 번개)
	elif Skills.staff_mode(self) != "":
		if Skills.staff_mode(self) == "fire":
			Skills.tick_beam(self, dt, lmb_held and draw_t <= 0.0, aim())
		elif lmb_edge and draw_t <= 0.0:
			Skills.lightning_strike(self, aim())
	# 은신 집중 중: 우클릭 = 취소, 준비 완료 후 좌클릭 = 은신 (좌클릭 안 하면 준비 상태 유지)
	elif channel_t > 0.0 or channel_ready:
		blocking = false
		if rmb_edge:
			Skills.cancel_channel(self)
		elif channel_ready and lmb_edge:
			Skills.activate_channel(self)
	# 좌클릭
	elif psi_on:
		# 심령의 검 소환 중: 좌클릭 = 소환된 만큼 발사, 우클릭 = 취소 (재사용 대기 없음)
		blocking = false
		if lmb_edge and psi_n > 0:
			if Skills.fire_psionic(self, aim()):
				cast = 0.3
		elif rmb_pressed or rmb_edge:
			Skills.cancel_psionic(self)
			game.notify(self, "toast", ["심령의 검 취소"])
	elif lmb_held and free and not blocking and cd.lmb <= 0.0 and draw_t <= 0.0:
		if melee:
			var prof: Dictionary
			if cls == "rogue" and not panther and Skills.wcat(self) == "dagger":
				var bt = Skills.backstab_target(self)
				if bt != null:
					# 뒤를 잡으면 양손 내려찍기 (패시브처럼 자동)
					prof = Skills.backstab_profile(self)
					combo_i = 0
				else:
					if combo_t <= 0.0:
						combo_i = 0
					prof = Skills.rogue_combo_profile(self, combo_i)
					combo_i = (combo_i + 1) % Skills.ROGUE_COMBO.size()
					combo_t = 1.0
			else:
				prof = Skills.melee_profile(self)
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


func set_held(k: String) -> void:
	if held == k:
		return
	held = k
	if k == "":
		draw_weapon()
	else:
		draw_t = 0.3
		game.sfx("draw_soft", pos, 0.05)
	game.on_weapon_changed(self)


# 무기 꺼내기: 잠깐 공격할 수 없고 무기에 맞는 소리 (칼 뽑는 소리 / 무거운 나무)
func draw_weapon() -> void:
	var cat := Skills.wcat(self)
	if cat == "":
		draw_t = 0.25
		return
	draw_t = 0.6 if cat in Data.TWO_HANDED else 0.45
	var snd := "draw_wood" if cat in ["crossbow", "staff", "orb"] else ("draw_blade" if cat in ["sword", "longsword", "dagger"] else "draw_soft")
	game.sfx(snd, pos, 0.05)


# 3/4/5: 그 칸의 소모품을 손에 듦 (다시 누르면 무기로)
func pick_slot(slot: String) -> void:
	if held == slot:
		set_held("")
		return
	var it = equipment.get(slot)
	if it == null:
		game.notify(self, "toast", ["소모품 칸 %s이 비어 있습니다" % slot.right(1)])
		return
	set_held(slot)
	game.notify(self, "toast", ["%s %s (좌클릭: 사용)" % [Data.base_of(it).icon, Data.base_of(it).name]])


# 손에 든 소모품 사용 (좌클릭). 다 쓰면 무기로
func use_held() -> void:
	var slot := held
	use_slot(slot, int(slot.right(1)))
	if equipment.get(slot) == null:
		set_held("")


# G: 횃불 켜서 들기 / 내려놓기 (불붙은 횃불은 다 탈 때까지 다시 들 수 있음)
func toggle_torch() -> void:
	if held == "torch":
		set_held("")
		return
	if torch_t <= 0.0:
		var t = equipment.get("torch")
		if t == null:
			game.notify(self, "toast", ["횃불이 없습니다"])
			return
		t.count = int(t.get("count", 1)) - 1
		if t.count <= 0:
			equipment.torch = null
		torch_t = float(Data.base_of(t).get("burn", 120.0))
		game.sfx("fire", pos)
		game.inv_changed(self)
	set_held("torch")


# 던전 입장 시 기본 횃불 2개
func give_start_torches() -> void:
	var t = equipment.get("torch")
	if t == null:
		t = Data.make_item("torch")
		equipment.torch = t
	t.count = maxi(int(t.get("count", 1)), 2)


func use_slot(slot: String, key: int) -> void:
	var it = equipment.get(slot)
	if it == null:
		game.notify(self, "toast", ["소모품 칸 %d이 비어 있습니다" % key])
		return
	var b: Dictionary = Data.base_of(it)
	if b.has("throw"):
		Skills.throw_flask(self, aim(), it, slot)
		return
	if cd.potion > 0.0:
		return
	if not b.has("heal"):
		return
	if hp >= max_hp:
		game.notify(self, "toast", ["체력이 가득 찼습니다"])
	else:
		use_consumable(it.id)


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
	var tr := 0.65 if stealth > 0.0 else 0.0
	if vm.get_meta("transparency", -1.0) != tr:
		vm.set_meta("transparency", tr)
		for n in vm.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).transparency = tr
	ViewAnim.animate(self, vm, b, dt)


# ------------------------------------------------------------------ 멀티플레이 동기화
func client_swing(side: float, bash: bool, dur: float, hit_at := -1.0) -> void:
	swing_side = side
	swing = {"t": 0.0, "prof": {"dur": dur, "hit_at": hit_at if hit_at >= 0.0 else dur * 0.4, "view_only": true}, "done": true, "side": side, "bash": bash}


# 서버 -> 해당 클라이언트: 본인 상태 (초당 20회)
func net_state() -> Dictionary:
	return {
		"p": pos, "f": forced_t > 0.0 or dash != null, "a": alive,
		"hp": hp, "mh": max_hp, "he": heal, "sh": shield, "sm": shield_max, "st": shield_t, "sc": shield_color, "shf": shield_hit_fx,
		"r": res, "sta": stamina, "ex": exhausted,
		"cd": [cd.lmb, cd.rmb, cd.q, cd.e, cd.potion, cd.util],
		"chg": charges, "hold": [hold_q, hold_e],
		"s": [stun, slow, root, stealth, frozen, parry, immune, dr, spin_t, channel_t, charge_t, cast],
		"sm2": slow_mul, "dot": dots.size(), "bl": blocking, "pa": panther, "hd": held, "tt": torch_t, "psi": psi_n if psi_on else -1, "chr": channel_ready, "dw": draw_t, "ld": active_crossbow() != null and active_crossbow().get("loaded", false), "rl": reload_t,
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
	torch_t = d.get("tt", 0.0)
	reload_t = d.get("rl", 0.0)
	var cbw = active_crossbow()
	if cbw != null:
		cbw["loaded"] = d.get("ld", false)
	var psi: int = int(d.get("psi", -1))
	psi_on = psi >= 0
	channel_ready = d.get("chr", false)
	psi_n = maxi(0, psi)
	draw_t = maxf(draw_t, float(d.get("dw", 0.0)) - 0.05)
	if held != d.get("hd", ""):
		held = d.get("hd", "")
		game._rebuild_view_model()
	if panther != d.pa:
		panther = d.pa
		game.on_shapeshift(self)
	kills = d.k[0]
	pvp_kills = d.k[1]
