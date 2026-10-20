# 그래픽 교체 지점: res://assets/<분류>/<id>.(glb|gltf|tscn|scn|obj|res|tres) 가 있으면 그것을 쓰고,
# 없으면 코드로 만든 블록 모델을 사용한다. 자세한 규칙은 docs/ART_PIPELINE.md 참고.
class_name AssetRegistry
extends RefCounted

const ROOT := "res://assets/"
const SCENE_EXT := [".glb", ".gltf", ".tscn", ".scn"]
const MESH_EXT := [".obj", ".res", ".tres", ".glb", ".gltf"]

static var _cache := {}


static func _find(category: String, id: String, exts: Array) -> String:
	for ext in exts:
		var p = ROOT + category + "/" + id + ext
		if ResourceLoader.exists(p):
			return p
	return ""


static func has(category: String, id: String) -> bool:
	return _find(category, id, SCENE_EXT + MESH_EXT) != ""


# 씬(캐릭터, 무기, 소품, 뷰모델) 인스턴스. 없으면 null
static func scene(category: String, id: String) -> Node3D:
	var key := "scene:" + category + "/" + id
	if not _cache.has(key):
		var p := _find(category, id, SCENE_EXT)
		_cache[key] = load(p) if p != "" else null
	var ps = _cache[key]
	if ps is PackedScene:
		return ps.instantiate() as Node3D
	return null


# 단일 메시(던전 벽/바닥 등 MultiMesh용). glb면 첫 번째 MeshInstance3D의 메시를 사용. 없으면 null
static func mesh(category: String, id: String) -> Mesh:
	var key := "mesh:" + category + "/" + id
	if _cache.has(key):
		return _cache[key]
	var p := _find(category, id, MESH_EXT)
	var m: Mesh = null
	if p != "":
		var r = load(p)
		if r is Mesh:
			m = r
		elif r is PackedScene:
			var inst: Node = r.instantiate()
			var mis := inst.find_children("*", "MeshInstance3D", true, false)
			if mis.size():
				m = (mis[0] as MeshInstance3D).mesh
			inst.free()
	_cache[key] = m
	return m


# 선택적 설정 파일 (예: 애니메이션 이름 매핑) res://assets/<분류>/<id>.json
static func config(category: String, id: String) -> Dictionary:
	var p := ROOT + category + "/" + id + ".json"
	if FileAccess.file_exists(p):
		var d = JSON.parse_string(FileAccess.get_file_as_string(p))
		if d is Dictionary:
			return d
	return {}


# 테마 설정 (던전 타일, 상자, 1인칭 무기) res://assets/theme.json
static func theme() -> Dictionary:
	if not _cache.has("theme"):
		var d := {}
		if FileAccess.file_exists(ROOT + "theme.json"):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "theme.json"))
			if parsed is Dictionary:
				d = parsed
		_cache["theme"] = d
	return _cache["theme"]


static func theme_section(name: String) -> Dictionary:
	return theme().get(name, {})


# 경로의 리소스가 실제로 있을 때만 로드
static func load_res(path: String):
	if path == "" or not ResourceLoader.exists(path):
		return null
	var key := "res:" + path
	if not _cache.has(key):
		_cache[key] = load(path)
	return _cache[key]


# 메시 파일(obj) 또는 씬(glb)의 첫 메시
static func mesh_at(path: String) -> Mesh:
	var r = load_res(path)
	if r is Mesh:
		return r
	if r is PackedScene:
		var key := "first_mesh:" + path
		if not _cache.has(key):
			var inst: Node = r.instantiate()
			var mis := inst.find_children("*", "MeshInstance3D", true, false)
			_cache[key] = (mis[0] as MeshInstance3D).mesh if mis.size() else null
			inst.free()
		return _cache[key]
	return null


# 다른 모델 파일 안의 특정 메시를 떼어 와서 새 MeshInstance3D로 (무기/방패 등)
# 반환되는 노드의 원점은 손잡이(원래 손 슬롯 기준) 위치
static func extract_mesh(path: String, mesh_name: String) -> MeshInstance3D:
	var key := "extract:" + path + ":" + mesh_name
	if not _cache.has(key):
		var ps = load_res(path)
		var found = null
		if ps is PackedScene:
			var inst: Node = ps.instantiate()
			var m = inst.find_child(mesh_name, true, false)
			if m is MeshInstance3D:
				found = {"mesh": m.mesh, "xform": m.transform, "mat": m.get_active_material(0)}
			inst.free()
		_cache[key] = found
	var f = _cache[key]
	if f == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = f.mesh
	mi.transform = f.xform
	if f.mat != null:
		mi.material_override = f.mat
	return mi


