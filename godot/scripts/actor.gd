# 액터 공통: 체력, 피해 처리, 상태이상, 이동
class_name Actor
extends RefCounted

var game # Game (순환 참조 방지를 위해 타입 미지정)
var kind := "" # "player" | "monster" | "bot"
var name := ""
var faction := ""
var pos := Vector3.ZERO
var yaw := 0.0
var radius := 0.45
var height := 1.9
var max_hp := 100.0
var hp := 100.0
var armor := 0.0
var alive := true
var extracted := false
var knock := Vector3.ZERO
var stun := 0.0
var slow := 0.0
var shield := 0.0
var invuln := 0.0
var blocking := false
var last_attacker = null
var hit_flash := 0.0
var heal := 0.0
var heal_rate := 0.0
var death_t := 0.0
var move_amt := 0.0
var walk_phase := 0.0
var attack_anim := 0.0
var windup := 0.0
var windup_max := 1.0
var swinging := false
var last_vel := Vector3.ZERO
var last_pos := Vector3.ZERO


func _init(g, o: Dictionary) -> void:
	game = g
	kind = o.kind
	name = o.name
	faction = o.faction
	pos = o.pos
	pos.y = 0.0
	last_pos = pos
	yaw = randf() * TAU
	radius = o.get("radius", 0.45)
	height = o.get("height", 1.9)
	max_hp = o.hp
	hp = o.hp
	armor = o.get("armor", 0.0)


func display_name() -> String:
	return name


func center() -> Vector3:
	return Vector3(pos.x, pos.y + height * 0.6, pos.z)


static func yaw_to(dx: float, dz: float) -> float:
	return atan2(-dx, -dz)


static func fwd(y: float) -> Vector3:
	return Vector3(-sin(y), 0, -cos(y))


func take_damage(amount: float, src, info: Dictionary = {}) -> float:
	if not alive or invuln > 0.0:
		return 0.0
	var dmg := amount
	var blocked := false
	if blocking:
		var from = info.get("from", src.pos if src != null else null)
		if from != null:
			var y := yaw_to(from.x - pos.x, from.z - pos.z)
			if absf(angle_difference(yaw, y)) < 1.25:
				blocked = true
				dmg *= 0.25
				on_block(amount)
	dmg *= 100.0 / (100.0 + armor)
	var absorbed := 0.0
	if shield > 0.0:
		absorbed = minf(shield, dmg)
		shield -= absorbed
		dmg -= absorbed
		on_shield_hit(absorbed)
	dmg = maxf(0.0, dmg)
	hp -= dmg
	hit_flash = 0.15
	if src != null and src != self:
		last_attacker = src
	if info.has("knock") and not blocked:
		knock += info.knock
	if info.has("stun") and not blocked:
		stun = maxf(stun, info.stun)
	info["absorbed"] = absorbed
	game.on_damage(self, dmg, src, blocked, info)
	on_hurt(src)
	if hp <= 0.0:
		hp = 0.0
		alive = false
		game.on_death(self, src)
	return dmg


func on_block(_amount: float) -> void:
	pass


func on_shield_hit(_amount: float) -> void:
	pass


func on_hurt(_src) -> void:
	pass


func apply_heal(amount: float, duration: float) -> void:
	heal += amount
	heal_rate = maxf(heal_rate, amount / duration)


func tick_common(dt: float) -> void:
	if stun > 0.0:
		stun -= dt
	if slow > 0.0:
		slow -= dt
	if invuln > 0.0:
		invuln -= dt
	if hit_flash > 0.0:
		hit_flash -= dt
	if heal > 0.0:
		var h := minf(heal, heal_rate * dt)
		heal -= h
		hp = minf(max_hp, hp + h)
		if heal <= 0.0:
			heal_rate = 0.0
	if knock.length_squared() > 0.001:
		pos.x += knock.x * dt
		pos.z += knock.z * dt
		knock *= maxf(0.0, 1.0 - dt * 8.0)
		pos = game.dungeon.resolve_circle(pos, radius)


func move(dx: float, dz: float, dt: float) -> void:
	pos.x += dx * dt
	pos.z += dz * dt
	pos = game.dungeon.resolve_circle(pos, radius)


func update(_dt: float) -> void:
	pass
