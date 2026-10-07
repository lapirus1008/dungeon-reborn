# 던전: 지도 파일(assets/maps/*.json) 또는 절차적 생성, 메시 구성, 충돌/시야/경로 탐색
class_name Dungeon
extends RefCounted

const T := 4.0 # 타일 크기 (미터)
const WALL_H := 4.0 # KayKit 던전 벽 높이(4m)와 맞춤

const EMPTY := 0
const ROOM := 1
const CORR := 2
const PILLAR := 3
const TREE := 4 # 야외 나무 (지나갈 수 없음)
# 구역 (area): 실내 / 야외(숲·안뜰, 천장 없음) / 성당(높은 천장)
const A_IN := 0
const A_OUT := 1
const A_CATH := 2
const INDOOR_LAYER := 2
static var lite := false # 그래픽 낮음(휴대폰): 벽걸이 횃불 중 절반만 실제 광원 # 실내 바닥: 달빛(방향광)이 비추지 않는 렌더 레이어

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
var area := PackedByteArray()
var decor: Dictionary = {} # 지도 장식: 탑, 본성/성당 범위, 벽 높이
var has_outdoor := false
var wild := PackedByteArray() # 지도 가장자리와 이어진 바위/숲 (벽 대신 나무로 그림)
var static_blocks: Array = [] # 탑·의자 등 고정 원형 장애물 [[pos, radius]]
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
	area.resize(W * H)
	area.fill(A_IN)
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
	return g == EMPTY or g == PILLAR or g == TREE


func to_tile(v: float) -> int:
	return int(floor(v / T))


func is_solid(x: float, z: float) -> bool:
	return tile_solid(to_tile(x), to_tile(z))


func center(tx: int, tz: int) -> Vector3:
	var x := (tx + 0.5) * T
	var z := (tz + 0.5) * T
	return Vector3(x, ground_y(x, z), z)


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
	area.resize(W * H)
	area.fill(A_IN)
	room_id.resize(W * H)
	room_id.fill(-1)
	decor = j.get("decor", {})
	var rows: Array = j.rows
	# 타일 문자: # 벽 · . 실내 · , 야외 · T 나무 · r 야외 기둥 · c 성당 · P 성당 기둥 · p 실내 기둥
	const KIND := {".": [ROOM, A_IN], ",": [ROOM, A_OUT], "T": [TREE, A_OUT], "r": [PILLAR, A_OUT], "c": [ROOM, A_CATH], "P": [PILLAR, A_CATH], "p": [PILLAR, A_IN]}
	for z in H:
		var row: String = rows[z]
		for x in W:
			if x < row.length() and row[x] != "#":
				var k: Array = KIND.get(row[x], [ROOM, A_IN])
				grid[idx(x, z)] = k[0]
				area[idx(x, z)] = k[1]
				if k[1] == A_OUT:
					has_outdoor = true
	_mark_wild()
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
	_build_heights()
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


# 지도 가장자리에서 벽 타일을 따라 이어진 곳 = 바깥 숲/바위 (성벽이 아님)
func _mark_wild() -> void:
	wild.resize(W * H)
	wild.fill(0)
	if not has_outdoor:
		return
	var q := []
	for z in H:
		for x in W:
			if (x == 0 or z == 0 or x == W - 1 or z == H - 1) and get_t(x, z) == EMPTY:
				wild[idx(x, z)] = 1
				q.append(Vector2i(x, z))
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= W or n.y >= H:
				continue
			if get_t(n.x, n.y) == EMPTY and wild[idx(n.x, n.y)] == 0:
				wild[idx(n.x, n.y)] = 1
				q.append(n)


# 바닥 높이: 숲은 완만한 언덕 (타일 모서리 높이를 이중 선형 보간), 건물·성 안뜰·실내는 0
var hv := PackedFloat32Array() # (W+1) x (H+1) 모서리 높이
const HILL_AMP := 3.5


func ground_y(x: float, z: float) -> float:
	if hv.is_empty():
		return 0.0
	var fx := clampf(x / T, 0.0, W - 0.001)
	var fz := clampf(z / T, 0.0, H - 0.001)
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var v := fz - j
	var a := hv[j * (W + 1) + i]
	var b := hv[j * (W + 1) + i + 1]
	var c := hv[(j + 1) * (W + 1) + i]
	var d := hv[(j + 1) * (W + 1) + i + 1]
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


func _build_heights() -> void:
	if not has_outdoor:
		return
	var CW := W + 1
	var dist := PackedInt32Array()
	dist.resize(CW * (H + 1))
	dist.fill(-1)
	var q := []
	var cu: Array = decor.get("curtain", [])
	for j in H + 1:
		for i in CW:
			var flat := false
			for t in [Vector2i(i - 1, j - 1), Vector2i(i, j - 1), Vector2i(i - 1, j), Vector2i(i, j)]:
				var g := get_t(t.x, t.y)
				if _in_rect(cu, t.x, t.y):
					flat = true
				elif g == EMPTY:
					if not is_wild(t.x, t.y):
						flat = true # 성벽·건물 벽 옆은 평평하게
				elif area_at(t.x, t.y) != A_OUT:
					flat = true
			if flat:
				dist[j * CW + i] = 0
				q.append(Vector2i(i, j))
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		var dc := dist[c.y * CW + c.x]
		for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + dv
			if n.x < 0 or n.y < 0 or n.x >= CW or n.y > H or dist[n.y * CW + n.x] >= 0:
				continue
			dist[n.y * CW + n.x] = dc + 1
			q.append(n)
	var noise := FastNoiseLite.new()
	noise.seed = hash(map_id)
	noise.frequency = 0.07
	noise.fractal_octaves = 3
	hv.resize(CW * (H + 1))
	for j in H + 1:
		for i in CW:
			var dd := dist[j * CW + i]
			var k := 1.0 if dd < 0 else clampf(dd / 3.0, 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k) # 부드럽게
			hv[j * CW + i] = (noise.get_noise_2d(i, j) * 0.5 + 0.35) * 2.0 * HILL_AMP * k


# 실내 천장 높이 (성당은 높음)
func ceiling_y(x: float, z: float) -> float:
	if area_at(to_tile(x), to_tile(z)) == A_CATH:
		return float(decor.get("wall_h", {}).get("cathedral", WALL_H))
	return WALL_H


func is_wild(x: int, z: int) -> bool:
	if x < 0 or z < 0 or x >= W or z >= H:
		return true
	return wild.size() > 0 and wild[idx(x, z)] == 1