# Mixamo 동작 묶음: 폴더 안의 동작 파일(fbx/glb, Without Skin)마다 첫 애니메이션을 꺼내 파일 이름으로 등록.
# 모든 Mixamo 캐릭터는 같은 뼈 이름(mixamorig_*)이지만, 캐릭터마다 뼈의 기본 방향이 조금씩 달라서
# 동작을 그대로 쓰면 몸이 비틀림 → 두 캐릭터 모두 T자 기본 자세라는 점을 이용해 "기본 자세에서 얼마나 돌았는지"를
# 전체 공간 기준으로 옮겨 다시 계산함 (리타깃). 엉덩이 위치는 키 비율로 맞추고, 다른 뼈의 위치 트랙은 제거.
static func anim_library(dir: String, target: Skeleton3D, model_key: String) -> AnimationLibrary:
	var key := "animlib:%s:%s" % [dir, model_key]
	if _cache.has(key):
		return _cache[key]
	var lib := AnimationLibrary.new()
	var da := DirAccess.open(dir)
	# 동작 파일 속 뼈대의 "기본 자세"는 T자가 아니라 동작 첫 장면이라 기준으로 못 씀.
	# → 동작을 받을 때 고른 캐릭터(source.json의 "rest", 기본 팔라딘)의 T자 자세를 기준으로 사용
	var ref_skel: Skeleton3D = null
	var ref_node: Node = null
	var src_cfg := {}
	if FileAccess.file_exists(dir.path_join("source.json")):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("source.json")))
		if parsed is Dictionary:
			src_cfg = parsed
	var ref_ps = load_res(str(src_cfg.get("rest", "res://assets/mixamo/characters/paladin.fbx")))
	if ref_ps is PackedScene:
		ref_node = ref_ps.instantiate()
		var rs := ref_node.find_children("*", "Skeleton3D", true, false)
		if rs.size():
			ref_skel = rs[0]
	if da != null:
		var seen := {}
		var files := da.get_files()
		files.sort()
		for f in files:
			var fn := f.trim_suffix(".import").trim_suffix(".remap")
			var ext := fn.get_extension().to_lower()
			if not (ext in ["fbx", "glb", "gltf"]) or seen.has(fn):
				continue
			seen[fn] = true
			var ps = load(dir.path_join(fn))
			if not (ps is PackedScene):
				continue
			var inst: Node = ps.instantiate()
			var aps := inst.find_children("*", "AnimationPlayer", true, false)
			var sks := inst.find_children("*", "Skeleton3D", true, false)
			if aps.size() and sks.size():
				var ap: AnimationPlayer = aps[0]
				var src: Skeleton3D = sks[0]
				for an in ap.get_animation_list():
					if an == "RESET" or an == "Take 001":
						continue
					var a := _retarget(ap.get_animation(an), ref_skel if ref_skel != null else src, target)
					lib.add_animation(fn.get_basename().to_lower().replace(" ", "_"), a)
					break
			inst.free()
	if ref_node != null:
		ref_node.free()
	_cache[key] = lib
	return lib


static func _retarget(orig: Animation, src: Skeleton3D, dst: Skeleton3D) -> Animation:
	var a: Animation = orig.duplicate(true)
	var sh := src.find_bone("mixamorig_Hips")
	var dh := dst.find_bone("mixamorig_Hips")
	var hip_k := 1.0
	if sh >= 0 and dh >= 0:
		hip_k = dst.get_bone_global_rest(dh).origin.y / maxf(0.01, src.get_bone_global_rest(sh).origin.y)
	for t in range(a.get_track_count() - 1, -1, -1):
		var np := a.track_get_path(t)
		var bone_name := str(np.get_concatenated_subnames())
		var tt := a.track_get_type(t)
		var sb := src.find_bone(bone_name)
		var db := dst.find_bone(bone_name)
		if db < 0 or sb < 0:
			a.remove_track(t) # 이 캐릭터에 없는 뼈
			continue
		if tt == Animation.TYPE_POSITION_3D:
			if bone_name != "mixamorig_Hips":
				a.remove_track(t)
				continue
			for i in a.track_get_key_count(t):
				a.track_set_key_value(t, i, a.track_get_key_value(t, i) * hip_k)
		elif tt == Animation.TYPE_ROTATION_3D:
			var s_rest := src.get_bone_rest(sb).basis.get_rotation_quaternion()
			var d_rest := dst.get_bone_rest(db).basis.get_rotation_quaternion()
			var sp := src.get_bone_parent(sb)
			var dp := dst.get_bone_parent(db)
			var s_par := src.get_bone_global_rest(sp).basis.get_rotation_quaternion() if sp >= 0 else Quaternion.IDENTITY
			var d_par := dst.get_bone_global_rest(dp).basis.get_rotation_quaternion() if dp >= 0 else Quaternion.IDENTITY
			var s_inv := s_rest.inverse()
			for i in a.track_get_key_count(t):
				var q: Quaternion = a.track_get_key_value(t, i)
				# 기본 자세 대비 회전(부모 기준) → 전체 공간 → 대상 캐릭터의 부모 기준으로
				var delta_g := s_par * (q * s_inv) * s_par.inverse()
				var nq := d_par.inverse() * delta_g * d_par * d_rest
				a.track_set_key_value(t, i, nq.normalized())
		elif tt == Animation.TYPE_SCALE_3D:
			a.remove_track(t)
	return a
