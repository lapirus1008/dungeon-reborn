# 코드로 합성한 효과음 (외부 오디오 파일 없음) (autoload: Sfx)
extends Node

const RATE := 22050
const POOL := 12

var streams := {}
var players: Array[AudioStreamPlayer] = []
var next := 0
var master_volume := 0.8


func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	_build()


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
	streams["coin"] = _to_wav(_mix(_tone(0.08, 1800, 1800, 0.2, "square"), _tone(0.12, 2400, 2400, 0.16, "square"), int(0.07 * RATE)))
	streams["portal"] = _to_wav(_tone(1.2, 200, 800, 0.35))
	streams["hurt"] = _to_wav(_mix(_tone(0.2, 220, 90, 0.5, "saw"), _noise(0.15, 0.1, 0.05, 1.5)))
	streams["growl"] = _to_wav(_tone(0.5, 110, 60, 0.45, "saw"))
	streams["death"] = _to_wav(_mix(_tone(0.7, 200, 40, 0.6, "saw"), _noise(0.5, 0.06, 0.02, 1.5)))
	streams["bell"] = _to_wav(_mix(_tone(2.5, 220, 218, 0.4), _tone(2.5, 440, 438, 0.2)))
	streams["step"] = _to_wav(_noise(0.07, 0.08, 0.04, 0.7))
	streams["ui"] = _to_wav(_tone(0.05, 700, 700, 0.18, "tri"))


# dist: 청자(플레이어)와의 거리, -1이면 감쇠 없음
func play(name: String, dist: float = -1.0, pitch_var := 0.06) -> void:
	if not streams.has(name):
		return
	var v := master_volume
	if dist >= 0.0:
		v *= maxf(0.0, 1.0 - dist / 35.0)
	if v <= 0.01:
		return
	var p := players[next]
	next = (next + 1) % POOL
	p.stream = streams[name]
	p.volume_db = linear_to_db(v)
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()