func area_at(x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= W or z >= H:
		return A_IN
	return area[idx(x, z)]


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


# 성 외곽 횃불: 건물 바깥 벽면에 4칸(16m)마다, 그리고 모든 출입문 양옆 (난수 없이 지도에서 정해짐)
func _exterior_torches() -> void:
	var have := {}
	for z in H:
		for x in W:
			if get_t(x, z) != ROOM or area_at(x, z) != A_OUT:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var wx: int = x + d.x
				var wz: int = z + d.y
				# 문 양옆: 이웃이 실내 바닥(출입구)이면, 출입구 옆 칸의 같은 벽면에 하나씩
				if area_at(wx, wz) != A_OUT and get_t(wx, wz) in [ROOM, CORR]:
					var side := Vector2i(d.y, d.x)
					for s in [side, -side]:
						var tx: int = x + s.x
						var tz: int = z + s.y
						if get_t(tx, tz) == ROOM and area_at(tx, tz) == A_OUT and get_t(tx + d.x, tz + d.y) == EMPTY:
							_add_wall_torch(tx, tz, d, Vector3(-s.x, 0, -s.y) * (T * 0.5 - 0.7), have)
					continue
				if get_t(wx, wz) != EMPTY or is_wild(wx, wz):
					continue
				if (x + z) % 4 == 0:
					_add_wall_torch(x, z, d, Vector3.ZERO, have)


func _add_wall_torch(x: int, z: int, d: Vector2i, off: Vector3, have: Dictionary) -> void:
	var key := Vector3i(x, z, d.x * 3 + d.y)
	if have.has(key):
		return
	have[key] = true
	var nrm := Vector3(d.x, 0, d.y)
	var ct := center(x, z) + off
	torches.append({"tx": x, "tz": z, "off": off, "pos": Vector3(ct.x + nrm.x * (T / 2.0 - 0.25), 3.2, ct.z + nrm.z * (T / 2.0 - 0.25)), "n": nrm})


# 지도용 횃불과 소품
func _decorate() -> void:
	var cand := []
	for z in H:
		for x in W:
			if get_t(x, z) == EMPTY:
				continue
			if get_t(x, z) != ROOM:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if get_t(x + d.x, z + d.y) == EMPTY and not is_wild(x + d.x, z + d.y):
					cand.append([x, z, d])
	var placed := {}
	for c in cand:
		# 실내는 횃불을 드물게 (어둡게 조심히 다니도록), 야외 벽면은 아래에서 일정 간격으로
		var outside: bool = has_outdoor and area_at(c[0], c[1]) == A_OUT
		var roll := rng.randf()
		if outside or roll > (0.05 if has_outdoor else 0.09):
			continue
		var key := Vector2i(c[0] / 3, c[1] / 3)
		if placed.has(key):
			continue
		placed[key] = true
		var d: Vector2i = c[2]
		var nrm := Vector3(d.x, 0, d.y)
		var ct := center(c[0], c[1])
		torches.append({"tx": c[0], "tz": c[1], "pos": Vector3(ct.x + nrm.x * (T / 2.0 - 0.25), 3.2, ct.z + nrm.z * (T / 2.0 - 0.25)), "n": nrm})
	if has_outdoor:
		_exterior_torches()
	for rm in rooms:
		for i in rng.randi_range(0, 2):
			var t: Vector2i = rm.tiles[rng.randi() % rm.tiles.size()]
			if _open_around(t.x, t.y):
				continue # 벽 옆에만
			var c := center(t.x, t.y) + Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
			if area[idx(t.x, t.y)] == A_OUT:
				props.append({"type": "rock" if rng.randf() < 0.6 else "log", "pos": c})
			elif area[idx(t.x, t.y)] == A_IN:
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
	m.normal_enabled = tex[1] != null
	m.normal_texture = tex[1]
	if tex.size() > 2 and tex[2] != null:
		m.roughness_texture = tex[2]
	m.normal_scale = 1.35
	m.roughness = 0.92
	m.uv1_scale = uv_scale
	# 요철: 높이맵 시차(폴리곤 추가 없이 벽돌·돌 틈이 움푹 들어가 보임)
	if Textures.relief and tex.size() > 3 and tex[3] != null:
		m.heightmap_enabled = true
		m.heightmap_texture = tex[3]
		m.heightmap_scale = 2.2
		m.heightmap_deep_parallax = true
		m.heightmap_min_layers = 4
		m.heightmap_max_layers = 12
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


# 사진 재질(assets/textures/<자리>/)이 있으면 그 재질, 없으면 fallback
func _pbr_or(slot: String, fallback: StandardMaterial3D, uv := Vector3.ONE, tint := Color.WHITE) -> StandardMaterial3D:
	var t := Textures.pbr(slot)
	if t.is_empty():
		return fallback
	return _mat(t, uv, tint)


# 벽 상자(BoxMesh는 3x2 아틀라스 UV) 위 사진 벽돌이 실제 크기로 보이도록 (약 2.5m에 한 번)
func _wall_uv(h: float) -> Vector3:
	if Textures.pbr("wall").is_empty():
		return Vector3(3.0, 2.0 * h / T, 1.0)
	return Vector3(3.0 * T / 2.5, 2.0 * h / 2.5, 1.0)


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
	# assets/textures/<이름>/ 에 사진 기반 재질이 있으면 교체 (wall, floor, grass, gravel, marble, roof)
	var wall_tex := Textures.pick("wall", Textures.stone_wall(deep))
	var floor_tex := Textures.pick("floor", Textures.floor_tiles(deep))
	var wall_mat := _mat(wall_tex)
	var floor_mat := _mat(floor_tex, Vector3.ONE * (2.0 if Textures.pbr("floor").size() else 1.0))
	var ceil_mat := _pbr_or("ceiling", _mat(wall_tex, Vector3.ONE, Color(0.45, 0.42, 0.4)), Vector3(1.5, 1.5, 1), Color(0.6, 0.55, 0.5))

	var floors := []
	var out_floors := [] # 숲 (풀)
	var yard_floors := [] # 성 안뜰 (자갈)
	var cath_floors := []
	var ceils := []
	var cath_ceils := []
	var walls := []
	var walls_by_h := {} # 4m가 아닌 벽: 높이 -> 위치
	var merlons := []
	var tree_x := [] # [위치, 크기, 종류]
	var bush_x := []
	var curtain: Array = decor.get("curtain", [])
	var cath_h := float(decor.get("wall_h", {}).get("cathedral", WALL_H))
	for z in H:
		for x in W:
			var g := get_t(x, z)
			var c := center(x, z)
			if g != EMPTY:
				var a := area_at(x, z)
				var fxf := Transform3D(Basis(), Vector3(c.x, 0, c.z))
				if a == A_OUT:
					if _in_rect(curtain, x, z):
						yard_floors.append(fxf)
					else:
						out_floors.append(fxf)
					if g == TREE:
						var tp := Vector3(c.x + rng.randf_range(-0.3, 0.3), 0, c.z + rng.randf_range(-0.3, 0.3))
						tp.y = ground_y(tp.x, tp.z) - 0.15
						tree_x.append([tp, rng.randf_range(1.0, 1.45), rng.randi() % 3])
					elif g == ROOM and rng.randf() < 0.35 and not _in_rect(curtain, x, z):
						var bp := Vector3(c.x + rng.randf_range(-1.6, 1.6), 0, c.z + rng.randf_range(-1.6, 1.6))
						bp.y = ground_y(bp.x, bp.z) + 0.15
						bush_x.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.6, 1.2)), bp))
				elif a == A_CATH:
					cath_floors.append(fxf)
					cath_ceils.append(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(c.x, cath_h, c.z)))
				else:
					floors.append(fxf)
					ceils.append(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(c.x, WALL_H, c.z)))
			else:
				var adj := false
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						if get_t(x + dx, z + dz) != EMPTY:
							adj = true
				if is_wild(x, z):
					# 바깥 숲 가장자리: 벽 대신 빽빽한 나무 (길에서 보이는 곳만)
					var near2 := adj
					if not near2:
						for dz in range(-2, 3):
							for dx in range(-2, 3):
								if get_t(x + dx, z + dz) != EMPTY:
									near2 = true
					if near2:
						for k in 3:
							var ep := Vector3(c.x + rng.randf_range(-1.7, 1.7), 0, c.z + rng.randf_range(-1.7, 1.7))
							ep.y = ground_y(ep.x, ep.z) - 0.15
							tree_x.append([ep, rng.randf_range(1.1, 1.8), rng.randi() % 3])
					continue
				if adj:
					var h := _wall_h(x, z)
					if is_equal_approx(h, WALL_H):
						walls.append(Transform3D(Basis(), Vector3(c.x, WALL_H / 2.0, c.z)))
					else:
						if not walls_by_h.has(h):
							walls_by_h[h] = []
						walls_by_h[h].append(Transform3D(Basis(), Vector3(c.x, h / 2.0, c.z)))
						# 성벽/본성 꼭대기 톱니 (총안)
						if h >= 12.0:
							for o in [Vector3(-1.0, 0, -1.0), Vector3(1.0, 0, 1.0), Vector3(-1.0, 0, 1.0), Vector3(1.0, 0, -1.0)]:
								merlons.append(Transform3D(Basis(), Vector3(c.x, h + 0.6, c.z) + o))

	# 타일 메시: assets/theme.json 의 "dungeon" 설정 또는 assets/dungeon/<이름> 파일이 있으면 교체 (docs/ART_PIPELINE.md)
	var th := AssetRegistry.theme_section("dungeon")
	var tm := func(key: String) -> Mesh:
		var v = th.get(key)
		if v is Array:
			v = v[0] if v.size() else ""
		return AssetRegistry.mesh_at(v) if v is String else null
	var plane: Mesh = tm.call("floor") if Textures.pbr("floor").is_empty() else null
	if plane == null and Textures.pbr("floor").is_empty():
		plane = AssetRegistry.mesh("dungeon", "floor")
	if plane == null:
		plane = PlaneMesh.new()
		plane.size = Vector2(T, T)
		plane.material = floor_mat
	if floors.size():
		var fmi := _multimesh(plane, floors)
		fmi.layers = INDOOR_LAYER if has_outdoor else 1
		root.add_child(fmi)
	# 야외/성당 바닥
	if out_floors.size() and not hv.is_empty():
		_build_terrain(out_floors)
		out_floors = []
	for pair in [[out_floors, "grass", 2.0], [yard_floors, "gravel", 2.0], [cath_floors, "marble", 1.0]]:
		if pair[0].size():
			var pm := PlaneMesh.new()
			pm.size = Vector2(T, T)
			var gm := _mat(Textures.pick(pair[1], Textures.ground(pair[1])), Vector3(pair[2], pair[2], 1.0))
			if pair[1] == "marble":
				gm.roughness = 0.35
			pm.material = gm
			var omi := _multimesh(pm, pair[0])
			if pair[1] == "marble":
				omi.layers = INDOOR_LAYER # 성당 안: 달빛을 받지 않음
			root.add_child(omi)
	var has_pbr_ceil := Textures.pbr("ceiling").size() > 0
	var cplane: Mesh = tm.call("ceiling") if not has_pbr_ceil else null
	if cplane == null and not has_pbr_ceil:
		cplane = AssetRegistry.mesh("dungeon", "ceiling")
	if cplane == null:
		cplane = PlaneMesh.new()
		cplane.size = Vector2(T, T)
		cplane.material = ceil_mat
	var ceil_mi := _multimesh(cplane, ceils)
	# 야외가 있는 지도: 달빛이 실내로 새지 않도록 천장이 그림자를 드리움
	ceil_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED if has_outdoor else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 테마 천장은 바닥 타일을 뒤집어 쓰므로 어둡게
	if th.has("ceiling") and not has_pbr_ceil and cplane.get_surface_count() > 0:
		var cm = cplane.surface_get_material(0)
		if cm is StandardMaterial3D:
			var dark: StandardMaterial3D = cm.duplicate()
			dark.albedo_color = Color(0.32, 0.3, 0.3)
			ceil_mi.material_override = dark
	if ceils.size():
		root.add_child(ceil_mi)
	if cath_ceils.size():
		var cc := PlaneMesh.new()
		cc.size = Vector2(T, T)
		cc.material = _pbr_or("ceiling", _mat(Textures.stone_wall(false), Vector3(1, 1, 1), Color(0.5, 0.46, 0.42)), Vector3(1.5, 1.5, 1), Color(0.55, 0.5, 0.45))
		var cci := _multimesh(cc, cath_ceils)
		cci.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		root.add_child(cci)
	var box: Mesh = AssetRegistry.mesh("dungeon", "wall")
	if box == null:
		box = BoxMesh.new()
		box.size = Vector3(T, WALL_H, T)
		box.material = wall_mat
		# 벽 텍스처가 세로로 늘어나지 않도록 UV 비율 조정
		wall_mat.uv1_scale = _wall_uv(WALL_H)
	if walls.size():
		root.add_child(_multimesh(box, walls))
	# 높은 벽 (성벽 12m, 본성 16m, 성당 10m, 작은 건물 바깥 7m)
	for h in walls_by_h:
		var tb := BoxMesh.new()
		tb.size = Vector3(T, h, T)
		var tmat := _mat(wall_tex, _wall_uv(h))
		tb.material = tmat
		root.add_child(_multimesh(tb, walls_by_h[h]))
	if merlons.size():
		var mb := BoxMesh.new()
		mb.size = Vector3(1.2, 1.2, 1.2)
		mb.material = _mat(wall_tex, Vector3(0.5, 0.5, 1.0))
		root.add_child(_multimesh(mb, merlons))
	if has_outdoor:
		_build_outdoor(tree_x, bush_x, wall_tex)
	# 테마 벽면: 바닥과 벽이 맞닿는 모든 경계에 벽 조각을 세움 (뒤의 블록 벽은 틈새 메우기용)
	var faces: Array = th.get("wall_face", [])
	# 사진 기반 벽 재질이 있으면 KayKit 벽 조각 대신 그 재질의 벽을 그대로 보여 줌
	var themed := faces.size() > 0 and AssetRegistry.mesh_at(faces[0]) != null and Textures.pbr("wall").is_empty()
	var banner_x := []
	if themed:
		var by_mesh := {}
		for z in H:
			for x in W:
				if get_t(x, z) == EMPTY or area_at(x, z) == A_OUT:
					continue
				var c := center(x, z)
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if get_t(x + d.x, z + d.y) != EMPTY or is_wild(x + d.x, z + d.y):
						continue
					var n := Vector3(d.x, 0, d.y)
					var rot := Basis(Vector3.UP, PI / 2 if d.x != 0 else 0.0)
					var path: String = faces[rng.randi() % faces.size()]
					if not by_mesh.has(path):
						by_mesh[path] = []
					by_mesh[path].append(Transform3D(rot, c + n * (T / 2.0 + 0.45)))
					if area_at(x, z) == A_CATH:
						# 성당: 높은 벽을 위로 한 단 더
						by_mesh[path].append(Transform3D(rot, c + n * (T / 2.0 + 0.45) + Vector3(0, WALL_H, 0)))
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
	var rock_x := []
	var log_x := []
	for p in props:
		match p.type:
			"pillar":
				pillar_x.append(Transform3D(Basis(), p.pos + Vector3(0, WALL_H / 2.0, 0)))
			"barrel":
				barrel_x.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p.pos + Vector3(0, 0.6, 0)))
			"rock":
				rock_x.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(0.6, 1.3), rng.randf_range(0.4, 0.8), rng.randf_range(0.6, 1.3))), p.pos + Vector3(0, 0.15, 0)))
			"log":
				log_x.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI / 2), p.pos + Vector3(0, 0.3, 0)))
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
			px.append(Transform3D(Basis().scaled(sc), Vector3(t.origin.x, t.origin.y - WALL_H / 2.0, t.origin.z)))
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
	if rock_x.size():
		var rk := SphereMesh.new()
		rk.radius = 0.7
		rk.height = 1.1
		rk.radial_segments = 7
		rk.rings = 4
		rk.material = _pbr_or("rock", _mat(wall_tex, Vector3(0.6, 0.6, 1), Color(0.75, 0.75, 0.72)), Vector3(2, 1, 1))
		root.add_child(_multimesh(rk, rock_x))
	if log_x.size():
		var lg := CylinderMesh.new()
		lg.top_radius = 0.3
		lg.bottom_radius = 0.34
		lg.height = 2.6
		lg.radial_segments = 8
		var lm0 := StandardMaterial3D.new()
		lm0.albedo_texture = Textures.wood()
		lm0.albedo_color = Color(0.7, 0.6, 0.5)
		var lm := _pbr_or("bark", lm0, Vector3(2, 1, 1))
		lg.material = lm
		root.add_child(_multimesh(lg, log_x))
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
		skull.radial_segments = 10
		skull.rings = 6
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
			var c: Vector3 = center(t.tx, t.tz) + t.get("off", Vector3.ZERO)
			var mount := c + n * (T / 2.0 - 0.02) + Vector3(0, 2.15, 0)
			sx.append(Transform3D(Basis(Vector3.UP, atan2(-n.x, -n.z)), mount))
			t.pos = mount - n * 0.42 + Vector3(0, 0.72, 0) - Vector3(-n.x * 0.12, 0.1, -n.z * 0.12)
		else:
			var b := Basis(Vector3.RIGHT, n.z * 0.4) * Basis(Vector3.BACK, -n.x * 0.4)
			sx.append(Transform3D(b, t.pos + Vector3(0, -0.4, 0)))
		fx.append(Transform3D(Basis(), t.pos + Vector3(-n.x * 0.12, 0.1, -n.z * 0.12)))
		if lite and torches.find(t) % 2 == 1:
			t["light"] = null
			continue
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
	_chunkify()
	_build_doors()


