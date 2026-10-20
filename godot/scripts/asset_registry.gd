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
# 모든 Mixamo 캐릭터는 같은 뼈 이름(mixamorig_*)이라 한 묶음을 여러 캐릭터가 같이 씀.
# 엉덩이(Hips) 위치 트랙만 남기고 키 차이에 맞게 비율을 맞춤 (다른 뼈의 위치 트랙은 체형을 망가뜨려 제거)
static func anim_library(dir: String, target_hip_y: float) -> AnimationLibrary:
	var key := "animlib:%s:%.3f" % [dir, target_hip_y]
	if _cache.has(key):
		return _cache[key]
	var lib := AnimationLibrary.new()
	var da := DirAccess.open(dir)
	if da != null:
		var seen := {}
		for f in da.get_files():
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
				var sk: Skeleton3D = sks[0]
				var hip := sk.find_bone("mixamorig_Hips")
				var src_hip_y: float = sk.get_bone_rest(hip).origin.y if hip >= 0 else 1.0
				for an in ap.get_animation_list():
					if an == "RESET" or an == "Take 001":
						continue
					var a: Animation = ap.get_animation(an).duplicate(true)
					for t in range(a.get_track_count() - 1, -1, -1):
						if a.track_get_type(t) != Animation.TYPE_POSITION_3D:
							continue
						var path := str(a.track_get_path(t))
						if not path.ends_with("mixamorig_Hips"):
							a.remove_track(t)
							continue
						var k := target_hip_y / maxf(0.01, src_hip_y)
						for i in a.track_get_key_count(t):
							a.track_set_key_value(t, i, a.track_get_key_value(t, i) * k)
					lib.add_animation(fn.get_basename().to_lower().replace(" ", "_"), a)
					break
			inst.free()
	_cache[key] = lib
	return lib
