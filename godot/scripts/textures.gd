# 절차적 텍스처 (색상 + 노멀맵). 레벨마다 다시 만들지 않도록 캐시
class_name Textures
extends RefCounted

static var _cache := {}


static func _noise_img(size: int, freq: float, seed_v: int) -> Image:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = 4
	return n.get_seamless_image(size, size)


# 벽돌 벽: albedo, normal 반환
static func stone_wall(deep: bool) -> Array:
	var key := "wall%s" % deep
	if _cache.has(key):
		return _cache[key]
	var S := 256
	var tint := Color(0.40, 0.36, 0.33) if not deep else Color(0.42, 0.25, 0.22)
	var albedo := Image.create(S, S, false, Image.FORMAT_RGB8)
	var height := Image.create(S, S, false, Image.FORMAT_RGB8)
	albedo.fill(Color(0.12, 0.11, 0.10))
	height.fill(Color(0.1, 0.1, 0.1))
	var rows := 6
	var bh := S / rows
	var bw := S / 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 if not deep else 11
	for r in rows:
		var off := 0 if r % 2 == 1 else bw / 2
		for x in range(-bw, S + bw, bw):
			var k := rng.randf_range(0.75, 1.1)
			var rect := Rect2i(x + off + 3, r * bh + 3, bw - 6, bh - 6)
			albedo.fill_rect(rect.intersection(Rect2i(0, 0, S, S)), tint * k)
			height.fill_rect(rect.intersection(Rect2i(0, 0, S, S)), Color(0.75, 0.75, 0.75))
			# 가로로 넘어가는 벽돌은 반대편에도 그려 타일링 유지
			if rect.position.x + rect.size.x > S:
				var wrapped := Rect2i(rect.position.x - S, rect.position.y, rect.size.x, rect.size.y).intersection(Rect2i(0, 0, S, S))
				albedo.fill_rect(wrapped, tint * k)
				height.fill_rect(wrapped, Color(0.75, 0.75, 0.75))
	var nz := _noise_img(S, 0.05, rng.seed)
	var nz2 := _noise_img(S, 0.25, rng.seed + 1)
	for y in S:
		for x in S:
			var a := nz.get_pixel(x, y).r
			var b := nz2.get_pixel(x, y).r
			var c := albedo.get_pixel(x, y)
			var m := 0.7 + a * 0.45 + (b - 0.5) * 0.25
			# 이끼 얼룩
			var moss := clampf((a - 0.68) * 3.0, 0.0, 0.35)
			c = Color(c.r * m, c.g * m, c.b * m).lerp(Color(0.16, 0.2, 0.1), moss)
			albedo.set_pixel(x, y, c)
			var h := height.get_pixel(x, y).r + (b - 0.5) * 0.35
			height.set_pixel(x, y, Color(h, h, h))
	height.bump_map_to_normal_map(6.0)
	albedo.generate_mipmaps()
	height.generate_mipmaps()
	var out := [ImageTexture.create_from_image(albedo), ImageTexture.create_from_image(height)]
	_cache[key] = out
	return out


static func floor_tiles(deep: bool) -> Array:
	var key := "floor%s" % deep
	if _cache.has(key):
		return _cache[key]
	var S := 256
	var tint := Color(0.30, 0.28, 0.25) if not deep else Color(0.32, 0.21, 0.19)
	var albedo := Image.create(S, S, false, Image.FORMAT_RGB8)
	var height := Image.create(S, S, false, Image.FORMAT_RGB8)
	albedo.fill(Color(0.07, 0.065, 0.06))
	height.fill(Color(0.1, 0.1, 0.1))
	var n := 4
	var s := S / n
	var rng := RandomNumberGenerator.new()
	rng.seed = 3 if not deep else 5
	for i in n:
		for j in n:
			var k := rng.randf_range(0.7, 1.1)
			albedo.fill_rect(Rect2i(i * s + 2, j * s + 2, s - 4, s - 4), tint * k)
			height.fill_rect(Rect2i(i * s + 2, j * s + 2, s - 4, s - 4), Color(0.7, 0.7, 0.7))
	var nz := _noise_img(S, 0.04, rng.seed)
	var nz2 := _noise_img(S, 0.3, rng.seed + 9)
	for y in S:
		for x in S:
			var a := nz.get_pixel(x, y).r
			var b := nz2.get_pixel(x, y).r
			var c := albedo.get_pixel(x, y)
			var m := 0.7 + a * 0.5 + (b - 0.5) * 0.3
			albedo.set_pixel(x, y, Color(c.r * m, c.g * m, c.b * m))
			var h := height.get_pixel(x, y).r + (b - 0.5) * 0.3
			height.set_pixel(x, y, Color(h, h, h))
	height.bump_map_to_normal_map(5.0)
	albedo.generate_mipmaps()
	height.generate_mipmaps()
	var out := [ImageTexture.create_from_image(albedo), ImageTexture.create_from_image(height)]
	_cache[key] = out
	return out


