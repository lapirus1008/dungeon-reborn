# 던전: 지도 파일(assets/maps/*.json) 또는 절차적 생성, 메시 구성, 충돌/시야/경로 탐색
class_name Dungeon
extends RefCounted

const T := 4.0 # 타일 크기 (미터)
const WALL_H := 4.0 # KayKit 던전 벽 높이(4m)와 맞춤

const EMPTY := 0
const ROOM := 1
const CORR := 2
const PILLAR := 3

var depth := 1
var W := 46
var H := 46
var grid := PackedByteArray()
var room_id := PackedInt32Array()
var rooms: Array = [] # Dictionary: id, x, z, w, h, cx, cz, boss
var torches: Array = [] # Dictionary: tx, tz, pos(Vector3), n(Vector3), light
var props: Array = []
var root: Node3D
var flame_mm: MultiMesh
var rng := RandomNumberGenerator.new() # 멀티플레이: 같은 시드면 모든 접속자에게 같은 던전
var seed_value := 0
var map_id := ""
# 지도 표식 (타일 좌표 Vector2i): spawns 시작 위치, shrines 성소, stones 부활석, exits 고정 탈출구, descent 아래층 계단
var marks := {"spawns": [], "shrines": [], "stones": [], "exits": [], "descent": []}


func _init(d: int = 1, seed_v: int = 0, map := "") -> void:
	depth = d
	seed_value = seed_v if seed_v != 0 else randi()
	rng.seed = seed_value
	map_id = map
	if map != "" and Data.MAPS.has(map):
		_load_map(Data.MAPS[map])
		return
	W = 46 if d == 1 else 50
	H = W
	grid.resize(W * H)
	grid.fill(EMPTY)
	room_id.resize(W * H)
	room_id.fill(-1)
	generate()


func idx(x: int, z: int) -> int:
	return z * W + x


