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
