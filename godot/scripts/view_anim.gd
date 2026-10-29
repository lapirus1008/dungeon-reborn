# 1인칭 뷰모델 애니메이션 (직업별 휘두르기/찌르기/시전/방어)
class_name ViewAnim
extends RefCounted

const R0_DEFAULT := Vector3(0.42, -0.37, -0.6)


static func animate(p, vm: Node3D, bob: float, _dt: float) -> void:
	var R: Node3D = vm.get_meta("R")
	var L: Node3D = vm.get_meta("L")
	var L0: Vector3 = vm.get_meta("L0", Vector3(-0.42, -0.37, -0.6))
	var R0: Vector3 = vm.get_meta("R0", R0_DEFAULT)
	vm.position = Vector3(sin(p.bob * 0.5) * (0.015 if p.moving else 0.0), bob * 0.4, 0)
	R.rotation = Vector3.ZERO
	R.position = R0
	L.rotation = Vector3.ZERO
	L.position = L0
	var t: float = p.game.time

	# 회오리 베기: 크게 휘돌림
	if p.spin_t > 0.0:
		var a := fmod(t * 14.0, TAU)
		R.rotation = Vector3(-0.4, sin(a) * 1.5, 0.6)
		R.position = R0 + Vector3(-sin(a) * 0.15, 0.05, 0)
		return
	# 마시기: 병을 든 오른손을 입으로 가져가 기울임
	# 붕대 감기: 두 손을 몸 앞 가운데로 모으고 오른손이 왼팔을 빙빙 감음
	if p.get("drink_t") != null and p.drink_t > 0.0 and p.get("drink_kind") == "bandage":
		var bk: float = 1.0 - clampf(p.drink_t / maxf(0.01, p.drink_max), 0.0, 1.0)
		var inn := clampf(bk / 0.15, 0.0, 1.0) * (1.0 - clampf((bk - 0.9) / 0.1, 0.0, 1.0))
		var ph: float = t * 9.0
		L.position = L0.lerp(Vector3(-0.05, -0.34, -0.46), inn)
		L.rotation = Vector3(0.5, 0.0, -0.9) * inn
		R.position = R0.lerp(Vector3(0.02 + cos(ph) * 0.06, -0.3 + sin(ph) * 0.05, -0.42), inn)
		R.rotation = Vector3(0.6, 0.0, 0.8) * inn
		return
	if p.get("drink_t") != null and p.drink_t > 0.0:
		var dk: float = 1.0 - clampf(p.drink_t / maxf(0.01, p.drink_max), 0.0, 1.0)
		var up := clampf(dk / 0.35, 0.0, 1.0) * (1.0 - clampf((dk - 0.85) / 0.15, 0.0, 1.0))
		R.position += Vector3(-0.34, 0.25, 0.28) * up
		R.rotation = Vector3(0.9 * up, 0.0, 0.5 * up + 0.4 * clampf((dk - 0.35) / 0.5, 0.0, 1.0) * up)
		return
	# 석궁 재장전: 석궁을 아래로 기울이고 왼손으로 볼트를 끼워 당김
	if p.reload_t > 0.0:
		var rk: float = 1.0 - clampf(p.reload_t / 1.4, 0.0, 1.0)
		var tilt := sin(clampf(rk * 1.25, 0.0, 1.0) * PI * 0.5) * (1.0 - clampf((rk - 0.85) / 0.15, 0.0, 1.0))
		R.position += Vector3(-0.08, -0.12, 0.05) * tilt
		R.rotation = Vector3(-0.7, 0.25, 0.35) * tilt
		var ins := clampf((rk - 0.3) / 0.4, 0.0, 1.0)
		L.position += Vector3(0.2, -0.05 + 0.1 * ins, 0.12 - 0.2 * ins) * tilt
		L.rotation = Vector3(-0.5 * ins, 0.0, 0.4) * tilt
		return
	# 은신 집중: 양손을 모음
	if p.channel_t > 0.0 or p.channel_ready:
		R.position = R0 + Vector3(-0.12, 0.05, 0.1)
		L.position = L0 + Vector3(0.12, 0.05, 0.1)
		return
	# 무기 꺼내는 중: 아래에서 들어 올림
	if p.draw_t > 0.0:
		var dk: float = clampf(p.draw_t / 0.6, 0.0, 1.0)
		R.position.y -= dk * 0.45
		R.rotation.x = dk * 1.2
		L.position.y -= dk * 0.4
	# 강공격 준비: 무기를 뒤로 크게 젖히고, 다 모이면 살짝 떨림
	var hv: float = p.get("heavy_t") if p.get("heavy_t") != null else -1.0
	if p.swing == null and hv >= Skills.HEAVY_MIN:
		var hk2 := clampf((hv - Skills.HEAVY_MIN) / (Skills.HEAVY_FULL - Skills.HEAVY_MIN), 0.0, 1.0)
		var e2 := sin(hk2 * PI * 0.5)
		var shake := (sin(t * 70.0) * 0.006) if hk2 >= 1.0 else 0.0
		if p.cls == "rogue" and Skills.wcat(p) == "dagger":
			# 단검: 두 손을 뒤로 당겨 찌를 준비
			R.position += Vector3(0.04, 0.06 + shake, 0.2) * e2
			L.position += Vector3(-0.04, 0.06 - shake, 0.2) * e2
			R.rotation.x = -0.3 * e2
			L.rotation.x = -0.3 * e2
		else:
			R.position += Vector3(0.12, 0.16 + shake, 0.16) * e2
			R.rotation = Vector3(0.9 * e2, 0.35 * e2, -0.5 * e2)
			if Skills.wcat(p) in Data.TWO_HANDED:
				L.position = R.position + R.basis * Vector3(-0.02, -0.11, 0.07)
				L.rotation = R.rotation
	# 지팡이 충전(R): 지팡이를 세우고, 왼손을 내밀어 손바닥의 마나(파란 빛)가 지팡이 머리로 흘러 들어감
	_mana_fx(vm, p.get("staff_charging") == true, t)
	if p.get("staff_charging") == true:
		R.position = R0 + Vector3(-0.06, 0.08 + sin(t * 6.0) * 0.01, 0.0)
		R.rotation = Vector3(0.2, 0.0, 0.12)
		L.position = L0 + Vector3(0.12, 0.12 + sin(t * 9.0) * 0.015, -0.12)
		L.rotation = Vector3(-0.4, 0.3, -0.5)
	if p.swing != null:
		var sw: Dictionary = p.swing
		var k: float = sw.t / sw.prof.dur
		# 예비 동작(뒤로 당김) -> 타격 순간(hit_at) -> 회수
		var hk: float = clampf(sw.prof.get("hit_at", sw.prof.dur * 0.4) / sw.prof.dur, 0.15, 0.8)
		var wind := k / hk if k < hk else 1.0
		var strike := 0.0 if k < hk else (1.0 - (k - hk) / (1.0 - hk))
		var s: float = sw.side
		if s >= 1.5:
			# 로그 기습: 양손을 머리 위로 들었다가 내려찍기
			var up := wind if k < hk else 0.0
			var down := sin(clampf((k - hk) / (1.0 - hk), 0.0, 1.0) * PI) if k >= hk else 0.0
			for arm in [R, L]:
				arm.position.y += up * 0.28 - down * 0.12
				arm.position.z -= down * 0.3
				arm.rotation.x = up * 1.4 - down * 1.2
			L.position.x += 0.12 * (up + down)
			R.position.x -= 0.12 * (up + down)
		elif s == 0.0 and p.cls == "rogue":
			# 3페이즈: 양손 X자 베기
			var a := wind * 0.4 if k < hk else strike
			R.position += Vector3(0.12 * a - 0.24 * (1.0 - a) * float(k >= hk), 0.15 * a, -0.1)
			L.position += Vector3(-0.12 * a + 0.24 * (1.0 - a) * float(k >= hk), 0.15 * a, -0.1)
			R.rotation = Vector3(-0.5 * a, 0.0, 0.9 * (a if k < hk else -a))
			L.rotation = Vector3(-0.5 * a, 0.0, -0.9 * (a if k < hk else -a))
		elif p.cls == "rogue" or p.panther or sw.bash:
			# 찌르기/할퀴기: 살짝 당겼다가 찌름 (우/좌 번갈아)
			var arm: Node3D = R if (s > 0.0 or p.cls == "druid" and not p.panther) else L
			var pull := wind * 0.1 if k < hk else 0.0
			var thrust := strike * 0.32 if k >= hk else 0.0
			arm.position.z += pull - thrust
			arm.position.y += thrust * 0.15
			if p.panther:
				arm.rotation.x = -thrust * 1.5
		else:
			# 베기: 오른손 무기는 오른쪽 어깨 위로 들었다가(백핸드는 왼쪽 어깨) 화면 가운데를 가로질러 반대쪽 아래로.
			# 양손 무기는 두 손이 몸 가운데에서 손잡이를 함께 잡고 같은 궤적으로 크게 휘두름
			var two: bool = Skills.wcat(p) in Data.TWO_HANDED or p.cls in ["swordmaster", "deathknight"]
			var fore := s > 0.0
			var W: Array
			var E: Array
			# 회전값은 "팔뚝 방향(손→팔꿈치)과 칼날 방향"이 목표에 맞도록 미리 계산한 값
			# (젖히기: 팔꿈치는 아래, 칼날은 어깨 위 뒤쪽 / 끝: 칼날이 반대쪽 앞 아래로 지나감)
			if two:
				W = [Vector3(0.28, 0.0, -0.62), Vector3(1.10, 0.50, -0.40)] if fore else [Vector3(-0.12, 0.0, -0.62), Vector3(1.00, 0.40, 0.60)]
				E = [Vector3(-0.2, -0.3, -0.62), Vector3(0.40, 0.30, 1.80)] if fore else [Vector3(0.36, -0.42, -0.62), Vector3(0.10, 0.30, -1.80)]
			else:
				W = [Vector3(0.42, -0.02, -0.6), Vector3(1.20, 0.70, 0.20)] if fore else [Vector3(-0.05, -0.02, -0.6), Vector3(0.70, 0.50, 1.20)]
				E = [Vector3(-0.12, -0.3, -0.6), Vector3(0.20, 0.40, 1.80)] if fore else [Vector3(0.48, -0.40, -0.62), Vector3(0.40, 0.10, -1.60)]
			var rest := [R.position, R.rotation]
			var pose := _swing_pose(k, hk, rest, W, E)
			R.position = pose[0]
			R.quaternion = pose[1]
			if two:
				# 왼손은 오른손 바로 아래에서 손잡이를 같이 잡음
				L.position = R.position + R.basis * Vector3(-0.02, -0.11, 0.07)
				L.rotation = R.rotation
	# 방어 자세: 우클릭을 누르면 평소 자세에서 GUARD_RAISE에 걸쳐 자연스럽게 올라감 (떼면 다시 내려감)
	var gk: float = vm.get_meta("gk", 0.0)
	gk = move_toward(gk, 1.0 if p.blocking else 0.0, _dt / (Actor.GUARD_RAISE if p.blocking else 0.18))
	vm.set_meta("gk", gk)
	if gk > 0.0:
		var e := gk * gk * (3.0 - 2.0 * gk)
		# 방패는 왼손을 앞으로, 무기는 가로로 세워 막음 (단검은 양손 교차)
		var off: String = Data.offhand_cat(p.equipment, p.wset)
		if off == "shield":
			L.position = L.position.lerp(Vector3(-0.16, -0.2, -0.5), e)
			L.rotation = L.rotation.lerp(Vector3(0, 0.5, 0), e)
		else:
			R.position = R.position.lerp(Vector3(0.06, -0.16, -0.48), e)
			R.rotation = R.rotation.lerp(Vector3(0.25, 0, 1.3), e)
			if off == "dagger":
				L.position = L.position.lerp(Vector3(-0.06, -0.18, -0.48), e)
				L.rotation = L.rotation.lerp(Vector3(0.25, 0, -1.3), e)
			elif Skills.wcat(p) in Data.TWO_HANDED:
				L.position = L.position.lerp(Vector3(-0.06, -0.18, -0.44), e)
	# 완전 방어 직후: 무기가 하얗게 빛남 (이때 우클릭 = 반격)
	_counter_glow(vm, p.counter_t)
	if p.parry > 0.0:
		R.position = Vector3(0.05, -0.15, -0.5)
		R.rotation = Vector3(0, 0, 1.3)
	if p.charge_t >= 0.0:
		# 프리스트 정화 충전: 책을 들어 올림
		var c := minf(1.0, p.charge_t / 1.2)
		L.position = L0 + Vector3(0.1, 0.08 + c * 0.05, -0.05)
	if p.cast > 0.0 and p.swing == null:
		R.position = R0 + Vector3(0, 0.08, -0.1)