func get_t(x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= W or z >= H:
		return EMPTY
	return grid[z * W + x]


func tile_solid(x: int, z: int) -> bool:
	var g := get_t(x, z)
	return g == EMPTY or g == PILLAR


func to_tile(v: float) -> int:
	return int(floor(v / T))


func is_solid(x: float, z: float) -> bool:
	return tile_solid(to_tile(x), to_tile(z))


func center(tx: int, tz: int) -> Vector3:
	return Vector3((tx + 0.5) * T, 0.0, (tz + 0.5) * T)


func room_at(x: float, z: float):
	var tx := to_tile(x)
	var tz := to_tile(z)
	if tx < 0 or tz < 0 or tx >= W or tz >= H:
		return null
	var id := room_id[idx(tx, tz)]
	return rooms[id] if id >= 0 else null


func generate() -> void:
	var target := 14 if depth == 1 else 16
	var attempts := 0
	while rooms.size() < target and attempts < 600:
		attempts += 1
		var big := rooms.is_empty()
		var w := rng.randi_range(8, 10) if big else rng.randi_range(4, 8)
		var h := rng.randi_range(8, 10) if big else rng.randi_range(4, 8)
		var x := rng.randi_range(2, W - w - 3)
		var z := rng.randi_range(2, H - h - 3)
		var ok := true
		for r in rooms:
			if x < r.x + r.w + 2 and x + w + 2 > r.x and z < r.z + r.h + 2 and z + h + 2 > r.z:
				ok = false
				break
		if not ok:
			continue
		var room := {"id": rooms.size(), "x": x, "z": z, "w": w, "h": h, "cx": x + w / 2.0, "cz": z + h / 2.0, "boss": big}
		rooms.append(room)
		for i in range(x, x + w):
			for j in range(z, z + h):
				grid[idx(i, j)] = ROOM
				room_id[idx(i, j)] = room.id

	# 프림 MST로 방 연결 + 추가 루프
	var n := rooms.size()
	var in_tree := {0: true}
	var edges := []
	while in_tree.size() < n:
		var best := []
		var bd := 1e9
		for a in in_tree:
			for b in n:
				if in_tree.has(b):
					continue
				var d := Vector2(rooms[a].cx - rooms[b].cx, rooms[a].cz - rooms[b].cz).length()
				if d < bd:
					bd = d
					best = [a, b]
		in_tree[best[1]] = true
		edges.append(best)
	for k in n / 3:
		var a := rng.randi_range(0, n - 1)
		var b := -1
		var bd := 1e9
		for j in n:
			if j == a:
				continue
			var d := Vector2(rooms[a].cx - rooms[j].cx, rooms[a].cz - rooms[j].cz).length()
			var exists := false
			for e in edges:
				if (e[0] == a and e[1] == j) or (e[0] == j and e[1] == a):
					exists = true
			if d < bd and not exists:
				bd = d
				b = j
		if b >= 0:
			edges.append([a, b])
	for e in edges:
		_carve(rooms[e[0]], rooms[e[1]])

	# 큰 방 기둥
	for r in rooms:
		if r.w >= 7 and r.h >= 7:
			for p in [[r.x + 2, r.z + 2], [r.x + r.w - 3, r.z + 2], [r.x + 2, r.z + r.h - 3], [r.x + r.w - 3, r.z + r.h - 3]]:
				grid[idx(p[0], p[1])] = PILLAR
				props.append({"type": "pillar", "pos": center(p[0], p[1])})

	# 횃불: 방 둘레 벽면
	for r in rooms:
		var count := 6 if r.boss else rng.randi_range(2, 3)
		var placed := 0
		var tries := 0
		while placed < count and tries < 40:
			tries += 1
			var side := rng.randi_range(0, 3)
			var tx := 0
			var tz := 0
			var nrm := Vector3.ZERO
			match side:
				0:
					tx = rng.randi_range(r.x, r.x + r.w - 1)
					tz = r.z
					nrm = Vector3(0, 0, -1)
				1:
					tx = rng.randi_range(r.x, r.x + r.w - 1)
					tz = r.z + r.h - 1
					nrm = Vector3(0, 0, 1)
				2:
					tx = r.x
					tz = rng.randi_range(r.z, r.z + r.h - 1)
					nrm = Vector3(-1, 0, 0)
				_:
					tx = r.x + r.w - 1
					tz = rng.randi_range(r.z, r.z + r.h - 1)
					nrm = Vector3(1, 0, 0)
			if get_t(tx + int(nrm.x), tz + int(nrm.z)) != EMPTY:
				continue
			var dup := false
			for t in torches:
				if t.tx == tx and t.tz == tz:
					dup = true
			if dup:
				continue
			var c := center(tx, tz)
			torches.append({"tx": tx, "tz": tz, "pos": Vector3(c.x + nrm.x * (T / 2.0 - 0.25), 3.2, c.z + nrm.z * (T / 2.0 - 0.25)), "n": nrm})
			placed += 1

	# 소품: 통, 뼈 더미
	for r in rooms:
		for i in rng.randi_range(1, 3):
			var tx := rng.randi_range(r.x, r.x + r.w - 1)
			var top := rng.randf() < 0.5
			var tz: int = r.z if top else r.z + r.h - 1
			if get_t(tx, tz) != ROOM:
				continue
			var c := center(tx, tz)
			c.x += rng.randf_range(-1.0, 1.0)
			c.z += -1.2 if top else 1.2
			props.append({"type": "barrel" if rng.randf() < 0.6 else "bones", "pos": c})


# ------------------------------------------------------------------ 지도 파일
func _load_map(def: Dictionary) -> void:
	var f := FileAccess.open(def.file, FileAccess.READ)
	var j = JSON.parse_string(f.get_as_text()) if f != null else null
	if not (j is Dictionary):
		push_error("지도를 읽을 수 없음: %s" % def.file)
		j = {"w": 8, "h": 8, "rows": ["########", "#......#", "#......#", "#......#", "#......#", "#......#", "#......#", "########"]}
	W = int(j.w)
	H = int(j.h)
	grid.resize(W * H)
	grid.fill(EMPTY)
	room_id.resize(W * H)
	room_id.fill(-1)
	var rows: Array = j.rows
	for z in H:
		var row: String = rows[z]
		for x in W:
			if x < row.length() and row[x] != "#":
				grid[idx(x, z)] = ROOM
	for k in marks:
		var seen := {}
		for v in j.get(k, []):
			var t := Vector2i(int(v[0]), int(v[1]))
			if not seen.has(t) and get_t(t.x, t.y) != EMPTY:
				seen[t] = true
				marks[k].append(t)
	# 지도 모양은 고정: 지도 이름으로 정한 난수 (멀티플레이 접속자 모두 같은 모양)
	var map_rng := RandomNumberGenerator.new()
	map_rng.seed = hash(map_id)
	if def.get("castle", false):
		_castle_walls(map_rng)
	if marks.spawns.is_empty():
		marks.spawns = _spread_points(10, [], map_rng)
	_segment_rooms(map_rng)
	for k in marks:
		marks[k] = marks[k].filter(func(t): return get_t(t.x, t.y) != EMPTY)
	if marks.spawns.size() < 4:
		marks.spawns.append_array(_spread_points(10 - marks.spawns.size(), marks.spawns, map_rng))
	# 보스 방: 시작 위치들에서 가장 먼 방
	var best = null
	var bd := -1.0
	for r in rooms:
		var md := 1e9
		for sp in marks.spawns:
			md = minf(md, Vector2(r.cx - sp.x, r.cz - sp.y).length())
		if r.tiles.size() >= 12 and md > bd:
			bd = md
			best = r
	if best != null:
		best.boss = true
	_decorate()


# 성 지도: 이미지에서 외곽만 나오므로 안쪽을 방/복도로 나눔 (재귀 분할 + 문)
func _castle_walls(r: RandomNumberGenerator) -> void:
	var stack := [Rect2i(1, 1, W - 2, H - 2)]
	var guard := 0
	while stack.size() and guard < 400:
		guard += 1
		var rc: Rect2i = stack.pop_back()
		var vertical := rc.size.x > rc.size.y if absi(rc.size.x - rc.size.y) > 3 else r.randf() < 0.5
		var span := rc.size.x if vertical else rc.size.y
		if span < 12:
			continue
		var cut := r.randi_range(5, span - 6)
		# 선 위의 바닥을 벽으로, 이어진 바닥 구간마다 문(2칸)
		var line := []
		var other := rc.size.y if vertical else rc.size.x
		for i in other:
			var x := rc.position.x + cut if vertical else rc.position.x + i
			var z := rc.position.y + i if vertical else rc.position.y + cut
			line.append(Vector2i(x, z))
		var run := []
		for k in line.size() + 1:
			var t = line[k] if k < line.size() else null
			if t != null and get_t(t.x, t.y) != EMPTY:
				run.append(t)
				continue
			if run.size() >= 3:
				var door := r.randi_range(0, run.size() - 2)
				for m in run.size():
					if m != door and m != door + 1:
						grid[idx(run[m].x, run[m].y)] = EMPTY
				if run.size() > 14:
					var d2 := (door + run.size() / 2) % (run.size() - 1)
					grid[idx(run[d2].x, run[d2].y)] = ROOM
					grid[idx(run[d2 + 1].x, run[d2 + 1].y)] = ROOM
			run = []
		if vertical:
			stack.append(Rect2i(rc.position.x, rc.position.y, cut, rc.size.y))
			stack.append(Rect2i(rc.position.x + cut + 1, rc.position.y, rc.size.x - cut - 1, rc.size.y))
		else:
			stack.append(Rect2i(rc.position.x, rc.position.y, rc.size.x, cut))
			stack.append(Rect2i(rc.position.x, rc.position.y + cut + 1, rc.size.x, rc.size.y - cut - 1))
	_keep_connected()


# 가장 큰 연결 영역만 남기고, 끊긴 영역은 가장 가까운 곳으로 벽을 뚫어 연결
func _keep_connected() -> void:
	for _pass in 30:
		var comp := PackedInt32Array()
		comp.resize(W * H)
		comp.fill(-1)
		var sizes := []
		for z in H:
			for x in W:
				if get_t(x, z) == EMPTY or comp[idx(x, z)] >= 0:
					continue
				var cid := sizes.size()
				var n := 0
				var st := [Vector2i(x, z)]
				comp[idx(x, z)] = cid
				while st.size():
					var c: Vector2i = st.pop_back()
					n += 1
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var q: Vector2i = c + d
						if get_t(q.x, q.y) != EMPTY and comp[idx(q.x, q.y)] < 0:
							comp[idx(q.x, q.y)] = cid
							st.append(q)
				sizes.append(n)
		if sizes.size() <= 1:
			return
		var main := sizes.find(sizes.max())
		# 작은 영역 하나를 골라 주 영역까지 직선으로 뚫음 (벽 1~3칸)
		var joined := false
		for z in H:
			for x in W:
				var c0 := comp[idx(x, z)]
				if c0 < 0 or c0 == main:
					continue
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					for ln in range(2, 5):
						var q = Vector2i(x, z) + d * ln
						if q.x <= 0 or q.y <= 0 or q.x >= W - 1 or q.y >= H - 1:
							break
						if comp[idx(q.x, q.y)] == main:
							for m in range(1, ln):
								var w = Vector2i(x, z) + d * m
								grid[idx(w.x, w.y)] = ROOM
							joined = true
							break
					if joined:
						break
				if joined:
					break
			if joined:
				break
		if not joined:
			# 연결할 수 없는 작은 영역은 메움
			for z in H:
				for x in W:
					if comp[idx(x, z)] >= 0 and comp[idx(x, z)] != main:
						grid[idx(x, z)] = EMPTY
			return


# 서로 멀리 떨어진 바닥 지점 n개 (시작 위치가 없는 지도용)
func _spread_points(n: int, avoid: Array, r: RandomNumberGenerator) -> Array:
	var floor_tiles := []
	for z in H:
		for x in W:
			if get_t(x, z) != EMPTY and _open_around(x, z):
				floor_tiles.append(Vector2i(x, z))
	var out := []
	if floor_tiles.is_empty():
		return out
	var first: Vector2i = floor_tiles[r.randi() % floor_tiles.size()]
	out.append(first)
	while out.size() < n:
		var best: Vector2i = floor_tiles[0]
		var bd := -1.0
		for t in floor_tiles:
			var md := 1e9
			for o in out + avoid:
				md = minf(md, Vector2(t - o).length())
			if md > bd:
				bd = md
				best = t
		out.append(best)
	return out


func _open_around(x: int, z: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if get_t(x + d.x, z + d.y) == EMPTY:
			return false
	return true


# 방 나누기: 8x8 구역마다 중심을 정하고, 바닥을 따라 가장 가까운 중심의 방으로 (측지 보로노이)
func _segment_rooms(_r: RandomNumberGenerator) -> void:
	const B := 8
	var seeds := []
	for bz in range(0, H, B):
		for bx in range(0, W, B):
			var cnt := 0
			var best := Vector2i(-1, -1)
			var bd := 1e9
			for z in range(bz, mini(bz + B, H)):
				for x in range(bx, mini(bx + B, W)):
					if get_t(x, z) == EMPTY:
						continue
					cnt += 1
					var d := Vector2(x - bx - B / 2.0, z - bz - B / 2.0).length() - (2.0 if _open_around(x, z) else 0.0)
					if d < bd:
						bd = d
						best = Vector2i(x, z)
			if cnt >= 6:
				seeds.append(best)
	var queue := []
	for i in seeds.size():
		var t: Vector2i = seeds[i]
		rooms.append({"id": i, "x": t.x, "z": t.y, "w": 1, "h": 1, "cx": t.x + 0.5, "cz": t.y + 0.5, "boss": false, "tiles": []})
		room_id[idx(t.x, t.y)] = i
		queue.append(t)
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = c + d
			if get_t(q.x, q.y) != EMPTY and room_id[idx(q.x, q.y)] < 0:
				room_id[idx(q.x, q.y)] = room_id[idx(c.x, c.y)]
				queue.append(q)
	for z in H:
		for x in W:
			var id := room_id[idx(x, z)]
			if id < 0:
				if get_t(x, z) != EMPTY:
					grid[idx(x, z)] = EMPTY # 어느 방과도 이어지지 않은 바닥
				continue
			rooms[id].tiles.append(Vector2i(x, z))
	for rm in rooms:
		var mn := Vector2i(W, H)
		var mx := Vector2i(-1, -1)
		for t in rm.tiles:
			mn = Vector2i(mini(mn.x, t.x), mini(mn.y, t.y))
			mx = Vector2i(maxi(mx.x, t.x), maxi(mx.y, t.y))
		rm.x = mn.x
		rm.z = mn.y
		rm.w = mx.x - mn.x + 1
		rm.h = mx.y - mn.y + 1


# 지도용 횃불과 소품
func _decorate() -> void:
	var cand := []
	for z in H:
		for x in W:
			if get_t(x, z) == EMPTY:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if get_t(x + d.x, z + d.y) == EMPTY:
					cand.append([x, z, d])
	var placed := {}
	for c in cand:
		if rng.randf() > 0.09:
			continue
		var key := Vector2i(c[0] / 3, c[1] / 3)
		if placed.has(key):
			continue
		placed[key] = true
		var d: Vector2i = c[2]
		var nrm := Vector3(d.x, 0, d.y)
		var ct := center(c[0], c[1])
		torches.append({"tx": c[0], "tz": c[1], "pos": Vector3(ct.x + nrm.x * (T / 2.0 - 0.25), 3.2, ct.z + nrm.z * (T / 2.0 - 0.25)), "n": nrm})
	for rm in rooms:
		for i in rng.randi_range(0, 2):
			var t: Vector2i = rm.tiles[rng.randi() % rm.tiles.size()]
			if _open_around(t.x, t.y):
				continue # 벽 옆에만
			var c := center(t.x, t.y) + Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
			props.append({"type": "barrel" if rng.randf() < 0.6 else "bones", "pos": c})


func _carve(a: Dictionary, b: Dictionary) -> void:
	var x := int(a.cx)
	var z := int(a.cz)
	var x2 := int(b.cx)
	var z2 := int(b.cz)
	var horiz_first := rng.randf() < 0.5
	if horiz_first:
		while x != x2:
			_carve_tile(x, z)
			x += signi(x2 - x)
		while z != z2:
			_carve_tile(x, z)
			z += signi(z2 - z)
	else:
		while z != z2:
			_carve_tile(x, z)
			z += signi(z2 - z)
		while x != x2:
			_carve_tile(x, z)
			x += signi(x2 - x)
	_carve_tile(x, z)


func _carve_tile(x: int, z: int) -> void:
	if get_t(x, z) == EMPTY:
		grid[idx(x, z)] = CORR


# ------------------------------------------------------------------ 메시
func _mat(tex: Array, uv_scale := Vector3.ONE, tint := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex[0]
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = tex[1]
	m.normal_scale = 1.0
	m.roughness = 0.92
	m.uv1_scale = uv_scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _multimesh(mesh: Mesh, xforms: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	return mi


func build(parent: Node3D, light_shadows: bool) -> void:
	root = Node3D.new()
	root.name = "Dungeon"
	parent.add_child(root)
	var deep := depth > 1
	var wall_tex := Textures.stone_wall(deep)
	var floor_tex := Textures.floor_tiles(deep)
	var wall_mat := _mat(wall_tex)
	var floor_mat := _mat(floor_tex)
	var ceil_mat := _mat(wall_tex, Vector3.ONE, Color(0.45, 0.42, 0.4))

	var floors := []
	var ceils := []
	var walls := []
	for z in H:
		for x in W:
			var g := get_t(x, z)
			if g != EMPTY:
				floors.append(Transform3D(Basis(), Vector3((x + 0.5) * T, 0, (z + 0.5) * T)))
				ceils.append(Transform3D(Basis(Vector3.RIGHT, PI), Vector3((x + 0.5) * T, WALL_H, (z + 0.5) * T)))
			else:
				var adj := false
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						if get_t(x + dx, z + dz) != EMPTY:
							adj = true
				if adj:
					walls.append(Transform3D(Basis(), Vector3((x + 0.5) * T, WALL_H / 2.0, (z + 0.5) * T)))

	# 타일 메시: assets/theme.json 의 "dungeon" 설정 또는 assets/dungeon/<이름> 파일이 있으면 교체 (docs/ART_PIPELINE.md)
	var th := AssetRegistry.theme_section("dungeon")
	var tm := func(key: String) -> Mesh:
		var v = th.get(key)
		if v is Array:
			v = v[0] if v.size() else ""
		return AssetRegistry.mesh_at(v) if v is String else null
	var plane: Mesh = tm.call("floor")
	if plane == null:
		plane = AssetRegistry.mesh("dungeon", "floor")
	if plane == null:
		plane = PlaneMesh.new()
		plane.size = Vector2(T, T)
		plane.material = floor_mat
	root.add_child(_multimesh(plane, floors))
	var cplane: Mesh = tm.call("ceiling")
	if cplane == null:
		cplane = AssetRegistry.mesh("dungeon", "ceiling")
	if cplane == null:
		cplane = PlaneMesh.new()
		cplane.size = Vector2(T, T)
		cplane.material = ceil_mat
	var ceil_mi := _multimesh(cplane, ceils)
	ceil_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 테마 천장은 바닥 타일을 뒤집어 쓰므로 어둡게
	if th.has("ceiling") and cplane.get_surface_count() > 0:
		var cm = cplane.surface_get_material(0)
		if cm is StandardMaterial3D:
			var dark: StandardMaterial3D = cm.duplicate()
			dark.albedo_color = Color(0.32, 0.3, 0.3)
			ceil_mi.material_override = dark
	root.add_child(ceil_mi)
	var box: Mesh = AssetRegistry.mesh("dungeon", "wall")
	if box == null:
		box = BoxMesh.new()
		box.size = Vector3(T, WALL_H, T)
		box.material = wall_mat
		# 벽 텍스처가 세로로 늘어나지 않도록 UV 비율 조정
		wall_mat.uv1_scale = Vector3(3.0, 2.0 * WALL_H / T, 1.0)
	root.add_child(_multimesh(box, walls))
	# 테마 벽면: 바닥과 벽이 맞닿는 모든 경계에 벽 조각을 세움 (뒤의 블록 벽은 틈새 메우기용)
	var faces: Array = th.get("wall_face", [])
	var themed := faces.size() > 0 and AssetRegistry.mesh_at(faces[0]) != null
	var banner_x := []
	if themed:
		var by_mesh := {}
		for z in H:
			for x in W:
				if get_t(x, z) == EMPTY:
					continue
				var c := center(x, z)
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if get_t(x + d.x, z + d.y) != EMPTY:
						continue
					var n := Vector3(d.x, 0, d.y)
					var rot := Basis(Vector3.UP, PI / 2 if d.x != 0 else 0.0)
					var path: String = faces[rng.randi() % faces.size()]
					if not by_mesh.has(path):
						by_mesh[path] = []
					by_mesh[path].append(Transform3D(rot, c + n * (T / 2.0 + 0.45)))
					# 방 안쪽 벽에 가끔 깃발
					if room_id[idx(x, z)] >= 0 and rng.randf() < 0.07:
						var face_rot := Basis(Vector3.UP, atan2(-n.x, -n.z))
						banner_x.append(Transform3D(face_rot, c + n * (T / 2.0 + 0.33)))
		for path in by_mesh:
			var fm := _multimesh(AssetRegistry.mesh_at(path), by_mesh[path])
			root.add_child(fm)
		var banner: Mesh = tm.call("banner")
		if banner != null and banner_x.size():
			root.add_child(_multimesh(banner, banner_x))

	# 기둥
	var pillar_x := []
	var barrel_x := []
	var bone_x := []
	var skull_x := []
	for p in props:
		match p.type:
			"pillar":
				pillar_x.append(Transform3D(Basis(), p.pos + Vector3(0, WALL_H / 2.0, 0)))
			"barrel":
				barrel_x.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p.pos + Vector3(0, 0.6, 0)))
			"bones":
				for k in 5:
					var bb := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI / 2)
					bone_x.append(Transform3D(bb, p.pos + Vector3(rng.randf_range(-0.5, 0.5), 0.05, rng.randf_range(-0.5, 0.5))))
				skull_x.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p.pos + Vector3(0, 0.18, 0)))
	if pillar_x.size() and tm.call("pillar") != null:
		var ps: Array = th.get("pillar_scale", [1.0, 1.0, 1.0])
		var sc := Vector3(ps[0], ps[1], ps[2])
		var px := []
		for t in pillar_x:
			px.append(Transform3D(Basis().scaled(sc), Vector3(t.origin.x, 0.0, t.origin.z)))
		root.add_child(_multimesh(tm.call("pillar"), px))
	elif pillar_x.size() and AssetRegistry.mesh("dungeon", "pillar") != null:
		root.add_child(_multimesh(AssetRegistry.mesh("dungeon", "pillar"), pillar_x))
	elif pillar_x.size():
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.1
		cyl.bottom_radius = 1.3
		cyl.height = WALL_H
		cyl.radial_segments = 12
		var pm := _mat(wall_tex)
		pm.uv1_scale = Vector3(4, 2, 1)
		cyl.material = pm
		root.add_child(_multimesh(cyl, pillar_x))
	if barrel_x.size() and tm.call("barrel") != null:
		var bs: float = th.get("barrel_scale", 1.0)
		var bx := []
		for t in barrel_x:
			bx.append(Transform3D(t.basis.scaled(Vector3.ONE * bs), Vector3(t.origin.x, 0.0, t.origin.z)))
		root.add_child(_multimesh(tm.call("barrel"), bx))
		# 일부 방 구석에 상자 더미
		var crates: Mesh = tm.call("crates")
		if crates != null:
			var cx := []
			for r in rooms:
				if rng.randf() < 0.35 and not r.boss:
					var corner := center(r.x, r.z) + Vector3(-0.6, 0, -0.6)
					if get_t(r.x, r.z) == ROOM:
						cx.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), corner))
			if cx.size():
				root.add_child(_multimesh(crates, cx))
	elif barrel_x.size() and AssetRegistry.mesh("dungeon", "barrel") != null:
		root.add_child(_multimesh(AssetRegistry.mesh("dungeon", "barrel"), barrel_x))
	elif barrel_x.size():
		var bm := CylinderMesh.new()
		bm.top_radius = 0.55
		bm.bottom_radius = 0.5
		bm.height = 1.2
		var bmat := StandardMaterial3D.new()
		bmat.albedo_texture = Textures.wood()
		bmat.roughness = 0.8
		bm.material = bmat
		root.add_child(_multimesh(bm, barrel_x))
	if bone_x.size():
		var bone_mat := StandardMaterial3D.new()
		bone_mat.albedo_color = Color(0.81, 0.78, 0.68)
		bone_mat.roughness = 0.7
		var stick := CylinderMesh.new()
		stick.top_radius = 0.05
		stick.bottom_radius = 0.05
		stick.height = 0.6
		stick.radial_segments = 6
		stick.material = bone_mat
		root.add_child(_multimesh(stick, bone_x))
		var skull := SphereMesh.new()
		skull.radius = 0.2
		skull.height = 0.36
		skull.material = bone_mat
		root.add_child(_multimesh(skull, skull_x))

	# 횃불: 받침 + 불꽃(발광) + 실제 점광원
	var sconce := BoxMesh.new()
	sconce.size = Vector3(0.15, 0.7, 0.15)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.23, 0.16, 0.1)
	sconce.material = smat
	var flame := CylinderMesh.new()
	flame.top_radius = 0.0
	flame.bottom_radius = 0.16
	flame.height = 0.45
	flame.radial_segments = 6
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var fcol := Color(1.0, 0.45, 0.2) if deep else Color(1.0, 0.7, 0.3)
	fmat.albedo_color = fcol
	fmat.emission_enabled = true
	fmat.emission = fcol
	fmat.emission_energy_multiplier = 4.0
	flame.material = fmat
	var sx := []
	var fx := []
	var torch_mesh: Mesh = tm.call("torch")
	for t in torches:
		var n: Vector3 = t.n
		if torch_mesh != null:
			# 벽걸이 횃불 모델: 벽면에 붙이고, 불꽃은 횃불 끝에
			var c := center(t.tx, t.tz)
			var mount := c + n * (T / 2.0 - 0.02) + Vector3(0, 2.15, 0)
			sx.append(Transform3D(Basis(Vector3.UP, atan2(-n.x, -n.z)), mount))
			t.pos = mount - n * 0.42 + Vector3(0, 0.72, 0) - Vector3(-n.x * 0.12, 0.1, -n.z * 0.12)
		else:
			var b := Basis(Vector3.RIGHT, n.z * 0.4) * Basis(Vector3.BACK, -n.x * 0.4)
			sx.append(Transform3D(b, t.pos + Vector3(0, -0.4, 0)))
		fx.append(Transform3D(Basis(), t.pos + Vector3(-n.x * 0.12, 0.1, -n.z * 0.12)))
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.55, 0.28) if deep else Color(1.0, 0.68, 0.38)
		l.omni_range = 12.0
		l.omni_attenuation = 1.2
		l.light_energy = 2.2
		l.shadow_enabled = light_shadows
		l.position = t.pos + Vector3(-n.x * 0.5, 0.2, -n.z * 0.5)
		l.distance_fade_enabled = true
		l.distance_fade_begin = 35.0
		l.distance_fade_length = 10.0
		root.add_child(l)
		t["light"] = l
	if torches.size():
		root.add_child(_multimesh(torch_mesh if torch_mesh != null else sconce, sx))
		var fmi := _multimesh(flame, fx)
		fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame_mm = fmi.multimesh
		root.add_child(fmi)


