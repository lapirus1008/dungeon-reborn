# 경쟁 모험가 AI: 던전본 8직업의 스킬을 상황에 맞게 사용, 상자 약탈, 물약, 탈출 판단
class_name Bot
extends AIActor

static var used_names := {}

var equipment: Dictionary
var bag: Array = []
var goal = null
var goal_timer := 0.0
var chest_t := 0.0
var extract_t := 0.0
var react_t := 0.0
var strafe_dir := 1.0
var strafe_t := 0.0
var skill_t := 0.0
var aim_err := 0.05
var courage := 0.5
var pending_prof = null # 윈드업 중인 근접 공격


static func _pick_name() -> String:
	var pool := []
	for n in Data.BOT_NAMES:
		if not used_names.has(n):
			pool.append(n)
	var n: String = pool.pick_random() if pool.size() else "Adventurer%d" % randi_range(1, 99)
	used_names[n] = true
	if used_names.size() > Data.BOT_NAMES.size() - 4:
		used_names.clear()
	return n


# 직업에 맞는 무기 세트 + 방어구 (깊을수록 좋은 등급)
static func _random_gear(c: String, depth: int) -> Dictionary:
	var luck := depth - 1 + randf()
	var by_cat := func(cat: String) -> String:
		var ks := []
		for k in Data.ITEM_BASES:
			var b: Dictionary = Data.ITEM_BASES[k]
			if b.slot == "weapon" and b.cat == cat and int(b.rarity) <= clampi(Data.roll_rarity(luck), 0, 5):
				ks.append(k)
		return ks.pick_random() if ks.size() else ""
	var eq := Account.empty_equipment()
	var cats: Array = Data.CLASSES[c].weapons
	var main_cats := cats.filter(func(x): return not (x in Data.OFFHAND))
	var mc: String = main_cats.pick_random()
	var w: String = by_cat.call(mc)
	eq.w1 = Data.make_item(w if w != "" else Data.STARTER_WEAPON[c])
	if not (Data.base_of(eq.w1).cat in Data.TWO_HANDED):
		var offs := cats.filter(func(x): return x in Data.OFFHAND)
		if c == "rogue":
			offs = ["dagger"]
		if offs.size() and randf() < 0.8:
			var o: String = by_cat.call(offs.pick_random())
			if o != "":
				eq.w1o = Data.make_item(o)
	var at: String = Data.STARTER_ARMOR[c]
	for slot in ["head", "chest", "hands", "legs", "feet"]:
		if randf() < 0.7:
			var r := clampi(Data.roll_rarity(luck), 0, 4)
			if r == 1:
				r = 0
			var ks := []
			for k in Data.ITEM_BASES:
				var b: Dictionary = Data.ITEM_BASES[k]
				if b.slot == slot and b.get("cat", "") == at and int(b.rarity) == r:
					ks.append(k)
			if ks.size():
				eq[slot] = Data.make_item(ks.pick_random())
	if randf() < 0.25:
		eq.necklace = Data.make_item(["bone_necklace", "wolf_pendant", "skull_amulet"].pick_random())
	if randf() < 0.3:
		eq.ring1 = Data.make_item(["copper_ring", "silver_ring", "ruby_ring"].pick_random())
	return eq


