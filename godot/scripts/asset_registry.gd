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
# 뼈대에 묶인(스킨) 메시를 꺼냄: 같은 뼈 이름(mixamorig_*)을 가진 다른 캐릭터의 뼈대에 붙여 쓰기 위함
static func extract_skinned(path: String, mesh_name: String) -> MeshInstance3D:
	var key := "skinned:" + path + ":" + mesh_name
	if not _cache.has(key):
		var ps = load_res(path)
		var found = null
		if ps is PackedScene:
			var inst: Node = ps.instantiate()
			var m = inst.find_child(mesh_name, true, false)
			# "bone:<뼈 이름>" = 그 뼈에 가장 많이 묶인 메시 (FBX 가져오기에서 메시 이름이 뒤섞이는 경우가 있어 뼈로 찾음)
			if mesh_name.begins_with("bone:"):
				m = _mesh_by_bone(inst, mesh_name.substr(5))
			if m is MeshInstance3D and m.skin != null:
				# 무기 전용 뼈(예: 칼자루 뼈)는 다른 캐릭터에 없으므로 [이름, 부모 이름, 기본 자세]를 함께 보관
				var bones := []
				var sk = m.get_parent()
				if sk is Skeleton3D:
					for i in sk.get_bone_count():
						var par: int = sk.get_bone_parent(i)
						bones.append([sk.get_bone_name(i), sk.get_bone_name(par) if par >= 0 else "", sk.get_bone_rest(i)])
				found = {"mesh": m.mesh, "skin": m.skin, "mat": m.get_active_material(0), "bones": bones}
			inst.free()
		_cache[key] = found
	var f = _cache[key]
	if f == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = f.mesh
	mi.skin = f.skin
	mi.set_meta("bones", f.bones)
	return mi


static func _mesh_by_bone(root: Node, bone: String) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_n := 0
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.skin == null or mi.mesh == null:
			continue
		var bind := -1
		for i in mi.skin.get_bind_count():
			if mi.skin.get_bind_name(i) == bone:
				bind = i
		if bind < 0:
			continue
		var n := 0
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			for i in bones.size():
				if bones[i] == bind and w[i] > 0.5:
					n += 1
		if n > best_n:
			best_n = n
			best = mi
	return best


# 대상 뼈대에 없는 뼈를 원래 부모 아래에 같은 기본 자세로 추가 (무기 뼈)
static func add_missing_bones(dst: Skeleton3D, bones: Array) -> void:
	for b in bones:
		if dst.find_bone(b[0]) >= 0:
			continue
		var par := dst.find_bone(b[1])
		if par < 0:
			continue
		var idx := dst.get_bone_count()
		dst.add_bone(b[0])
		dst.set_bone_parent(idx, par)
		dst.set_bone_rest(idx, b[2])
		dst.set_bone_pose(idx, b[2])


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
static func anim_library(dirs, target: Skeleton3D, model_key: String, wanted: Array = []) -> AnimationLibrary:
	# 폴더 여러 개도 가능 (앞 폴더의 같은 이름 동작이 우선). wanted가 있으면 그 이름의 동작만 (불러오는 시간 절약)
	var list: Array = dirs if dirs is Array else [dirs]
	var key := "animlib:%s:%s:%s" % [",".join(list), model_key, ",".join(wanted)]
	if _cache.has(key):
		return _cache[key]
	var lib := AnimationLibrary.new()
	for d in list:
		var src := _anim_sources(str(d))
		for an in src.clips:
			if lib.has_animation(an) or (wanted.size() and not (an in wanted)):
				continue
			lib.add_animation(an, _retarget(src.clips[an], src.ref, target))
	_cache[key] = lib
	return lib


# 폴더의 원본 동작들 (한 번만 불러와서 모든 캐릭터가 같이 씀)
# 동작 파일 속 뼈대의 "기본 자세"는 T자가 아니라 동작 첫 장면이라 기준으로 못 씀.
# → 동작을 받을 때 고른 캐릭터(source.json의 "rest", 기본 팔라딘)의 T자 자세를 기준으로 사용
static func _anim_sources(dir: String) -> Dictionary:
	var key := "animsrc:" + dir
	if _cache.has(key):
		return _cache[key]
	var out := {"clips": {}, "ref": null}
	var src_cfg := {}
	if FileAccess.file_exists(dir.path_join("source.json")):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("source.json")))
		if parsed is Dictionary:
			src_cfg = parsed
	var ref_ps = load_res(str(src_cfg.get("rest", "res://assets/mixamo/characters/paladin.fbx")))
	if ref_ps is PackedScene:
		var ref_node: Node = ref_ps.instantiate()
		var rs := ref_node.find_children("*", "Skeleton3D", true, false)
		if rs.size():
			# 기준 뼈대는 복사해 둠 (원본 노드는 바로 해제)
			var sk: Skeleton3D = rs[0]
			sk.get_parent().remove_child(sk)
			sk.owner = null
			out.ref = sk
		ref_node.free()
	var da := DirAccess.open(dir)
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
				if out.ref == null:
					var sk2: Skeleton3D = sks[0]
					sk2.get_parent().remove_child(sk2)
					sk2.owner = null
					out.ref = sk2
				for an in ap.get_animation_list():
					if an == "RESET" or an == "Take 001":
						continue
					out.clips[fn.get_basename().to_lower().replace(" ", "_")] = ap.get_animation(an)
					break
			inst.free()
	_cache[key] = out
	return out


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
			# 제자리 동작으로: 앞뒤·좌우 이동은 첫 장면 위치에 고정 (게임이 직접 움직임), 높이만 키 비율로
			var p0: Vector3 = a.track_get_key_value(t, 0) if a.track_get_key_count(t) else Vector3.ZERO
			for i in a.track_get_key_count(t):
				var v: Vector3 = a.track_get_key_value(t, i)
				a.track_set_key_value(t, i, Vector3(p0.x * hip_k, v.y * hip_k, p0.z * hip_k))
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