func animate_torches(time: float, cam_pos: Vector3) -> void:
	for i in torches.size():
		var t: Dictionary = torches[i]
		var fl := sin(time * 11.0 + i * 3.7) * 0.5 + sin(time * 5.3 + i) * 0.4
		var l: OmniLight3D = t.light
		if absf(t.pos.x - cam_pos.x) + absf(t.pos.z - cam_pos.z) < 40.0:
			l.light_energy = 2.2 + fl * 0.35
			if flame_mm:
				var n: Vector3 = t.n
				var b := Basis().scaled(Vector3(1.0 + fl * 0.1, 1.0 + fl * 0.25, 1.0 + fl * 0.1))
				flame_mm.set_instance_transform(i, Transform3D(b, t.pos + Vector3(-n.x * 0.12, 0.1, -n.z * 0.12)))


func dispose() -> void:
	if root and is_instance_valid(root):
		root.queue_free()


# ------------------------------------------------------------------ 충돌/시야/경로
# 원형 충돌체를 벽 밖으로 밀어낸 위치를 반환 (Vector3는 값 타입이므로 반환값 사용)
func resolve_circle(pos: Vector3, r: float) -> Vector3:
	var tx := to_tile(pos.x)
	var tz := to_tile(pos.z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var x := tx + dx
			var z := tz + dz
			var g := get_t(x, z)
			if g == PILLAR:
				var cx := (x + 0.5) * T
				var cz := (z + 0.5) * T
				var ddx := pos.x - cx
				var ddz := pos.z - cz
				var d := sqrt(ddx * ddx + ddz * ddz)
				var mn := 1.3 + r
				if d < mn and d > 1e-4:
					pos.x = cx + ddx / d * mn
					pos.z = cz + ddz / d * mn
				continue
			if g != EMPTY:
				continue
			var min_x := x * T
			var min_z := z * T
			var px := clampf(pos.x, min_x, min_x + T)
			var pz := clampf(pos.z, min_z, min_z + T)
			var ddx := pos.x - px
			var ddz := pos.z - pz
			var d2 := ddx * ddx + ddz * ddz
			if d2 < r * r:
				var d := sqrt(d2)
				if d > 1e-4:
					pos.x = px + ddx / d * r
					pos.z = pz + ddz / d * r
				else:
					var cx := min_x + T / 2.0
					var cz := min_z + T / 2.0
					if absf(pos.x - cx) > absf(pos.z - cz):
						pos.x = min_x + T + r if pos.x > cx else min_x - r
					else:
						pos.z = min_z + T + r if pos.z > cz else min_z - r
	return pos


func los(ax: float, az: float, bx: float, bz: float) -> bool:
	var dx := bx - ax
	var dz := bz - az
	var d := sqrt(dx * dx + dz * dz)
	var steps := int(ceil(d / 0.5))
	for i in range(1, steps):
		var t := float(i) / steps
		var x := ax + dx * t
		var z := az + dz * t
		var tx := to_tile(x)
		var tz := to_tile(z)
		var g := get_t(tx, tz)
		if g == EMPTY:
			return false
		if g == PILLAR:
			var cx := (tx + 0.5) * T
			var cz := (tz + 0.5) * T
			if Vector2(x - cx, z - cz).length() < 1.2:
				return false
	return true


func wide_los(a: Vector3, b: Vector3) -> bool:
	var dx := b.x - a.x
	var dz := b.z - a.z
	var d := maxf(0.001, sqrt(dx * dx + dz * dz))
	var px := -dz / d * 0.7
	var pz := dx / d * 0.7
	return los(a.x + px, a.z + pz, b.x + px, b.z + pz) and los(a.x - px, a.z - pz, b.x - px, b.z - pz)


# BFS 경로 탐색 -> 월드 좌표 웨이포인트 배열 (실패 시 빈 배열)
func path(a: Vector3, b: Vector3) -> Array:
	var sx := to_tile(a.x)
	var sz := to_tile(a.z)
	var ex := to_tile(b.x)
	var ez := to_tile(b.z)
	if tile_solid(ex, ez) or tile_solid(sx, sz):
		return []
	var prev := PackedInt32Array()
	prev.resize(W * H)
	prev.fill(-2)
	var q := PackedInt32Array()
	q.resize(W * H)
	var qh := 0
	var qt := 0
	var s := idx(sx, sz)
	var e := idx(ex, ez)
	prev[s] = -1
	q[qt] = s
	qt += 1
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while qh < qt:
		var c := q[qh]
		qh += 1
		if c == e:
			break
		var cx := c % W
		var cz := c / W
		for dv in dirs:
			var nx: int = cx + dv.x
			var nz: int = cz + dv.y
			if tile_solid(nx, nz):
				continue
			var ni := idx(nx, nz)
			if prev[ni] != -2:
				continue
			prev[ni] = c
			q[qt] = ni
			qt += 1
	if prev[e] == -2:
		return []
	var tiles := []
	var c2 := e
	while c2 != -1:
		tiles.append(c2)
		c2 = prev[c2]
	tiles.reverse()
	var pts := []
	for t in tiles:
		pts.append(center(t % W, t / W))
	pts[pts.size() - 1] = Vector3(b.x, 0, b.z)
	# 시야 기반 경로 단순화
	var out := []
	var anchor := Vector3(a.x, 0, a.z)
	var i := 0
	while i < pts.size():
		var j := pts.size() - 1
		while j > i and not wide_los(anchor, pts[j]):
			j -= 1
		out.append(pts[j])
		anchor = pts[j]
		i = j + 1
	return out


func random_point_in_room(room: Dictionary, margin: int = 1) -> Vector3:
	if room.has("tiles"):
		var tl: Array = room.tiles
		for k in 30:
			var t: Vector2i = tl[rng.randi() % tl.size()]
			if margin > 0 and not _open_around(t.x, t.y) and k < 25:
				continue
			var c := center(t.x, t.y)
			c.x += rng.randf_range(-1.0, 1.0)
			c.z += rng.randf_range(-1.0, 1.0)
			return c
		return center(int(room.cx), int(room.cz))
	for k in 30:
		var tx := rng.randi_range(room.x + margin, room.x + room.w - 1 - margin)
		var tz := rng.randi_range(room.z + margin, room.z + room.h - 1 - margin)
		if get_t(tx, tz) == ROOM:
			var c := center(tx, tz)
			c.x += rng.randf_range(-1.0, 1.0)
			c.z += rng.randf_range(-1.0, 1.0)
			return c
	return center(int(room.cx), int(room.cz))