# 성능: 지도 전체를 한 덩어리로 그리면 화면 밖·먼 곳까지 매 프레임 그리게 됨.
# 32m 구역마다 나눠서 화면 밖 구역은 건너뛰고(절두체 컬링), 멀리 있는 구역은 그리지 않음(안개 너머)
const CHUNK := 32.0
const VIEW_RANGE := 85.0


func _chunkify() -> void:
	for mi in root.get_children():
		if not (mi is MultiMeshInstance3D):
			continue
		var mm: MultiMesh = mi.multimesh
		if mm == null or mm == flame_mm or mm.instance_count < 24:
			continue
		var groups := {}
		for i in mm.instance_count:
			var xf := mm.get_instance_transform(i)
			var key := Vector2i(floori(xf.origin.x / CHUNK), floori(xf.origin.z / CHUNK))
			if not groups.has(key):
				groups[key] = []
			groups[key].append(xf)
		if groups.size() <= 1:
			continue
		for key in groups:
			var part := _multimesh(mm.mesh, groups[key])
			part.cast_shadow = mi.cast_shadow
			part.layers = mi.layers
			part.material_override = mi.material_override
			part.visibility_range_end = VIEW_RANGE
			part.visibility_range_end_margin = 10.0
			part.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			root.add_child(part)
		mi.queue_free()


