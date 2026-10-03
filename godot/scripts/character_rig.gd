# 캐릭터 모델 + 애니메이션 인터페이스.
# 게임 로직은 animate(dt, state)만 호출하므로 블록 모델 <-> 실제 3D 모델(glb + AnimationPlayer)을 바꿔도 로직은 그대로다.
# state: {"move": 0~1, "windup": 0~1(-1 없음), "attack": 0~1(-1 없음), "aim": bool, "block": bool,
#         "dead_t": 초(-1 생존), "cast": bool, "spin": bool}
#
# 모델 선택 순서:
#  1) res://assets/characters/<id>.json 에 "source"가 있으면 그 glb를 설정대로 사용 (보이는 장비, 무기 부착, 색, 애니메이션 이름)
#  2) res://assets/characters/<id>.glb 등이 있으면 그대로 사용
#  3) 둘 다 없으면 코드로 만든 블록 모델
class_name CharacterRig
extends RefCounted

const LOOP_KEYS := ["idle", "walk", "run", "block", "aim"]

var node: Node3D
var meshes: Array = []
var procedural := true
var parts: Dictionary = {}
var anim: AnimationPlayer
var anim_map := {
	"idle": "idle", "walk": "walk", "run": "run", "attack": "attack", "block": "block", "cast": "cast",
	"death": "death", "hit": "hit", "spin": "spin", "aim": "aim",
}
var anim_speed := 1.0
var _current := ""
var _walk_phase := 0.0
var _was_attacking := false
var _was_dead := false


static func create(model_id: String, builder: Callable) -> CharacterRig:
	var rig := CharacterRig.new()
	var cfg := AssetRegistry.config("characters", model_id)
	var custom: Node3D = null
	if cfg.has("source"):
		var ps = AssetRegistry.load_res(cfg.source)
		if ps is PackedScene:
			custom = ps.instantiate()
	if custom == null:
		custom = AssetRegistry.scene("characters", model_id)
	if custom != null:
		rig._setup_custom(custom, cfg)
	else:
		rig.node = builder.call()
		rig.parts = rig.node.get_meta("parts", {})
		rig.meshes = rig.node.get_meta("meshes", [])
	return rig


func _setup_custom(model: Node3D, cfg: Dictionary) -> void:
	procedural = false
	node = Node3D.new()
	node.add_child(model)
	# glTF 모델은 +Z가 앞이므로 게임 기준(-Z 앞)에 맞게 회전
	model.rotation.y = cfg.get("yaw", PI)
	model.scale = Vector3.ONE * float(cfg.get("scale", 1.0))
	# 보이는 장비만 남기기 (뼈에 붙은 장비/모자/망토)
	if cfg.has("show"):
		var show: Array = cfg.show
		for m in model.find_children("*", "MeshInstance3D", true, false):
			if m.get_parent() is BoneAttachment3D or m.name.ends_with("_Cape") or m.name.ends_with("_Hat") or m.name.ends_with("_Helmet") or m.name.ends_with("_Hood"):
				m.visible = m.name in show
	# 다른 모델의 무기를 손에 부착
	var skel: Skeleton3D = null
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.size():
		skel = sks[0]
	for a in cfg.get("attach", []):
		if skel == null:
			break
		var bone: String = "handslot.r" if a.get("slot", "r") == "r" else "handslot.l"
		var holder: BoneAttachment3D = null
		for b in skel.find_children("*", "BoneAttachment3D", false, false):
			if (b as BoneAttachment3D).bone_name == bone:
				holder = b
		if holder == null:
			holder = BoneAttachment3D.new()
			holder.bone_name = bone
			skel.add_child(holder)
		var mi := AssetRegistry.extract_mesh(a.from, a.mesh)
		if mi != null:
			mi.name = a.mesh
			holder.add_child(mi)
	# 색 입히기: "*"는 전체, 그 외는 메시 이름별 (텍스처 색에 곱해짐)
	var tint: Dictionary = cfg.get("tint", {})
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var c = tint.get(m.name, tint.get("*", null))
		if c != null:
			var base: Material = m.get_active_material(0)
			if base is StandardMaterial3D:
				var mat: StandardMaterial3D = base.duplicate()
				mat.albedo_color = Color(c)
				m.material_override = mat
		if m.visible:
			meshes.append(m)
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	if aps.size():
		anim = aps[0]
	anim_map.merge(cfg.get("animations", {}), true)
	anim_speed = float(cfg.get("anim_speed", 1.0))
	# 반복 재생할 동작 설정
	if anim:
		for k in LOOP_KEYS:
			var clip = anim_map.get(k)
			if clip is String and anim.has_animation(clip):
				anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_play("idle")


