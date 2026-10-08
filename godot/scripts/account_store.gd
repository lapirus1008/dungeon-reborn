# 온라인 서버의 계정 DB (전용 서버 전용)
# 기본 백엔드: 계정별 JSON 파일 (클라우드 서버의 디스크/볼륨, 예: AWS EBS·Lightsail 디스크)
# 다른 DB(DynamoDB, PostgreSQL 등)로 바꿀 때는 _read/_write 두 함수만 교체하면 된다
class_name AccountStore
extends RefCounted

var dir := ""
var cache := {} # 계정 키 -> {name, salt, hash, data, created}


func _init(path: String) -> void:
	dir = path
	DirAccess.make_dir_recursive_absolute(dir)


static func key_of(nm: String) -> String:
	return nm.strip_edges().to_lower().sha256_text().left(32)


static func hash_pin(salt: String, pin: String) -> String:
	var h := (salt + ":" + pin)
	# 단순 반복 해시 (무차별 대입을 느리게)
	for i in 2000:
		h = h.sha256_text()
	return h


static func valid_name(nm: String) -> bool:
	var n := nm.strip_edges()
	return n.length() >= 2 and n.length() <= 16 and not n.contains("/") and not n.contains("\\")


# 로그인 (없으면 새 계정 생성). 성공 시 {ok, data, created}, 실패 시 {ok:false, msg}
# 공개 서버 보호: 계정별 연속 실패 5회 → 5분 잠금, 접속 주소(IP)별 새 계정은 1시간에 3개까지
const FAIL_MAX := 5
const LOCK_SEC := 300
const NEW_PER_IP := 3
const NEW_PIN_MIN := 6 # 새 계정 PIN 최소 길이 (기존 4자리 계정은 그대로 로그인 가능)
var fails := {} # 계정 키 -> [실패 횟수, 잠금 해제 시각(초)]
var new_by_ip := {} # IP -> [생성 시각들]


func login(nm: String, pin: String, ip := "") -> Dictionary:
	var now := Time.get_unix_time_from_system()
	var lk: Array = fails.get(key_of(nm), [0, 0.0])
	if lk[1] > now:
		return {"ok": false, "msg": "로그인 실패가 많아 잠시 잠겼습니다 (%d초 후 다시 시도)" % ceili(lk[1] - now)}
	if not valid_name(nm):
		return {"ok": false, "msg": "이름은 2~16자로 정해 주세요"}
	if pin.length() < 4 or pin.length() > 32:
		return {"ok": false, "msg": "PIN은 4~32자로 정해 주세요"}
	var k := key_of(nm)
	var rec = cache.get(k)
	if rec == null:
		rec = _read(k)
	if rec == null:
		if ip != "":
			var recent: Array = new_by_ip.get(ip, []).filter(func(t): return now - t < 3600.0)
			if recent.size() >= NEW_PER_IP:
				return {"ok": false, "msg": "이 주소에서 새 계정을 너무 많이 만들었습니다. 잠시 후 다시 시도하세요"}
			recent.append(now)
			new_by_ip[ip] = recent
		if pin.length() < NEW_PIN_MIN:
			return {"ok": false, "msg": "새 계정의 PIN은 %d자 이상으로 정해 주세요" % NEW_PIN_MIN}
		var crypto := Crypto.new()
		var salt := crypto.generate_random_bytes(16).hex_encode()
		rec = {"name": nm.strip_edges(), "salt": salt, "hash": hash_pin(salt, pin), "data": Account.fresh(), "created": Time.get_datetime_string_from_system(true)}
		rec.data.erase("settings")
		cache[k] = rec
		_write(k, rec)
		return {"ok": true, "data": rec.data, "name": rec.name, "created": true}
	if hash_pin(rec.salt, pin) != rec.hash:
		lk[0] += 1
		if lk[0] >= FAIL_MAX:
			lk = [0, now + LOCK_SEC]
			fails[key_of(nm)] = lk
			return {"ok": false, "msg": "PIN이 %d번 틀려 %d분 동안 잠겼습니다" % [FAIL_MAX, LOCK_SEC / 60]}
		fails[key_of(nm)] = lk
		return {"ok": false, "msg": "PIN이 맞지 않습니다 (%d/%d)" % [lk[0], FAIL_MAX]}
	fails.erase(key_of(nm))
	rec.data = Account.normalize(rec.data)
	rec.data.erase("settings")
	cache[k] = rec
	return {"ok": true, "data": rec.data, "name": rec.name, "created": false}


func get_data(nm: String):
	var rec = cache.get(key_of(nm))
	return rec.data if rec != null else null


func save(nm: String) -> void:
	var k := key_of(nm)
	if cache.has(k):
		_write(k, cache[k])


func unload(nm: String) -> void:
	save(nm)
	cache.erase(key_of(nm))


# ---------------------------------------------------------------- 파일 백엔드
func _path(k: String) -> String:
	return dir.path_join(k + ".json")


func _read(k: String):
	var p := _path(k)
	if not FileAccess.file_exists(p):
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
	return parsed if parsed is Dictionary and parsed.has("hash") else null


# 임시 파일에 쓴 뒤 교체 (쓰는 도중 서버가 꺼져도 계정이 깨지지 않게)
func _write(k: String, rec: Dictionary) -> void:
	var p := _path(k)
	var tmp := p + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		printerr("[accounts] 저장 실패: ", tmp)
		return
	var out: Dictionary = rec.duplicate()
	out.data = Account.serial(rec.data)
	f.store_string(JSON.stringify(out))
	f.close()
	if DirAccess.rename_absolute(tmp, p) != OK:
		DirAccess.remove_absolute(p)
		DirAccess.rename_absolute(tmp, p)