# 숲 바닥: 높낮이를 따라 휘어진 지면 (32m 구역마다 하나의 메시, 타일당 2x2 칸)
func _build_terrain(tiles: Array) -> void:
	var mat := _mat(Textures.pick("grass", Textures.ground("grass")), Vector3(0.5, 0.5, 1))
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var chunks := {}
	for xf in tiles:
		var o: Vector3 = xf.origin
		var key := Vector2i(floori(o.x / CHUNK), floori(o.z / CHUNK))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(o)
	const SUB := 2
	for key in chunks:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for o in chunks[key]:
			var x0: float = o.x - T / 2.0
			var z0: float = o.z - T / 2.0
			var s := T / SUB
			for a in SUB:
				for b in SUB:
					var p := [Vector3(x0 + a * s, 0, z0 + b * s), Vector3(x0 + (a + 1) * s, 0, z0 + b * s),
						Vector3(x0 + (a + 1) * s, 0, z0 + (b + 1) * s), Vector3(x0 + a * s, 0, z0 + (b + 1) * s)]
					for k in 4:
						p[k].y = ground_y(p[k].x, p[k].z)
					for idx3 in [0, 1, 2, 0, 2, 3]:
						var v: Vector3 = p[idx3]
						var e := 0.5
						var nrm := Vector3(ground_y(v.x - e, v.z) - ground_y(v.x + e, v.z), 2.0 * e, ground_y(v.x, v.z - e) - ground_y(v.x, v.z + e)).normalized()
						st.set_normal(nrm)
						st.set_uv(Vector2(v.x, v.z) / T)
						st.add_vertex(v)
		st.generate_tangents()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.visibility_range_end = VIEW_RANGE + 10.0
		root.add_child(mi)