func _init(g, p: Vector3, depth: int, force_cls := "") -> void:
	var c: String = force_cls if force_cls != "" else Data.CLASS_ORDER.pick_random()
	var eq := _random_gear(c, depth)
	var st := Data.compute_stats(c, eq)
	var nm := _pick_name()
	super(g, {"kind": "bot", "name": nm, "faction": "bot_" + nm, "pos": p, "hp": st.max_hp, "armor": st.armor})
	cls = c
	equipment = eq
	stats = st
	res = st.res_max if st.res == "mana" else st.res_max * 0.5
	block_mul = 1.0 - st.block_pct / 100.0 if st.block_pct > 0.0 else 0.4
	# 무작위 Q/E 스킬 선택
	skills = {"q": Data.CLASSES[c].q.pick_random(), "e": Data.CLASSES[c].e.pick_random()}
	if c == "swordmaster":
		eq.sw1 = Data.make_item("old_sword")
		eq.sw2 = Data.make_item("old_sword")
	for i in randi_range(0, 2):
		bag.append(Data.make_item("health_potion"))
	if randf() < 0.4:
		bag.append_array(Data.roll_loot(1, depth - 1))
	strafe_dir = 1.0 if randf() < 0.5 else -1.0
	aim_err = randf_range(0.03, 0.08)
	courage = randf()
	attach_rig(Models.hero_rig(c, Data.weapon_model(c, eq, 1), eq.head != null))
	if c == "druid":
		attach_alt_rig(Models.panther_rig())


func display_name() -> String:
	return "%s (%s)" % [name, Data.CLASSES[cls].name]


func bag_value() -> int:
	return Data.items_value(bag)


func on_hurt(src) -> void:
	if src != null and src.alive and hostile_to(src):
		var cur = target
		if cur == null or not cur.alive or (src.kind != "monster" and cur.kind == "monster") or randf() < 0.3:
			target = src
			react_t = 0.15
	chest_t = 0.0
	extract_t = 0.0


func potion_count() -> int:
	var n := 0
	for i in bag:
		if i.base == "health_potion" or i.base == "bandage":
			n += 1
	return n


func use_potion() -> bool:
	for i in bag.size():
		var it: Dictionary = bag[i]
		if it.base == "health_potion" or it.base == "bandage":
			bag.remove_at(i)
			apply_heal(Data.ITEM_BASES[it.base].heal, 3.0)
			return true
	return false


# 가치 높은 순으로 가방에 담기 (최대 14칸)
func take_from(items: Array, mx := 99) -> int:
	items.sort_custom(func(a, b): return a.value > b.value)
	var n := 0
	while items.size() and bag.size() < 14 and n < mx:
		bag.append(items.pop_front())
		n += 1
	return n


func target_dist() -> float:
	if target == null:
		return 1e9
	return Vector2(target.pos.x - pos.x, target.pos.z - pos.z).length()


# AI 조준: 대상의 이동을 약간 예측하고 오차를 섞는다
func bot_aim() -> Dictionary:
	var origin := Vector3(pos.x, pos.y + height * 0.75, pos.z) + Actor.fwd(yaw) * 0.6
	if target == null:
		return {"origin": origin, "dir": Actor.fwd(yaw), "target": null}
	var to: Vector3 = target.center()
	to += target.last_vel * (origin.distance_to(to) / 32.0) * 0.6
	var dir := (to - origin).normalized()
	dir.x += randf_range(-1, 1) * aim_err
	dir.y += randf_range(-0.5, 0.5) * aim_err
	dir.z += randf_range(-1, 1) * aim_err
	return {"origin": origin, "dir": dir.normalized(), "target": target, "point": target.pos}