func set_active(v: bool) -> void:
	if anim:
		anim.active = v


func animate(dt: float, st: Dictionary) -> void:
	if procedural:
		_animate_procedural(dt, st)
	else:
		_animate_clips(st)


func _clip_for(key: String) -> String:
	var c = anim_map.get(key, key)
	if c is Array:
		return c.pick_random() if c.size() else ""
	return c


func _play(key: String, restart := false, speed := 1.0) -> void:
	if anim == null:
		return
	var clip := _clip_for(key)
	if clip == "" or not anim.has_animation(clip):
		return
	if clip == _current and not restart:
		return
	_current = clip
	anim.play(clip, 0.12, speed * anim_speed)
	if restart:
		anim.seek(0.0, true)


func _animate_clips(st: Dictionary) -> void:
	if st.get("dead_t", -1.0) >= 0.0:
		if not _was_dead:
			_was_dead = true
			_play("death", true)
		return
	var attacking: bool = st.get("attack", -1.0) >= 0.0 or st.get("windup", -1.0) >= 0.0
	if st.get("spin", false):
		_play("spin")
		_was_attacking = false
		return
	if attacking:
		if not _was_attacking:
			_play("cast" if st.get("cast", false) else "attack", true, 1.4)
		_was_attacking = true
		return
	_was_attacking = false
	var mv: float = st.get("move", 0.0)
	if st.get("block", false):
		_play("block")
	elif st.get("aim", false) and mv < 0.3:
		_play("aim")
	elif mv > 0.7:
		_play("run")
	elif mv > 0.05:
		_play("walk")
	else:
		_play("idle")


func _animate_procedural(dt: float, st: Dictionary) -> void:
	if parts.is_empty():
		return
	var p := parts
	var dead_t: float = st.get("dead_t", -1.0)
	if dead_t >= 0.0:
		p.rig.rotation.x = maxf(-PI / 2, -dead_t * 5.0)
		p.rig.position.y = minf(0.25, dead_t)
		return
	var mv: float = st.get("move", 0.0)
	_walk_phase += dt * 9.0 * mv
	var sw := sin(_walk_phase) * 0.7 * mv
	p.leg_l.rotation.x = sw
	p.leg_r.rotation.x = -sw
	p.arm_l.rotation.x = -sw * 0.6
	p.arm_r.rotation.x = sw * 0.6
	p.arm_r.rotation.z = 0.0
	var wk: float = st.get("windup", -1.0)
	var ak: float = st.get("attack", -1.0)
	if wk >= 0.0:
		p.arm_r.rotation.x = 2.6 * minf(1.0, wk + 0.3)
		p.arm_r.rotation.z = 0.3
	elif ak >= 0.0:
		p.arm_r.rotation.x = 2.6 - ak * 3.2
	if st.get("aim", false):
		p.arm_l.rotation.x = PI / 2
		p.arm_r.rotation.x = PI / 2
	if st.get("block", false):
		p.arm_l.rotation.x = 1.3
	if p.has("panther_legs"):
		for i in p.panther_legs.size():
			p.panther_legs[i].rotation.x = sin(_walk_phase * 1.6 + i * PI / 2) * 0.6 * mv