func _in_rect(r: Array, x: int, z: int) -> bool:
	return r.size() == 4 and x >= int(r[0]) and z >= int(r[1]) and x <= int(r[2]) and z <= int(r[3])


# 벽 높이: 성벽 12m · 본성 16m · 성당 10m · 야외에 닿은 작은 건물 7m · 나머지 4m
func _wall_h(x: int, z: int) -> float:
	if decor.is_empty():
		return WALL_H
	var wh: Dictionary = decor.get("wall_h", {})
	if _in_rect(decor.get("keep", []), x, z):
		return float(wh.get("keep", WALL_H))
	if _in_rect(decor.get("cathedral", []), x, z) or _in_rect(decor.get("transept", []), x, z):
		return float(wh.get("cathedral", WALL_H))
	var cu: Array = decor.get("curtain", [])
	if _in_rect(cu, x, z) and (x == int(cu[0]) or x == int(cu[2]) or z == int(cu[1]) or z == int(cu[3])):
		return float(wh.get("castle", WALL_H))
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if get_t(x + d.x, z + d.y) != EMPTY and area_at(x + d.x, z + d.y) == A_OUT:
			return 7.0
	return WALL_H


# 야외 지도: 나무·덤불, 성 탑, 성당 지붕·종탑·스테인드글라스·의자·제단
func _build_outdoor(tree_x: Array, bush_x: Array, wall_tex: Array) -> void:
	var stone := _mat(wall_tex, Vector3(2, 2, 1))
	# 나무 3종: 전나무 / 활엽수 / 마른 나무
	var bark0 := StandardMaterial3D.new()
	bark0.albedo_texture = Textures.wood()
	bark0.albedo_color = Color(0.45, 0.36, 0.3)
	var bark := _pbr_or("bark", bark0, Vector3(2, 2, 1))
	var pine := StandardMaterial3D.new()
	pine.albedo_color = Color(0.09, 0.17, 0.1)
	pine.roughness = 0.9
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.15, 0.24, 0.1)
	leaf.roughness = 0.9
	var parts := {} # 이름 -> [mesh, 변환들]
	var add_part := func(nm: String, mesh: Mesh, xf: Transform3D) -> void:
		if not parts.has(nm):
			parts[nm] = [mesh, []]
		parts[nm][1].append(xf)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.28
	trunk.height = 3.2
	trunk.radial_segments = 7
	trunk.material = bark
	var cones := []
	for k in 3:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = [1.9, 1.5, 1.0][k]
		cm.height = [3.0, 2.6, 2.1][k]
		cm.radial_segments = 8
		cm.material = pine
		cones.append(cm)
	var blob := SphereMesh.new()
	blob.radius = 1.6
	blob.height = 2.6
	blob.radial_segments = 8
	blob.rings = 5
	blob.material = leaf
	var branch := CylinderMesh.new()
	branch.top_radius = 0.05
	branch.bottom_radius = 0.12
	branch.height = 2.0
	branch.radial_segments = 5
	branch.material = bark
	for t in tree_x:
		var p: Vector3 = t[0]
		var s: float = t[1]
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		var xf := func(local: Vector3, lb := Basis()) -> Transform3D:
			return Transform3D(b * lb, p + b * local)
		add_part.call("trunk", trunk, xf.call(Vector3(0, 1.6, 0)))
		match int(t[2]):
			0:
				add_part.call("c0", cones[0], xf.call(Vector3(0, 3.0, 0)))
				add_part.call("c1", cones[1], xf.call(Vector3(0, 4.6, 0)))
				add_part.call("c2", cones[2], xf.call(Vector3(0, 6.0, 0)))
			1:
				add_part.call("blob", blob, xf.call(Vector3(0, 4.3, 0)))
				add_part.call("blob", blob, xf.call(Vector3(0.9, 3.7, 0.4), Basis().scaled(Vector3.ONE * 0.75)))
				add_part.call("blob", blob, xf.call(Vector3(-0.8, 3.9, -0.5), Basis().scaled(Vector3.ONE * 0.7)))
			_:
				add_part.call("branch", branch, xf.call(Vector3(0.45, 3.2, 0), Basis(Vector3.BACK, -0.7)))
				add_part.call("branch", branch, xf.call(Vector3(-0.4, 3.8, 0.2), Basis(Vector3.BACK, 0.8)))
				add_part.call("branch", branch, xf.call(Vector3(0, 4.4, -0.3), Basis(Vector3.RIGHT, 0.6)))
	for nm in parts:
		root.add_child(_multimesh(parts[nm][0], parts[nm][1]))
	if bush_x.size():
		var bush := SphereMesh.new()
		bush.radius = 0.55
		bush.height = 0.7
		bush.radial_segments = 6
		bush.rings = 3
		bush.material = leaf
		var bmi := _multimesh(bush, bush_x)
		bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(bmi)
	# 화로(바닥) / 샹들리에(천장): 불꽃 + 점광원
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.12, 0.11, 0.1)
	iron.metallic = 0.6
	iron.roughness = 0.5
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.55
	bowl.bottom_radius = 0.3
	bowl.height = 0.35
	bowl.radial_segments = 10
	bowl.material = iron
	var leg := CylinderMesh.new()
	leg.top_radius = 0.08
	leg.bottom_radius = 0.14
	leg.height = 1.0
	leg.radial_segments = 6
	leg.material = iron
	var ring := TorusMesh.new()
	ring.inner_radius = 1.0
	ring.outer_radius = 1.12
	ring.rings = 16
	ring.ring_segments = 4
	ring.material = iron
	var fire := CylinderMesh.new()
	fire.top_radius = 0.0
	fire.bottom_radius = 0.38
	fire.height = 0.7
	fire.radial_segments = 6
	fire.material = Models.glow_mat(Color(1.0, 0.6, 0.25), 4.0)
	var candle := CylinderMesh.new()
	candle.top_radius = 0.0
	candle.bottom_radius = 0.07
	candle.height = 0.22
	candle.radial_segments = 5
	candle.material = Models.glow_mat(Color(1.0, 0.8, 0.45), 4.0)
	var lx := {"bowl": [bowl, []], "leg": [leg, []], "ring": [ring, []], "fire": [fire, []], "candle": [candle, []]}
	for li in decor.get("lights", []):
		var c := center(int(li[0]), int(li[1]))
		var lt := OmniLight3D.new()
		lt.light_color = Color(1.0, 0.66, 0.36)
		lt.omni_attenuation = 1.1
		lt.distance_fade_enabled = true
		lt.distance_fade_begin = 45.0
		lt.distance_fade_length = 10.0
		if str(li[2]) == "chandelier":
			var top := WALL_H if area_at(int(li[0]), int(li[1])) != A_CATH else float(decor.get("wall_h", {}).get("cathedral", WALL_H))
			var y := top - 1.3
			lx.ring[1].append(Transform3D(Basis().scaled(Vector3(1, 0.6, 1)), c + Vector3(0, y, 0)))
			for k in 8:
				var ang := k * TAU / 8.0
				lx.candle[1].append(Transform3D(Basis(), c + Vector3(cos(ang) * 1.06, y + 0.16, sin(ang) * 1.06)))
			lt.position = c + Vector3(0, y - 0.3, 0)
			lt.light_energy = 2.6
			lt.omni_range = 13.0
		else:
			lx.leg[1].append(Transform3D(Basis(), c + Vector3(0, 0.5, 0)))
			lx.bowl[1].append(Transform3D(Basis(), c + Vector3(0, 1.1, 0)))
			lx.fire[1].append(Transform3D(Basis(), c + Vector3(0, 1.55, 0)))
			lt.position = c + Vector3(0, 2.0, 0)
			lt.light_energy = 2.8
			lt.omni_range = 14.0
			static_blocks.append([Vector3(c.x, 0, c.z), 0.55])
		root.add_child(lt)
	for k in lx:
		if lx[k][1].size():
			var lmi := _multimesh(lx[k][0], lx[k][1])
			if k in ["fire", "candle"]:
				lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(lmi)
	# 성 탑: 원통 + 뾰족 지붕
	var slate0 := StandardMaterial3D.new()
	slate0.albedo_color = Color(0.2, 0.22, 0.28)
	slate0.roughness = 0.6
	var slate := _pbr_or("roof", slate0, Vector3(6, 4, 1), Color(0.75, 0.78, 0.85))
	for tw in decor.get("towers", []):
		var c := center(int(tw[0]), int(tw[1]))
		var r := float(tw[2])
		var h := float(tw[3])
		var cyl := CylinderMesh.new()
		cyl.top_radius = r
		cyl.bottom_radius = r * 1.06
		cyl.height = h
		cyl.radial_segments = 16
		cyl.material = _mat(wall_tex, Vector3(TAU * r / 2.5, h / 2.5, 1) if Textures.pbr("wall").size() else Vector3(6, h / 3.0, 1))
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.position = c + Vector3(0, h / 2.0, 0)
		root.add_child(mi)
		var roof := CylinderMesh.new()
		roof.top_radius = 0.0
		roof.bottom_radius = r + 0.6
		roof.height = r * 2.2
		roof.radial_segments = 16
		roof.material = slate
		var rm := MeshInstance3D.new()
		rm.mesh = roof
		rm.position = c + Vector3(0, h + r * 1.1, 0)
		root.add_child(rm)
		static_blocks.append([Vector3(c.x, 0, c.z), r])
	# 성당
	var ca: Array = decor.get("cathedral", [])
	if ca.size() == 4:
		var ch := float(decor.get("wall_h", {}).get("cathedral", WALL_H))
		var x0 := int(ca[0])
		var z0 := int(ca[1])
		var x1 := int(ca[2])
		var z1 := int(ca[3])
		var cx := (x0 + x1 + 1) * T / 2.0
		var nave := PrismMesh.new()
		nave.size = Vector3((x1 - x0 + 1) * T + 1.0, 7.0, (z1 - z0 + 1) * T)
		nave.material = slate
		var nm := MeshInstance3D.new()
		nm.mesh = nave
		nm.position = Vector3(cx, ch + 3.5, (z0 + z1 + 1) * T / 2.0)
		root.add_child(nm)
		var tr: Array = decor.get("transept", [])
		if tr.size() == 4:
			var tp := PrismMesh.new()
			tp.size = Vector3((int(tr[3]) - int(tr[1]) + 1) * T + 1.0, 6.0, (int(tr[2]) - int(tr[0]) + 1) * T)
			tp.material = slate
			var tmi := MeshInstance3D.new()
			tmi.mesh = tp
			tmi.rotation.y = PI / 2
			tmi.position = Vector3((int(tr[0]) + int(tr[2]) + 1) * T / 2.0, ch + 3.0, (int(tr[1]) + int(tr[3]) + 1) * T / 2.0)
			root.add_child(tmi)
		# 정면 종탑 + 첨탑
		var sp: Array = decor.get("spire", [])
		if sp.size() == 2:
			var sc := center(int(sp[0]), int(sp[1]))
			var bel := BoxMesh.new()
			bel.size = Vector3(7, 9, 7)
			bel.material = _mat(wall_tex, Vector3(2, 2.5, 1))
			var bm := MeshInstance3D.new()
			bm.mesh = bel
			bm.position = Vector3(sc.x, ch + 4.5, sc.z)
			root.add_child(bm)
			var spire := CylinderMesh.new()
			spire.top_radius = 0.0
			spire.bottom_radius = 5.0
			spire.height = 14.0
			spire.radial_segments = 4
			spire.material = slate
			var smi := MeshInstance3D.new()
			smi.mesh = spire
			smi.rotation.y = PI / 4
			smi.position = Vector3(sc.x, ch + 9.0 + 7.0, sc.z)
			root.add_child(smi)
		# 스테인드글라스: 성당 안쪽 벽 높은 곳의 빛나는 창
		var glass_cols := [Color(0.25, 0.4, 1.0), Color(0.9, 0.2, 0.2), Color(1.0, 0.75, 0.25), Color(0.3, 0.8, 0.4)]
		var glass := {}
		for z in range(z0, z1 + 1):
			for x in range(x0 - 7, x1 + 8):
				if area_at(x, z) != A_CATH or get_t(x, z) == EMPTY or (x + z) % 2 != 0:
					continue
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if get_t(x + d.x, z + d.y) != EMPTY:
						continue
					var n := Vector3(d.x, 0, d.y)
					var col: Color = glass_cols[rng.randi() % glass_cols.size()]
					var key := col.to_html()
					if not glass.has(key):
						glass[key] = [col, []]
					glass[key][1].append(Transform3D(Basis(Vector3.UP, atan2(-n.x, -n.z)), center(x, z) + n * (T / 2.0 - 0.08) + Vector3(0, 6.4, 0)))
		for key in glass:
			var q := QuadMesh.new()
			q.size = Vector2(1.6, 3.4)
			q.material = Models.glow_mat(glass[key][0], 1.4)
			var gi := _multimesh(q, glass[key][1])
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(gi)
		# 신랑 양쪽 긴 의자 (가운데 통로)
		var pew := BoxMesh.new()
		pew.size = Vector3(4.0, 0.9, 0.7)
		var pmat := StandardMaterial3D.new()
		pmat.albedo_texture = Textures.wood()
		pew.material = _pbr_or("wood", pmat, Vector3(3, 2, 1))
		var pews := []
		var zs := (int(tr[3]) + 1) * T + 1.5 if tr.size() == 4 else (z0 + 3) * T
		var zz: float = zs
		while zz < z1 * T - 1.5:
			for side in [-1.0, 1.0]:
				var pc := Vector3(cx + side * 4.3, 0.45, zz)
				pews.append(Transform3D(Basis(), pc))
				static_blocks.append([Vector3(pc.x - 1.3, 0, pc.z), 0.45])
				static_blocks.append([Vector3(pc.x, 0, pc.z), 0.45])
				static_blocks.append([Vector3(pc.x + 1.3, 0, pc.z), 0.45])
			zz += 2.6
		if pews.size():
			root.add_child(_multimesh(pew, pews))
		# 제단 + 촛불 (후진)
		var alt := MeshInstance3D.new()
		var ab := BoxMesh.new()
		ab.size = Vector3(3.2, 1.1, 1.4)
		ab.material = stone
		alt.mesh = ab
		var ap := Vector3(cx, 0.55, (z0 + 2) * T)
		alt.position = ap
		root.add_child(alt)
		static_blocks.append([Vector3(ap.x, 0, ap.z), 1.3])
		var cl := CylinderMesh.new()
		cl.top_radius = 0.05
		cl.bottom_radius = 0.05
		cl.height = 0.35
		cl.material = Models.glow_mat(Color(1.0, 0.85, 0.5), 3.0)
		var cand := []
		for k in 5:
			cand.append(Transform3D(Basis(), ap + Vector3(-1.2 + k * 0.6, 0.72, 0.0)))
		root.add_child(_multimesh(cl, cand))
		var al := OmniLight3D.new()
		al.light_color = Color(1.0, 0.8, 0.5)
		al.light_energy = 2.0
		al.omni_range = 10.0
		al.position = ap + Vector3(0, 1.5, 1.0)
		root.add_child(al)


