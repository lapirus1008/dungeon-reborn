# 미니맵(플레이어 중심 회전)과 전체 지도
class_name MiniMap
extends Control

var game
var big := false
var redraw_t := 0.0


func _process(dt: float) -> void:
	if game == null or not visible:
		return
	redraw_t -= dt
	if redraw_t <= 0.0:
		redraw_t = 0.1
		queue_redraw()


func _draw() -> void:
	if game == null or game.dungeon == null or game.player == null:
		return
	var dg = game.dungeon
	var p = game.player
	var w := size.x
	var h := size.y
	var center_on_player := not big
	var scale := 5.0 if not big else floorf(minf(w / dg.W, h / dg.H))
	if not big:
		draw_circle(Vector2(w / 2, h / 2), w / 2, Color(0.04, 0.035, 0.03, 0.92))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.035, 0.03, 0.95))
	var ptx: float = p.pos.x / Dungeon.T
	var ptz: float = p.pos.z / Dungeon.T
	var ox = w / 2 - ptx * scale if center_on_player else (w - dg.W * scale) / 2
	var oz = h / 2 - ptz * scale if center_on_player else (h - dg.H * scale) / 2
	if center_on_player:
		draw_set_transform(Vector2(w / 2, h / 2), p.yaw, Vector2.ONE)
		ox -= w / 2
		oz -= h / 2
	var ex: PackedByteArray = game.explored
	var r2 := (w / 2 - 4) * (w / 2 - 4)
	for z in dg.H:
		for x in dg.W:
			var i: int = z * dg.W + x
			if ex[i] == 0:
				continue
			var v: int = dg.grid[i]
			if v == Dungeon.EMPTY:
				continue
			var rx = ox + x * scale
			var rz = oz + z * scale
			if center_on_player and (rx * rx + rz * rz) > r2:
				continue
			var c := Color("#3a342c") if v == Dungeon.PILLAR else (Color("#6d6253") if dg.room_id[i] >= 0 else Color("#4d463c"))
			draw_rect(Rect2(rx, rz, scale + 0.5, scale + 0.5), c)
	var dot := func(wx: float, wz: float, col: Color, rad: float):
		var dx = ox + wx / Dungeon.T * scale
		var dz = oz + wz / Dungeon.T * scale
		if center_on_player and dx * dx + dz * dz > r2:
			return
		draw_circle(Vector2(dx, dz), rad, col)
	for c in game.chests:
		if ex[dg.idx(dg.to_tile(c.pos.x), dg.to_tile(c.pos.z))]:
			dot.call(c.pos.x, c.pos.z, Color("#5a4a2a") if c.opened else Color("#ffcc44"), maxf(2.0, scale * 0.35))
	for b in game.loot_bags:
		if ex[dg.idx(dg.to_tile(b.pos.x), dg.to_tile(b.pos.z))]:
			dot.call(b.pos.x, b.pos.z, Color("#ffe08a"), maxf(1.5, scale * 0.25))
	for a in game.actors:
		if a == p or not a.alive or a.extracted:
			continue
		if a.pos.distance_to(p.pos) > 30.0 or not dg.los(p.pos.x, p.pos.z, a.pos.x, a.pos.z):
			continue
		dot.call(a.pos.x, a.pos.z, Color("#ff5a3a") if a.kind == "bot" else Color("#cc3333"), maxf(2.0, scale * 0.35))
	for po in game.portals:
		var col := Color("#4ab8ff") if po.kind == "exit" else Color("#ff3a2a")
		var dx: float = ox + po.pos.x / Dungeon.T * scale
		var dz: float = oz + po.pos.z / Dungeon.T * scale
		if center_on_player:
			# 미니맵 밖이면 가장자리에 표시
			var v := Vector2(dx, dz)
			if v.length() > w / 2 - 8:
				v = v.normalized() * (w / 2 - 8)
			draw_circle(v, 5.0 + sin(game.time * 4.0), col)
		else:
			draw_circle(Vector2(dx, dz), maxf(4.0, scale * 0.8) + sin(game.time * 4.0), col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 플레이어 화살표
	var pp := Vector2(w / 2, h / 2) if center_on_player else Vector2(ox + ptx * scale, oz + ptz * scale)
	var rot = 0.0 if center_on_player else -p.yaw
	var pts := PackedVector2Array([Vector2(0, -8), Vector2(6, 6), Vector2(0, 2), Vector2(-6, 6)])
	for i in pts.size():
		pts[i] = pp + pts[i].rotated(rot)
	draw_colored_polygon(pts, Color.WHITE)
	if not big:
		draw_arc(Vector2(w / 2, h / 2), w / 2 - 1, 0, TAU, 64, Color("#6a5232"), 3.0)
