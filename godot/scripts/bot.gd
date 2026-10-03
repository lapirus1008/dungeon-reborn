# 경쟁 모험가 AI: 직업별 전투, 상자 약탈, 물약, 탈출 판단
class_name Bot
extends AIActor

const LOOK := {
	"fighter": {"body": Color(0.48, 0.5, 0.53), "legs": Color(0.23, 0.23, 0.25), "helmet": Color(0.54, 0.56, 0.6), "weapon": "sword", "shield": true, "metal": 0.6},
	"ranger": {"body": Color(0.2, 0.33, 0.18), "legs": Color(0.23, 0.18, 0.13), "helmet": Color(0.3, 0.25, 0.18), "weapon": "bow", "shield": false, "metal": 0.0},
	"mage": {"body": Color(0.18, 0.2, 0.44), "legs": Color(0.14, 0.15, 0.31), "helmet": Color(0.16, 0.18, 0.4), "weapon": "staff", "shield": false, "metal": 0.0},
}

static var used_names := {}

var cls := ""
var equipment: Dictionary
var stats: Dictionary
var bag: Array = []
var mana := 0.0
var goal = null
var goal_timer := 0.0
var chest_t := 0.0
var extract_t := 0.0
var react_t := 0.0
var strafe_dir := 1.0
var strafe_t := 0.0
var fireball_cd := 4.0
var aim_err := 0.05
var courage := 0.5


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


static func _random_gear(c: String, depth: int) -> Dictionary:
	var luck := depth - 1 + randf()
	var weapons := []
	for k in Data.ITEM_BASES:
		if Data.ITEM_BASES[k].slot == "weapon" and Data.ITEM_BASES[k].cls == c:
			weapons.append(k)
	var pick := func(slot: String) -> String:
		var ks := []
		for k in Data.ITEM_BASES:
			if Data.ITEM_BASES[k].slot == slot:
				ks.append(k)
		return ks.pick_random()
	return {
		"weapon": Data.make_item(Data.STARTER_WEAPON[c] if randf() < 0.35 else weapons.pick_random(), Data.roll_rarity(luck - 1)),
		"head": Data.make_item(pick.call("head"), Data.roll_rarity(luck - 1)) if randf() < 0.6 else null,
		"chest": Data.make_item(pick.call("chest"), Data.roll_rarity(luck - 1)) if randf() < 0.75 else null,
		"trinket": Data.make_item(pick.call("trinket"), Data.roll_rarity(luck)) if randf() < 0.3 else null,
	}


func _init(g, p: Vector3, depth: int) -> void:
	var c: String = Data.CLASSES.keys().pick_random()
	var eq := _random_gear(c, depth)
	var st := Data.compute_stats(c, eq)
	var nm := _pick_name()
	super(g, {"kind": "bot", "name": nm, "faction": "bot_" + nm, "pos": p, "hp": st.max_hp, "armor": st.armor})
	cls = c
	equipment = eq
	stats = st
	for i in randi_range(0, 2):
		bag.append(Data.make_item("health_potion"))
	if randf() < 0.4:
		bag.append_array(Data.roll_loot(1, depth - 1))
	mana = st.max_mana
	strafe_dir = 1.0 if randf() < 0.5 else -1.0
	aim_err = randf_range(0.03, 0.08)
	courage = randf()
	var look: Dictionary = LOOK[c]
	attach_model(Models.humanoid({
		"body": look.body, "legs": look.legs,
		"helmet": look.helmet if eq.head != null else null,
		"weapon": look.weapon, "shield": look.shield, "metal": look.metal,
	}))


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


func update(dt: float) -> void:
	tick_common(dt)
	if not alive or extracted:
		return
	if atk_cd > 0.0:
		atk_cd -= dt
	fireball_cd -= dt
	if stats.max_mana > 0:
		mana = minf(stats.max_mana, mana + dt * 7.0)
	if stun > 0.0:
		windup = 0.0
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
			if target_dist() > 35.0 or (not game.dungeon.los(pos.x, pos.z, target.pos.x, target.pos.z) and randf() < 0.1):
				target = null

	if target != null:
		combat(dt)
		return
	blocking = false
	aim_anim = false
	explore(dt)


func combat(dt: float) -> void:
	var t = target
	var dx: float = t.pos.x - pos.x
	var dz: float = t.pos.z - pos.z
	var d := maxf(0.001, sqrt(dx * dx + dz * dz))
	var seen: bool = game.dungeon.los(pos.x, pos.z, t.pos.x, t.pos.z)
	var speed: float = stats.base_speed * stats.speed_mul * 0.95
	chest_t = 0.0
	extract_t = 0.0
	if react_t > 0.0:
		react_t -= dt
		turn_to(yaw_to(dx, dz), dt, 5.0)
		move_amt = 0.0
		return
	if windup > 0.0:
		windup -= dt
		turn_to(yaw_to(dx, dz), dt, 6.0)
		if cls != "fighter":
			move_amt = 0.0
		else:
			move(dx / d * speed * 0.4, dz / d * speed * 0.4, dt)
		if windup <= 0.0:
			release()
		return
	strafe_t -= dt
	if strafe_t <= 0.0:
		strafe_t = randf_range(0.8, 2.3)
		strafe_dir *= -1.0
	if cls == "fighter":
		var threat: bool = (t.windup > 0.0 or t.swinging) and d < 4.0
		blocking = threat and randf() < 0.9 and atk_cd > 0.2
		if d > 2.4 or not seen:
			blocking = false
			nav_to(t.pos, speed * (1.3 if d > 8.0 else 1.0), dt, 0.5)
		else:
			turn_to(yaw_to(dx, dz), dt, 9.0)
			move(-dz / d * strafe_dir * speed * 0.35, dx / d * strafe_dir * speed * 0.35, dt)
			move_amt = 0.5
			if atk_cd <= 0.0 and not threat:
				blocking = false
				windup = 0.32
				windup_max = 0.32
	else:
		var want := 11.0 if cls == "ranger" else 12.0
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
		aim_anim = cls == "ranger"
		if atk_cd <= 0.0:
			if cls == "mage" and mana < 10.0:
				return
			windup = 0.55 if cls == "ranger" else 0.3
			windup_max = windup


func release() -> void:
	var t = target
	attack_anim = 0.25
	if t == null:
		return
	var dm: float = stats.dmg_mul * (0.65 if t.kind == "monster" else 1.0)
	match cls:
		"fighter":
			atk_cd = randf_range(1.0, 1.5)
			Sfx.play("swing", game.dist_to_player(pos))
			game.melee_hit(self, 22.0 * dm, 3.0, 1.4, {"knock": 4.0})
		"ranger":
			atk_cd = randf_range(1.3, 2.0)
			game.shoot_at(self, t, "arrow", 26.0 * dm, 48.0, aim_err)
		_:
			if fireball_cd <= 0.0 and mana >= 30.0 and target_dist() > 5.0:
				fireball_cd = 7.0
				mana -= 30.0
				atk_cd = 1.0
				game.shoot_at(self, t, "fireball", 40.0 * dm, 24.0, aim_err)
			else:
				mana -= 10.0
				atk_cd = randf_range(0.9, 1.4)
				game.shoot_at(self, t, "bolt", 18.0 * dm, 42.0, aim_err)


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
	for s in Data.GEAR_SLOTS:
		if equipment[s] != null:
			out.append(equipment[s])
	out.append_array(bag)
	return out