func animate_torches(time: float, cam_pos: Vector3) -> void:
	for i in torches.size():
		var t: Dictionary = torches[i]
		var fl := sin(time * 11.0 + i * 3.7) * 0.5 + sin(time * 5.3 + i) * 0.4
		var l = t.light
		if absf(t.pos.x - cam_pos.x) + absf(t.pos.z - cam_pos.z) < 40.0:
			if l != null:
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
var dyn_blocks: Array = [] # 돌기둥 등 일시적인 원형 장애물 [[pos, radius], ...]


func resolve_circle(pos: Vector3, r: float) -> Vector3:
	if closed_n > 0:
		pos = _push_doors(pos, r)
	pos = _push_blocks(pos, r, dyn_blocks)
	if static_blocks.size():
		pos = _push_blocks(pos, r, static_blocks)
	return _resolve_tiles(pos, r)


func _push_blocks(pos: Vector3, r: float, blocks: Array) -> Vector3:
	for b in blocks:
		var bp: Vector3 = b[0]
		if absf(bp.x - pos.x) > 8.0 or absf(bp.z - pos.z) > 8.0:
			continue
		var bdx := pos.x - bp.x
		var bdz := pos.z - bp.z
		var bd := sqrt(bdx * bdx + bdz * bdz)
		var mn: float = b[1] + r
		if bd < mn:
			if bd < 1e-4:
				bdx = 1.0
				bdz = 0.0
				bd = 1.0
			pos.x = bp.x + bdx / bd * mn
			pos.z = bp.z + bdz / bd * mn
	return pos


