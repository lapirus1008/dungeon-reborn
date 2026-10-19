# 효과음 (autoload: Sfx)
# assets/sfx/<이름>[_번호].wav (tools/gen_sfx.py 로 만든 중세풍 소리)를 우선 쓰고, 없으면 코드로 합성한 소리
# 같은 이름에 여러 파일(_1, _2 ...)이 있으면 매번 무작위로 골라 반복감을 줄임
extends Node

const RATE := 22050
const POOL := 12

var streams := {}
var variants := {} # 이름 -> [AudioStream, ...] (파일)
var _last := {} # 이름 -> 마지막 재생 시각 (같은 소리가 한꺼번에 겹치지 않게)
const SAME_GAP := 0.06
var players: Array[AudioStreamPlayer] = []
var next := 0
var master_volume := 0.8


func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	_build()
	_load_files()


# 효과음 파일: assets/sfx (합성해서 만든 기본 소리) → assets/sfx_recorded (직접 받은 녹음 소리, 같은 이름이면 이쪽이 우선)
# 이름 규칙: <소리이름>.wav / <소리이름>_2.ogg ... (wav·ogg·mp3)
const SFX_EXT := ["wav", "ogg", "mp3"]


func _load_files() -> void:
	var base_set := _scan("res://assets/sfx")
	var rec := _scan("res://assets/sfx_recorded")
	for k in base_set:
		variants[k] = base_set[k]
	for k in rec:
		variants[k] = rec[k]


func _scan(dir: String) -> Dictionary:
	var out := {}
	var da := DirAccess.open(dir)
	if da == null:
		return out
	var seen := {}
	for f in da.get_files():
		# 내보낸 게임에서는 원본 대신 .import/.remap 이름으로 보임 (에디터에서는 둘 다 보임)
		var fn := f.trim_suffix(".import").trim_suffix(".remap")
		if not (fn.get_extension().to_lower() in SFX_EXT) or seen.has(fn):
			continue
		seen[fn] = true
		var st = load(dir + "/" + fn)
		if st == null:
			continue
		var base := fn.get_basename()
		var parts := base.rsplit("_", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int():
			base = parts[0]
		if not out.has(base):
			out[base] = []
		out[base].append(st)
	return out


# 필터된 노이즈 버스트: freq는 저역통과 계수(0~1)로 근사
func _noise(dur: float, cutoff_start: float, cutoff_end: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / n
		var a := lerpf(cutoff_start, cutoff_end, t)
		lp += (randf() * 2.0 - 1.0 - lp) * a
		lp2 += (lp - lp2) * a
		out[i] = lp2 * vol * pow(1.0 - t, 2.0)
	return out


func _tone(dur: float, f0: float, f1: float, vol: float, wave := "sine") -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		var f := f0 * pow(f1 / f0, t)
		ph += f / RATE
		var s := 0.0
		match wave:
			"sine":
				s = sin(ph * TAU)
			"square":
				s = 1.0 if fmod(ph, 1.0) < 0.5 else -1.0
			"saw":
				s = fmod(ph, 1.0) * 2.0 - 1.0
			"tri":
				s = absf(fmod(ph, 1.0) * 4.0 - 2.0) - 1.0
		out[i] = s * vol * pow(1.0 - t, 1.5)
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, offset := 0) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size() + offset)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var v := 0.0
		if i < a.size():
			v += a[i]
		if i - offset >= 0 and i - offset < b.size():
			v += b[i - offset]
		out[i] = v
	return out


func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


