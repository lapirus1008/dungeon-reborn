# 멀티플레이 대리 액터: 서버 스냅샷을 보간해 그리기만 한다 (AI/전투 없음)
# 호스트에서는 접속한 친구(원격 Player)의 모습을 그리는 꼭두각시로도 쓴다
class_name NetActor
extends AIActor

const DELAY := 0.1 # 보간 지연 (스냅샷 간격 0.05초의 2배)

var type := ""
var def: Dictionary = {}
var dname := ""
var buf: Array = [] # [수신 시각, 위치, yaw]


func _init(g, d: Dictionary) -> void:
	super(g, {"kind": d.k, "name": d.n, "faction": d.f, "pos": d.p, "hp": d.mh, "radius": d.r, "height": d.h})
	nid = d.id
	dname = d.n
	yaw = d.y
	match d.k:
		"monster":
			type = d.t
			def = Data.MONSTERS[type]
			attach_rig(Monster.build_rig(type))
			if def.boss:
				hp_bar.scale = Vector3(2, 2, 2)
		"summon":
			attach_rig(Models.treant_rig())
			if not rig.procedural:
				rig.node.scale = Vector3.ONE * 1.5
		_:
			cls = d.c
			attach_rig(Models.hero_rig(cls, d.w, d.hm))
			if cls == "druid":
				attach_alt_rig(Models.panther_rig())
	buf.append([g.time, pos, yaw])


func display_name() -> String:
	if kind == "player":
		return "%s (%s)" % [dname, Data.CLASSES[cls].name]
	return dname


# 스냅샷 한 줄: id, x, y, z, yaw, hp, flags, move, windup_k, attack
func push_snap(s: PackedFloat32Array) -> void:
	buf.append([game.time, Vector3(s[1], s[2], s[3]), s[4]])
	if buf.size() > 12:
		buf.pop_front()
	hp = s[5]
	var f := int(s[6])
	var was_alive := alive
	alive = (f & 1) != 0
	if was_alive and not alive:
		death_t = 0.0
	aim_anim = (f & 2) != 0
	blocking = (f & 4) != 0
	panther = (f & 8) != 0
	spin_t = 1.0 if (f & 16) != 0 else 0.0
	stealth = 1.0 if (f & 32) != 0 else 0.0
	mimic_form = (f & 128) != 0
	crouch = (f & 256) != 0
	quiet = (f & 512) != 0
	if (f & 64) != 0:
		hit_flash = 0.15
	move_amt = s[7]
	var wk: float = s[8]
	windup_max = 1.0
	windup = (1.0 - wk) if wk >= 0.0 else 0.0
	if s[9] > 0.0 and attack_anim <= 0.05:
		attack_anim = s[9]


func update(dt: float) -> void:
	if hit_flash > 0.0:
		hit_flash -= dt
	if frozen > 0.0:
		frozen -= dt
	# 0.1초 전 시점을 두 스냅샷 사이에서 보간
	var t: float = game.time - DELAY
	var n := buf.size()
	if n == 0:
		return
	if t <= buf[0][0]:
		pos = buf[0][1]
		yaw = buf[0][2]
	elif t >= buf[n - 1][0]:
		pos = buf[n - 1][1]
		yaw = buf[n - 1][2]
	else:
		for i in range(n - 1):
			var a: Array = buf[i]
			var b: Array = buf[i + 1]
			if t >= a[0] and t <= b[0]:
				var k: float = (t - a[0]) / maxf(0.0001, b[0] - a[0])
				pos = (a[1] as Vector3).lerp(b[1], k)
				yaw = lerp_angle(a[2], b[2], k)
				break
	last_vel = (pos - last_pos) / maxf(dt, 0.001)
	last_pos = pos


# 호스트: 원격 플레이어 상태를 그대로 복사
func mirror(p) -> void:
	pos = p.pos
	yaw = p.yaw
	hp = p.hp
	max_hp = p.max_hp
	alive = p.alive
	blocking = p.blocking
	panther = p.panther
	spin_t = p.spin_t
	stealth = p.stealth
	mimic_form = p.mimic_form
	crouch = p.crouch
	quiet = p.quiet
	hit_flash = p.hit_flash
	frozen = p.frozen
	move_amt = 1.0 if p.moving else 0.0
	if p.swing != null and p.swing.t < 0.05 and attack_anim <= 0.05:
		attack_anim = 0.25


func animate(dt: float) -> void:
	super(dt)
	# 나는 몬스터 (박쥐, 악마의 눈, 미믹 책)
	var fly: float = def.get("fly", 0.0)
	if fly > 0.0 and alive:
		var r := active_rig()
		r.node.position.y = fly + sin(game.time * 3.0 + nid) * 0.15