func _resolve_tiles(pos: Vector3, r: float) -> Vector3:
	var tx := to_tile(pos.x)
	var tz := to_tile(pos.z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var x := tx + dx
			var z := tz + dz
			var g := get_t(x, z)
			if g == PILLAR or g == TREE:
				var cx := (x + 0.5) * T
				var cz := (z + 0.5) * T
				var ddx := pos.x - cx
				var ddz := pos.z - cz
				var d := sqrt(ddx * ddx + ddz * ddz)
				var mn := (1.3 if g == PILLAR else 0.7) + r
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
	if closed_n > 0 and door_between(Vector3(ax, 0, az), Vector3(bx, 0, bz)):
		return false
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
		if g == PILLAR or g == TREE:
			var cx := (tx + 0.5) * T
			var cz := (tz + 0.5) * T
			if Vector2(x - cx, z - cz).length() < (1.2 if g == PILLAR else 0.6):
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
			if tile_solid(t.x, t.y):
				continue
			if margin > 0 and not _open_around(t.x, t.y) and k < 25:
				continue
			var c := center(t.x, t.y)
			c.x += rng.randf_range(-1.0, 1.0)
			c.z += rng.randf_range(-1.0, 1.0)
			c.y = ground_y(c.x, c.z)
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


# ------------------------------------------------------------------ 문
# 건물 입구(야외 ↔ 실내/성당 타일 경계)마다 4m 폭 양문. 닫혀 있으면 이동·시야·투사체를 막음.
# 위치는 지도에서 정해지므로 서버/클라이언트가 같은 목록을 가짐 (열림 상태만 동기화)
# door: {id, axis(0: x=coord 경계, 1: z=coord 경계), coord, lo, hi, pos, open, node, L, R, swing}
var doors: Array = []
var closed_n := 0
const DOOR_H := 3.6


func _build_doors() -> void:
	doors.clear()
	if not has_outdoor:
		return
	var wood := _pbr_or("wood", _mat(Textures.stone_wall(false), Vector3.ONE, Color(0.35, 0.23, 0.12)), Vector3(1, 2, 1), Color(0.8, 0.65, 0.5))
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.13, 0.12, 0.12)
	iron.metallic = 0.8
	iron.roughness = 0.55
	for z in H:
		for x in W:
			if not _walkable_door(x, z):
				continue
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var nx: int = x + d.x
				var nz: int = z + d.y
				if not _walkable_door(nx, nz):
					continue
				var a := area_at(x, z)
				var b := area_at(nx, nz)
				if a == b or (a != A_OUT and b != A_OUT):
					continue
				var door := {"id": doors.size(), "kind": "door", "name": "문", "open": false, "swing": 0.0}
				if d.x == 1:
					door.axis = 0
					door.coord = (x + 1) * T
					door.lo = z * T
					door.hi = (z + 1) * T
					door.pos = Vector3(door.coord, 0, (z + 0.5) * T)
				else:
					door.axis = 1
					door.coord = (z + 1) * T
					door.lo = x * T
					door.hi = (x + 1) * T
					door.pos = Vector3((x + 0.5) * T, 0, door.coord)
				door.pos.y = minf(ground_y(door.pos.x - 0.1 * d.x, door.pos.z - 0.1 * d.y), ground_y(door.pos.x + 0.1 * d.x, door.pos.z + 0.1 * d.y))
				# 안쪽(실내) 방향: 문은 안쪽으로 열림
				door.inward = Vector3(d.x, 0, d.y) * (1.0 if b != A_OUT else -1.0)
				_door_node(door, wood, iron)
				doors.append(door)
	closed_n = doors.size()