func _build() -> void:
	streams["swing"] = _to_wav(_noise(0.2, 0.15, 0.6, 1.4))
	streams["hit"] = _to_wav(_mix(_noise(0.14, 0.12, 0.05, 2.0), _tone(0.14, 160, 60, 0.6, "tri")))
	streams["block"] = _to_wav(_mix(_tone(0.18, 1300, 900, 0.35, "square"), _noise(0.08, 0.8, 0.5, 0.6)))
	streams["bow"] = _to_wav(_mix(_tone(0.14, 320, 120, 0.5, "tri"), _noise(0.1, 0.9, 0.6, 0.5)))
	streams["magic"] = _to_wav(_tone(0.28, 900, 300, 0.3, "saw"))
	streams["fire"] = _to_wav(_noise(0.7, 0.08, 0.01, 3.0))
	streams["heal"] = _to_wav(_mix(_tone(0.45, 500, 900, 0.3), _tone(0.5, 750, 1300, 0.18)))
	streams["shield"] = _to_wav(_mix(_mix(_tone(0.6, 300, 1200, 0.3), _tone(0.6, 450, 1800, 0.18)), _noise(0.3, 0.6, 0.9, 0.4)))
	streams["shield_hit"] = _to_wav(_mix(_tone(0.25, 1600, 800, 0.3, "tri"), _tone(0.25, 2400, 1200, 0.15)))
	streams["shield_break"] = _to_wav(_mix(_noise(0.4, 0.9, 0.3, 1.2), _tone(0.4, 1800, 300, 0.3, "tri")))
	streams["chest"] = _to_wav(_mix(_tone(0.25, 180, 120, 0.35, "square"), _noise(0.3, 0.3, 0.2, 0.8)))
	streams["pickup"] = _to_wav(_tone(0.1, 900, 1400, 0.3, "tri"))
	streams["draw_blade"] = _to_wav(_mix(_noise(0.32, 0.25, 0.05, 2.5), _tone(0.32, 2600, 3400, 0.08, "saw")))
	streams["draw_wood"] = _to_wav(_mix(_tone(0.22, 140, 90, 0.4, "square"), _noise(0.25, 0.35, 0.15, 0.6)))
	streams["draw_soft"] = _to_wav(_noise(0.15, 0.15, 0.05, 1.0))
	streams["drop"] = _to_wav(_mix(_tone(0.12, 500, 220, 0.3, "tri"), _noise(0.1, 0.25, 0.1, 0.8)))
	streams["coin"] = _to_wav(_mix(_tone(0.08, 1800, 1800, 0.2, "square"), _tone(0.12, 2400, 2400, 0.16, "square"), int(0.07 * RATE)))
	streams["portal"] = _to_wav(_tone(1.2, 200, 800, 0.35))
	streams["hurt"] = _to_wav(_mix(_tone(0.2, 220, 90, 0.5, "saw"), _noise(0.15, 0.1, 0.05, 1.5)))
	streams["growl"] = _to_wav(_tone(0.5, 110, 60, 0.45, "saw"))
	streams["death"] = _to_wav(_mix(_tone(0.7, 200, 40, 0.6, "saw"), _noise(0.5, 0.06, 0.02, 1.5)))
	streams["bell"] = _to_wav(_mix(_tone(2.5, 220, 218, 0.4), _tone(2.5, 440, 438, 0.2)))
	streams["step"] = _to_wav(_noise(0.07, 0.08, 0.04, 0.7))
	streams["door"] = _to_wav(_mix(_tone(0.7, 260, 180, 0.18, "saw"), _noise(0.5, 0.1, 0.05, 0.5))) # 삐걱
	streams["door_shut"] = _to_wav(_mix(_tone(0.25, 90, 50, 0.6, "square"), _noise(0.2, 0.2, 0.05, 1.2))) # 쿵
	streams["ui"] = _to_wav(_tone(0.05, 700, 700, 0.18, "tri"))


# dist: 청자(플레이어)와의 거리, -1이면 감쇠 없음
func play(name: String, dist: float = -1.0, pitch_var := 0.06, vol := 1.0) -> void:
	if not streams.has(name) and not variants.has(name):
		return
	# 같은 소리를 아주 짧은 간격으로 여러 번 부르면 (상자 아이템 여러 개 줍기 등) 한 번만
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(name, -1.0)) < SAME_GAP:
		return
	_last[name] = now
	var v := master_volume * vol
	if dist >= 0.0:
		v *= maxf(0.0, 1.0 - dist / 35.0)
	if v <= 0.01:
		return
	var p := players[next]
	next = (next + 1) % POOL
	p.stream = variants[name].pick_random() if variants.has(name) else streams[name]
	p.volume_db = linear_to_db(v)
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()