static var _glow_mat: StandardMaterial3D


# R 충전 효과: 왼손 앞 파란 구슬 + 지팡이 머리까지 이어진 빛줄기 (흐르는 알갱이)
static func _mana_fx(vm: Node3D, on: bool, t: float) -> void:
	var fx: Node3D = vm.get_meta("mana_fx") if vm.has_meta("mana_fx") else null
	if fx == null or not is_instance_valid(fx):
		if not on:
			return
		fx = Node3D.new()
		var orb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.035
		sm.height = 0.07
		orb.mesh = sm
		orb.material_override = Models.glow_mat(Color(0.35, 0.6, 1.0), 6.0)
		orb.name = "Orb"
		fx.add_child(orb)
		for i in 6:
			var mote := MeshInstance3D.new()
			var ms := SphereMesh.new()
			ms.radius = 0.012
			ms.height = 0.024
			mote.mesh = ms
			mote.material_override = Models.glow_mat(Color(0.5, 0.75, 1.0), 5.0)
			mote.name = "M%d" % i
			fx.add_child(mote)
		var lt := OmniLight3D.new()
		lt.light_color = Color(0.4, 0.6, 1.0)
		lt.light_energy = 0.8
		lt.omni_range = 2.5
		lt.name = "Light"
		fx.add_child(lt)
		vm.add_child(fx)
		vm.set_meta("mana_fx", fx)
	fx.visible = on
	if not on:
		return
	var L: Node3D = vm.get_meta("L")
	var R: Node3D = vm.get_meta("R")
	var a := L.position + Vector3(0.02, 0.06, -0.08)
	var b := R.position + R.basis * Vector3(0, 0.55, -0.05) # 지팡이 머리 쪽
	var orb2: Node3D = fx.get_node("Orb")
	orb2.position = a
	orb2.scale = Vector3.ONE * (1.0 + 0.25 * sin(t * 14.0))
	(fx.get_node("Light") as Node3D).position = a
	for i in 6:
		var k := fmod(t * 1.6 + i / 6.0, 1.0)
		var m: Node3D = fx.get_node("M%d" % i)
		m.position = a.lerp(b, k) + Vector3(sin(t * 7.0 + i) * 0.015, sin(k * PI) * 0.05, 0)
		m.scale = Vector3.ONE * (1.0 - k * 0.5)