static func wood() -> ImageTexture:
	if _cache.has("wood"):
		return _cache["wood"]
	var S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	var nz := _noise_img(S, 0.02, 21)
	for y in S:
		for x in S:
			var plank := (y / 32) % 2
			var base := Color(0.36, 0.23, 0.12) if plank == 0 else Color(0.40, 0.26, 0.13)
			var grain := sin((y + nz.get_pixel(x, y).r * 40.0) * 0.9) * 0.08
			var m := 0.85 + grain + nz.get_pixel(x, y).r * 0.2
			if y % 32 == 0:
				m = 0.3
			img.set_pixel(x, y, Color(base.r * m, base.g * m, base.b * m))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache["wood"] = t
	return t


# 야외 바닥: 풀(숲) / 자갈(성 안뜰) / 대리석 바둑판(성당)  → [albedo, normal]
static func ground(kind: String) -> Array:
	var key := "ground_" + kind
	if _cache.has(key):
		return _cache[key]
	var S := 256
	var albedo := Image.create(S, S, false, Image.FORMAT_RGB8)
	var height := Image.create(S, S, false, Image.FORMAT_RGB8)
	var nz := _noise_img(S, 0.03, 41 + kind.length())
	var nz2 := _noise_img(S, 0.35, 77 + kind.length())
	for y in S:
		for x in S:
			var a := nz.get_pixel(x, y).r
			var b := nz2.get_pixel(x, y).r
			var c: Color
			var h := 0.5
			match kind:
				"grass":
					# 풀 + 흙 얼룩 + 낙엽
					var g := Color(0.16, 0.22, 0.09).lerp(Color(0.22, 0.27, 0.11), b)
					c = g.lerp(Color(0.2, 0.15, 0.09), clampf((0.42 - a) * 3.0, 0.0, 0.8))
					if b > 0.82:
						c = c.lerp(Color(0.35, 0.22, 0.08), 0.5)
					h = 0.4 + b * 0.3
				"gravel":
					var k := 0.6 + b * 0.55
					c = Color(0.34, 0.29, 0.22) * k
					c = c.lerp(Color(0.18, 0.15, 0.11), clampf((0.45 - a) * 2.5, 0.0, 0.6))
					h = b
				_:
					# 성당: 흑백 대리석 바둑판
					var cell := ((x / 64) + (y / 64)) % 2
					var base := Color(0.62, 0.6, 0.56) if cell == 0 else Color(0.16, 0.15, 0.15)
					var vein := clampf(1.0 - absf(sin((x + a * 120.0) * 0.07)) * 6.0, 0.0, 1.0) * 0.25
					c = base * (0.88 + b * 0.12) + Color(vein, vein, vein) * (1.0 if cell == 1 else -0.6)
					h = 0.8 if (x % 64 > 1 and y % 64 > 1) else 0.2
			albedo.set_pixel(x, y, c)
			height.set_pixel(x, y, Color(h, h, h))
	height.bump_map_to_normal_map(3.0 if kind != "marble" else 2.0)
	albedo.generate_mipmaps()
	height.generate_mipmaps()
	var out := [ImageTexture.create_from_image(albedo), ImageTexture.create_from_image(height)]
	_cache[key] = out
	return out