# 건물 안(실내/성당)이면 달빛을 받지 않는 레이어로: 실내에 들어간 캐릭터·뷰모델·상자가 달빛에 밝게 뜨지 않게
func indoor_at(p: Vector3) -> bool:
	return has_outdoor and area_at(to_tile(p.x), to_tile(p.z)) != A_OUT


static func set_indoor(node: Node3D, indoor: bool) -> void:
	if node == null or node.get_meta("indoor", false) == indoor:
		return
	node.set_meta("indoor", indoor)
	var lay := INDOOR_LAYER if indoor else 1
	for n in node.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = lay
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = lay


func _walkable_door(x: int, z: int) -> bool:
	var g := get_t(x, z)
	return g == ROOM or g == CORR


func _door_node(door: Dictionary, wood: Material, iron: Material) -> void:
	var n := Node3D.new()
	n.position = door.pos
	# 문짝 평면이 경계선을 따라가도록: axis 0이면 z 방향으로 늘어섬
	n.rotation.y = PI / 2 if door.axis == 0 else 0.0
	root.add_child(n)
	var leaves := []
	for side in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(side * T * 0.5, 0, 0)
		n.add_child(hinge)
		var leaf := Node3D.new()
		hinge.add_child(leaf)
		var w := T * 0.5 - 0.04
		var plank := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w, DOOR_H, 0.14)
		plank.mesh = bm
		plank.material_override = wood
		plank.position = Vector3(-side * (w * 0.5 + 0.02), DOOR_H * 0.5, 0)
		leaf.add_child(plank)
		# 쇠띠 3줄 + 손잡이 고리
		for hy in [0.5, DOOR_H * 0.5, DOOR_H - 0.5]:
			var band := MeshInstance3D.new()
			var bb := BoxMesh.new()
			bb.size = Vector3(w * 0.92, 0.12, 0.18)
			band.mesh = bb
			band.material_override = iron
			band.position = Vector3(-side * (w * 0.5 + 0.02), hy, 0)
			leaf.add_child(band)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.07
		tm.outer_radius = 0.11
		tm.rings = 8
		tm.ring_segments = 6
		ring.mesh = tm
		ring.material_override = iron
		ring.rotation.x = PI / 2
		ring.position = Vector3(-side * (w - 0.25), 1.2, 0.12)
		leaf.add_child(ring)
		leaves.append(hinge)
	# 문틀 위 상인방 (문 위쪽 벽과 이어짐)
	var lintel := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(T + 0.3, 0.35, 0.4)
	lintel.mesh = lb
	lintel.material_override = wood
	lintel.position = Vector3(0, DOOR_H + 0.17, 0)
	n.add_child(lintel)
	door.node = n
	door.leaves = leaves
	# 열리는 방향: 문 노드의 로컬 +z가 inward와 같으면 +, 아니면 -
	var local_z := n.transform.basis.z
	door.dir_sign = 1.0 if local_z.dot(door.inward) > 0.0 else -1.0


func set_door_open(id: int, open: bool) -> void:
	if id < 0 or id >= doors.size():
		return
	var d: Dictionary = doors[id]
	if d.open == open:
		return
	d.open = open
	closed_n += -1 if open else 1


# 문짝 회전 애니메이션 (열림 0 → 1)
func animate_doors(dt: float) -> void:
	for d in doors:
		var target := 1.0 if d.open else 0.0
		if d.swing == target:
			continue
		d.swing = move_toward(d.swing, target, dt * 2.5)
		var e: float = d.swing * d.swing * (3.0 - 2.0 * d.swing)
		var ang: float = e * deg_to_rad(95.0) * d.dir_sign
		d.leaves[0].rotation.y = -ang
		d.leaves[1].rotation.y = ang


func _push_doors(pos: Vector3, r: float) -> Vector3:
	var rr := r + 0.1
	for d in doors:
		if d.open:
			continue
		if d.axis == 0:
			if pos.z < d.lo - rr or pos.z > d.hi + rr or absf(pos.x - d.coord) >= rr:
				continue
			pos.x = d.coord + (rr if pos.x >= d.coord else -rr)
		else:
			if pos.x < d.lo - rr or pos.x > d.hi + rr or absf(pos.z - d.coord) >= rr:
				continue
			pos.z = d.coord + (rr if pos.z >= d.coord else -rr)
	return pos


# a→b 선분이 닫힌 문을 지나는지
func door_between(a: Vector3, b: Vector3) -> bool:
	for d in doors:
		if d.open:
			continue
		var c: float = d.coord
		var pa: float = a.x if d.axis == 0 else a.z
		var pb: float = b.x if d.axis == 0 else b.z
		if (pa - c) * (pb - c) > 0.0 or pa == pb:
			continue
		var t := (c - pa) / (pb - pa)
		var q: float = lerpf(a.z, b.z, t) if d.axis == 0 else lerpf(a.x, b.x, t)
		if q >= d.lo and q <= d.hi:
			# 높이: 문 위로 넘어가는 투사체는 통과
			var y := lerpf(a.y, b.y, t)
			if y <= d.pos.y + DOOR_H + 0.3:
				return true
	return false


func door_near(p: Vector3, max_d: float):
	var best = null
	var bd := max_d
	for d in doors:
		var dd := Vector2(d.pos.x - p.x, d.pos.z - p.z).length()
		if dd < bd:
			bd = dd
			best = d
	return best