static func _counter_glow(vm: Node3D, ct: float) -> void:
	var on := ct > 0.0
	if not on and not vm.get_meta("glowing", false):
		return
	vm.set_meta("glowing", on)
	if _glow_mat == null:
		_glow_mat = StandardMaterial3D.new()
		_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_glow_mat.albedo_color = Color(1, 1, 1, 0.8)
	var w = vm.get_meta("weapon") if vm.has_meta("weapon") else null
	if w == null or not is_instance_valid(w):
		return
	var a := clampf(ct / 0.3, 0.0, 1.0) * (0.7 + 0.3 * sin(ct * 40.0))
	_glow_mat.albedo_color = Color(1, 1, 1, a)
	for n in (w as Node3D).find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).material_overlay = _glow_mat if on else null


# 휘두르기 자세 보간: 평소 → 젖히기(W, 타격 직전까지) → 빠르게 베어 끝 자세(E, 타격 순간 조금 뒤) → 평소로 회수
static func _swing_pose(k: float, hk: float, rest: Array, W: Array, E: Array) -> Array:
	var w_end := hk * 0.7
	var e_end := hk + (1.0 - hk) * 0.2
	var a: Array
	var b: Array
	var t: float
	if k < w_end:
		a = rest
		b = W
		t = k / w_end
	elif k < e_end:
		a = W
		b = E
		t = (k - w_end) / (e_end - w_end)
	else:
		a = E
		b = rest
		t = (k - e_end) / (1.0 - e_end)
	t = clampf(t, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	var qa := Basis.from_euler(a[1]).get_rotation_quaternion()
	var qb := Basis.from_euler(b[1]).get_rotation_quaternion()
	return [(a[0] as Vector3).lerp(b[0], t), qa.slerp(qb, t)]