func update(dt: float) -> void:
	tick_common(dt)
	if not alive or extracted:
		return
	for k in cd:
		if cd[k] > 0.0:
			cd[k] -= dt
	if atk_cd > 0.0:
		atk_cd -= dt
	Skills.tick_resource(self, dt)
	Skills.tick_channel(self, dt)
	Skills.tick_spin(self, dt)
	Skills.tick_soul_storm(self, dt)
	Skills.tick_psionic(self, dt)
	Skills.tick_barrier(self, dt)
	if incapacitated():
		windup = 0.0
		move_amt = 0.0
		blocking = false
		return
	if Skills.tick_dash(self, dt):
		move_amt = 1.0
		return
	if channel_t > 0.0:
		move_amt = 0.0
		return
	if hp < max_hp * 0.45 and heal <= 0.0 and potion_count() > 0 and (target == null or target_dist() > 7.0):
		use_potion()

	sense_timer -= dt
	if sense_timer <= 0.0:
		sense_timer = 0.3
		if target != null and (not target.alive or target.extracted):
			target = null
		var seen = sense(24.0)
		# 보스는 용감한 봇만 먼저 건드림
		if seen != null and seen.kind == "monster" and seen.def.boss and courage < 0.85 and seen != last_attacker:
			seen = null
		if seen != null and (target == null or (seen != target and target_dist() > seen.pos.distance_to(pos) + 5.0)):
			if target != seen:
				react_t = randf_range(0.35, 0.85)
			target = seen
		if target != null:
			var lost: bool = target.stealth > 0.0 and target_dist() > 3.0
			if lost or target_dist() > 35.0 or (not game.dungeon.los(pos.x, pos.z, target.pos.x, target.pos.z) and randf() < 0.1):
				target = null

	if target != null:
		combat(dt)
		return
	blocking = false
	aim_anim = false
	# 적이 없을 때: 로그는 가끔 은신, 드루이드는 표범 형태 해제
	if cls == "rogue" and stealth <= 0.0 and cd.e <= 0.0 and randf() < dt * 0.05:
		Skills.use_e(self, bot_aim())
	if panther and res < 5.0:
		Skills.set_panther(self, false)
	explore(dt)


func combat(dt: float) -> void:
	var t = target
	var dx: float = t.pos.x - pos.x
	var dz: float = t.pos.z - pos.z
	var d := maxf(0.001, sqrt(dx * dx + dz * dz))
	var seen: bool = game.dungeon.los(pos.x, pos.z, t.pos.x, t.pos.z)
	var speed: float = stats.base_speed * stats.speed_mul * 0.95 * speed_factor() * (1.7 if panther else 1.0) * (0.75 if spin_t > 0.0 else 1.0)
	chest_t = 0.0
	extract_t = 0.0
	if react_t > 0.0:
		react_t -= dt
		turn_to(yaw_to(dx, dz), dt, 5.0)
		move_amt = 0.0
		return
	# 근접 윈드업 진행
	if windup > 0.0:
		windup -= dt
		turn_to(yaw_to(dx, dz), dt, 7.0)
		move(dx / d * speed * 0.4, dz / d * speed * 0.4, dt)
		if windup <= 0.0 and pending_prof != null:
			attack_anim = 0.25
			game.sfx("swing", pos)
			Skills.melee_strike(self, pending_prof)
			atk_cd = pending_prof.cd + randf_range(0.35, 0.7)
			pending_prof = null
		return
	strafe_t -= dt
	if strafe_t <= 0.0:
		strafe_t = randf_range(0.8, 2.3)
		strafe_dir *= -1.0
	skill_t -= dt
	if skill_t <= 0.0 and seen:
		skill_t = randf_range(0.3, 0.6)
		_use_skills(t, d)
	if Skills.is_melee(self):
		_melee_combat(dt, t, d, dx, dz, seen, speed)
	else:
		_ranged_combat(dt, t, d, dx, dz, seen, speed)


func _melee_combat(dt: float, t, d: float, dx: float, dz: float, seen: bool, speed: float) -> void:
	var prof := Skills.melee_profile(self)
	var threat: bool = (t.windup > 0.0 or t.swinging) and d < 4.0
	blocking = Skills.uses_block(self) and threat and randf() < 0.9 and atk_cd > 0.2
	if d > prof.range * 0.85 or not seen:
		blocking = false
		nav_to(t.pos, speed * (1.3 if d > 8.0 else 1.0), dt, 0.5)
		return
	turn_to(yaw_to(dx, dz), dt, 9.0)
	move(-dz / d * strafe_dir * speed * 0.35, dx / d * strafe_dir * speed * 0.35, dt)
	move_amt = 0.5
	if atk_cd <= 0.0 and not threat and spin_t <= 0.0:
		blocking = false
		pending_prof = prof
		windup = prof.hit_at + 0.15
		windup_max = windup


