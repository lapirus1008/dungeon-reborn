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
			# 베기: 반대쪽으로 크게 젖혔다가 휘두름
			var heavy := 1.3 if p.cls == "deathknight" else 1.0
			var a := wind if k < hk else strike
			var sweep := 1.4 if k < hk else (1.4 - 2.8 * (1.0 - strike))
			R.rotation = Vector3(-0.6 * a * heavy, s * sweep * a, s * 0.6 * a)
			R.position.x = R0.x - s * 0.1 * a
			if p.cls in ["swordmaster", "deathknight"]:
				# 양손 무기: 왼손이 따라감
				L.position = R.position + Vector3(-0.08, -0.04, 0.08)
	if p.blocking:
		# 방어 자세: 방패는 왼손을 앞으로, 무기는 가로로 세워 막음 (단검은 양손 교차)
		var off: String = Data.offhand_cat(p.equipment, p.wset)
		if off == "shield":
			L.position = Vector3(-0.14, -0.2, -0.5)
			L.rotation.y = 0.5
		else:
			R.position = Vector3(0.04, -0.16, -0.48)
			R.rotation = Vector3(0.25, 0, 1.3)
			if off == "dagger":
				L.position = Vector3(-0.04, -0.18, -0.48)
				L.rotation = Vector3(0.25, 0, -1.3)
			elif Skills.wcat(p) == "longsword":
				L.position = R.position + Vector3(-0.12, -0.02, 0.04)
	if p.parry > 0.0:
		R.position = Vector3(0.05, -0.15, -0.5)
		R.rotation = Vector3(0, 0, 1.3)
	if p.charge_t >= 0.0:
		# 프리스트 정화 충전: 책을 들어 올림
		var c := minf(1.0, p.charge_t / 1.2)
		L.position = L0 + Vector3(0.1, 0.08 + c * 0.05, -0.05)
	if p.cast > 0.0 and p.swing == null:
		R.position = R0 + Vector3(0, 0.08, -0.1)
