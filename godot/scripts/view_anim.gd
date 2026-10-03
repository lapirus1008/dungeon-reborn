# 1인칭 뷰모델 애니메이션 (직업별 휘두르기/찌르기/시전/방어)
class_name ViewAnim
extends RefCounted

const R0 := Vector3(0.3, -0.34, -0.6)


static func animate(p, vm: Node3D, bob: float, _dt: float) -> void:
	var R: Node3D = vm.get_meta("R")
	var L: Node3D = vm.get_meta("L")
	var L0: Vector3 = vm.get_meta("L0", Vector3(-0.3, -0.36, -0.6))
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
	# 은신 집중: 양손을 모음
	if p.channel_t > 0.0:
		R.position = R0 + Vector3(-0.12, 0.05, 0.1)
		L.position = L0 + Vector3(0.12, 0.05, 0.1)
		return
	if p.swing != null:
		var sw: Dictionary = p.swing
		var k: float = sw.t / sw.prof.dur
		var s: float = sw.side
		var thrust = p.cls == "rogue" or p.panther or sw.bash
		if thrust:
			# 찌르기/할퀴기: 양손 번갈아
			var amt := sin(k * PI)
			var arm: Node3D = R if (s > 0.0 or p.cls == "druid" and not p.panther) else L
			arm.position.z -= amt * 0.28
			arm.position.y += amt * 0.06
			if p.panther:
				arm.rotation.x = -amt * 0.5
		else:
			var heavy := 1.3 if p.cls == "deathknight" else 1.0
			var a := k / 0.35 if k < 0.35 else 1.0 - (k - 0.35) / 0.65
			R.rotation = Vector3(-0.6 * a * heavy, s * (1.4 - k * 2.8) * a, s * 0.6 * a)
			R.position.x = R0.x - s * 0.1 * a
			if p.cls in ["swordmaster", "deathknight"]:
				# 양손 무기: 왼손이 따라감
				L.position = R.position + Vector3(-0.08, -0.04, 0.08)
	if p.blocking:
		L.position = Vector3(-0.14, -0.2, -0.5)
		L.rotation.y = 0.5
		if p.cls == "deathknight":
			R.position = Vector3(0.05, -0.22, -0.5)
			R.rotation = Vector3(0, 0, 1.2)
	if p.parry > 0.0:
		R.position = Vector3(0.05, -0.15, -0.5)
		R.rotation = Vector3(0, 0, 1.3)
	if p.charge_t >= 0.0:
		# 프리스트 정화 충전: 책을 들어 올림
		var c := minf(1.0, p.charge_t / 1.2)
		L.position = L0 + Vector3(0.1, 0.08 + c * 0.05, -0.05)
	if p.cast > 0.0 and p.swing == null:
		R.position = R0 + Vector3(0, 0.08, -0.1)