func _ranged_combat(dt: float, t, d: float, dx: float, dz: float, seen: bool, speed: float) -> void:
	var want := 11.0
	if not seen or d > want + 8.0:
		aim_anim = false
		nav_to(t.pos, speed, dt, 1.0)
		return
	turn_to(yaw_to(dx, dz), dt, 8.0)
	var mx := -dz / d * strafe_dir * 0.6
	var mz := dx / d * strafe_dir * 0.6
	if d < want - 4.0:
		mx -= dx / d
		mz -= dz / d
	elif d > want + 3.0:
		mx += dx / d
		mz += dz / d
	move(mx * speed * 0.7, mz * speed * 0.7, dt)
	move_amt = 0.6
	aim_anim = true
	if atk_cd <= 0.0 and Skills.fire_basic(self, bot_aim()):
		attack_anim = 0.25
		atk_cd = randf_range(0.5, 0.9)


# 고른 Q/E 스킬에 맞춰 사용 판단
func _use_skills(t, d: float) -> void:
	var aim := bot_aim()
	var near := 0
	for a in game.actors:
		if a.alive and a != self and hostile_to(a) and a.pos.distance_to(pos) < 3.5:
			near += 1
	var hpk := hp / max_hp
	if cls == "swordmaster" and (t.windup > 0.0 or t.swinging) and d < 4.0 and randf() < 0.6:
		Skills.start_parry(self)
	if cls == "rogue" and d > 5.0 and d < 14.0 and randf() < 0.3:
		Skills.throw_knife(self, aim)
	match Skills.skill_id(self, "q"):
		"fighter_whirlwind":
			if near >= 2 or d < 3.0:
				Skills.use_q(self, aim)
		"fighter_warcry":
			if d < 4.0:
				Skills.use_q(self, aim)
		"priest_revelation":
			if d < 14.0:
				Skills.use_q(self, aim)
		"priest_heal":
			if hpk < 0.6:
				var sa := aim.duplicate()
				sa["self"] = true
				Skills.use_q(self, sa, 1.0)
		"pyro_pyroblast":
			if d > 4.0 and d < 25.0:
				Skills.use_q(self, aim, 1.5 if res >= 40.0 else 0.6)
		"rogue_petrify":
			if d < 6.0:
				Skills.use_q(self, aim)
		"rogue_blades":
			if d > 3.0 and d < 12.0:
				Skills.use_q(self, aim)
		"dk_wraith_guard":
			if near >= 1:
				Skills.use_q(self, aim)
		"dk_soul_storm":
			if not soul_storm and near >= 1 and res > 30.0:
				Skills.use_q(self, aim)
			elif soul_storm and near == 0:
				Skills.use_q(self, aim)
		"cryo_blizzard":
			if d < 18.0:
				Skills.use_q(self, aim)
		"cryo_frost_curse":
			if d < 20.0:
				Skills.use_q(self, aim)
		"sm_psionic":
			if d < 20.0:
				Skills.use_q(self, aim)
		"druid_primal":
			if not panther and d < 9.0 and res >= 40.0:
				Skills.use_q(self, aim)
			elif panther and res < 20.0:
				Skills.use_q(self, aim)
	var sa := aim.duplicate()
	sa["self"] = true
	match Skills.skill_id(self, "e"):
		"fighter_charge":
			if d > 5.0 and d < 10.0:
				Skills.use_e(self, aim)
		"fighter_inspire":
			if d > 8.0 and randf() < 0.3:
				Skills.use_e(self, aim)
		"priest_holy_ward":
			if hpk < 0.35:
				Skills.use_e(self, sa)
		"priest_protection":
			if hpk < 0.75 and d < 8.0:
				Skills.use_e(self, aim)
		"pyro_fireshock":
			if d < 5.0:
				Skills.use_e(self, aim)
		"rogue_stealth", "rogue_shadow_veil":
			if stealth <= 0.0 and d > 14.0 and randf() < 0.05:
				Skills.use_e(self, aim)
		"rogue_quick_conceal":
			if stealth <= 0.0 and (hpk < 0.4 or (d > 8.0 and d < 14.0)):
				Skills.use_e(self, aim)
		"dk_soul_chain":
			if d > 5.0 and d < 16.0:
				Skills.use_e(self, aim)
		"cryo_ice_armor":
			if hpk < 0.65:
				Skills.use_e(self, sa)
		"cryo_ice_barrier":
			if hpk < 0.3:
				Skills.use_e(self, aim)
		"sm_blade_dance":
			if d < 5.0:
				Skills.use_e(self, aim)
		"druid_nature":
			if d < 14.0:
				Skills.use_e(self, aim)
		"druid_shadow_assault":
			if d > 3.0 and d < 9.0:
				Skills.use_e(self, aim)


