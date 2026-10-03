# 캐릭터 모델 + 애니메이션 인터페이스.
# 게임 로직은 animate(dt, state)만 호출하므로 블록 모델 <-> 실제 3D 모델(glb + AnimationPlayer)을 바꿔도 로직은 그대로다.
# state: {"move": 0~1, "windup": 0~1(-1 없음), "attack": 0~1(-1 없음), "aim": bool, "block": bool, "dead_t": 초(-1 생존), "cast": bool}
class_name CharacterRig
extends RefCounted

var node: Node3D
var meshes: Array = []
var procedural := true
var parts: Dictionary = {}
var anim: AnimationPlayer
var anim_map := {
	"idle": "idle", "walk": "walk", "attack": "attack", "block": "block", "cast": "cast", "death": "death", "hit": "hit",
}
var _current := ""
var _walk_phase := 0.0


# model_id: res://assets/characters/<model_id>.glb 가 있으면 사용, 없으면 builder로 블록 모델 생성
static func create(model_id: String, builder: Callable) -> CharacterRig:
	var rig := CharacterRig.new()
	var custom := AssetRegistry.scene("characters", model_id)
	if custom != null:
		rig.procedural = false
		rig.node = Node3D.new()
		rig.node.add_child(custom)
		var aps := custom.find_children("*", "AnimationPlayer", true, false)
		if aps.size():
			rig.anim = aps[0]
		rig.anim_map.merge(AssetRegistry.config("characters", model_id).get("animations", {}), true)
		for n in custom.find_children("*", "GeometryInstance3D", true, false):
			rig.meshes.append(n)
	else:
		rig.node = builder.call()
		rig.parts = rig.node.get_meta("parts", {})
		rig.meshes = rig.node.get_meta("meshes", [])
	return rig


func animate(dt: float, st: Dictionary) -> void:
	if procedural:
		_animate_procedural(dt, st)
	else:
		_animate_clips(st)


func _play(key: String) -> void:
	if anim == null:
		return
	var clip: String = anim_map.get(key, key)
	if clip == _current or not anim.has_animation(clip):
		return
	_current = clip
	anim.play(clip, 0.15)


func _animate_clips(st: Dictionary) -> void:
	if st.get("dead_t", -1.0) >= 0.0:
		_play("death")
	elif st.get("attack", -1.0) >= 0.0 or st.get("windup", -1.0) >= 0.0:
		_play("cast" if st.get("cast", false) else "attack")
	elif st.get("block", false):
		_play("block")
	elif st.get("move", 0.0) > 0.1:
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