func choose_goal() -> Dictionary:
	var g = game
	var tl: float = g.time_left
	var exits: Array = g.exit_portals()
	var want_out: bool = exits.size() > 0 and (tl < 120.0 + courage * 120.0 or bag_value() > 700 + courage * 1300 or (hp < max_hp * 0.3 and potion_count() == 0))
	if want_out:
		var p = g.nearest(exits, pos)
		if p != null:
			return {"type": "portal", "pos": p.pos, "ref": p}
	var bags := []
	for b in g.loot_bags:
		if b.items.size() and b.pos.distance_to(pos) < 25.0:
			bags.append(b)
	if bags.size():
		var b = g.nearest(bags, pos)
		return {"type": "bag", "pos": b.pos, "ref": b}
	var chests := []
	for c in g.chests:
		if c.opened:
			continue
		var claimer = c.get("claimed_by")
		if claimer != null and claimer != self and claimer.alive:
			continue
		if c.room.boss and courage <= 0.85 and not g.boss_dead:
			continue
		chests.append(c)
	if chests.size() and bag.size() < 14:
		var c = g.nearest(chests, pos)
		c["claimed_by"] = self
		return {"type": "chest", "pos": c.pos, "ref": c}
	var r: Dictionary = g.dungeon.rooms.pick_random()
	return {"type": "wander", "pos": g.dungeon.random_point_in_room(r)}


func explore(dt: float) -> void:
	var g = game
	goal_timer -= dt
	if goal == null or goal_timer <= 0.0 or (goal.type == "chest" and goal.ref.opened and chest_t <= 0.0):
		goal = choose_goal()
		goal_timer = 25.0
	if goal.type != "portal" and g.exit_portals().size() and randf() < dt * 0.5:
		var ng := choose_goal()
		if ng.type == "portal":
			goal = ng
	var speed: float = stats.base_speed * stats.speed_mul * 0.85
	var stop := 0.8 if goal.type == "portal" else (1.6 if goal.type in ["chest", "bag"] else 1.0)
	if not nav_to(goal.pos, speed, dt, stop):
		return
	match goal.type:
		"chest":
			var c = goal.ref
			if c.opened:
				take_from(c.items, 3)
				goal = null
				return
			chest_t += dt
			move_amt = 0.0
			if chest_t > 1.6:
				chest_t = 0.0
				g.open_chest(c, self)
				take_from(c.items, 3)
				goal = null
		"bag":
			take_from(goal.ref.items)
			g.refresh_bag(goal.ref)
			goal = null
		"portal":
			extract_t += dt
			move_amt = 0.0
			if extract_t > 3.0:
				g.bot_extract(self)
		_:
			goal = null


func all_items() -> Array:
	var out := []
	for s in Data.ALL_SLOTS:
		if equipment[s] != null:
			out.append(equipment[s])
	out.append_array(bag)
	return out
