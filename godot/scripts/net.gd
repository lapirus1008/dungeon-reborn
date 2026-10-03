# 멀티플레이 네트워크 (오토로드 "Net")
# 구조: 호스트(또는 전용 서버)가 레이드 전체를 시뮬레이션하고, 클라이언트는
#  - 자기 캐릭터 이동은 즉시 로컬 처리 후 위치/입력을 전송
#  - 전투/몬스터/상자/전리품은 서버 결과(스냅샷 초당 20회 + 이벤트)를 받아 표시
extends Node

signal roster_changed
signal status_changed(text: String)
signal prepare_received # 클라이언트: 서버가 레이드 준비(장비 제출) 요청
signal begin_received(info: Dictionary) # 클라이언트: 레이드 시작
signal server_begin(loadouts: Dictionary) # 서버: 모든 장비가 모였으니 레이드 생성
signal disconnected(reason: String)

const PORT := 7777
const VERSION := "dr-mp-2"
const MAX_PLAYERS := 8

var mode := "offline" # offline | host | server(전용) | client
var my_name := "모험가"
var roster := {} # peer_id -> {name, cls, state("lobby"/"raid")}
var pvp := false
var game = null # 진행 중인 Game (RPC 전달 대상)
var status := ""
var loadouts := {}
var preparing := false
var prepare_left := 0.0
# 온라인 서버 계정 (전용 서버가 계정 DB를 가지고 있을 때)
var accounts: AccountStore = null # 서버: 계정 DB
var peer_acct := {} # 서버: peer_id -> 계정 이름
var pin := "" # 클라이언트: 로그인 PIN
var account_mode := false # 클라이언트: 접속한 서버가 계정 서버


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_lost)


func online() -> bool:
	return mode != "offline"


func is_server() -> bool:
	return mode == "host" or mode == "server"


func is_client() -> bool:
	return mode == "client"


func my_id() -> int:
	return multiplayer.get_unique_id() if online() else 0


# 레이드 시작 권한: 호스트 본인, 전용 서버면 가장 먼저 들어온 사람
func leader() -> int:
	if mode == "host" or (mode == "client" and roster.has(1)):
		return 1
	var ids := roster.keys()
	ids.sort()
	return ids[0] if ids.size() else 0


func is_leader() -> bool:
	return online() and my_id() == leader()


func _set_status(t: String) -> void:
	status = t
	status_changed.emit(t)
	print("[net] ", t)


# ------------------------------------------------------------------ 접속
func host(port: int, pname: String, dedicated := false, accounts_dir := "") -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return "포트 %d 을(를) 열 수 없습니다 (이미 사용 중?)" % port
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	mode = "server" if dedicated else "host"
	my_name = pname
	roster = {}
	peer_acct = {}
	accounts = AccountStore.new(accounts_dir) if accounts_dir != "" else null
	if accounts != null:
		print("[net] 계정 DB: ", accounts_dir)
	if not dedicated:
		roster[1] = {"name": pname, "cls": SaveData.data.cls, "state": "lobby"}
	_set_status("포트 %d 에서 %s 대기 중" % [port, "전용 서버" if dedicated else "호스트"])
	roster_changed.emit()
	return ""


func join(address: String, port: int, pname: String, pin_code := "") -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return "접속을 시작할 수 없습니다"
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	mode = "client"
	my_name = pname
	pin = pin_code
	roster = {}
	_set_status("%s:%d 에 접속 중..." % [address, port])
	return ""


func leave() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var was := mode
	mode = "offline"
	roster = {}
	preparing = false
	account_mode = false
	if accounts != null:
		for id in peer_acct:
			accounts.unload(peer_acct[id])
	peer_acct = {}
	SaveData.leave_account()
	if was != "offline":
		_set_status("오프라인")
		roster_changed.emit()


func _on_connected() -> void:
	_set_status("접속 완료 - 호스트가 레이드를 시작하길 기다리는 중")
	hello.rpc_id(1, my_name, SaveData.data.cls, VERSION, pin)


func _on_failed() -> void:
	leave()
	_set_status("접속 실패 (주소/포트/방화벽을 확인하세요)")
	disconnected.emit("접속 실패")


func _on_server_lost() -> void:
	leave()
	_set_status("호스트와 연결이 끊겼습니다")
	disconnected.emit("호스트와 연결이 끊겼습니다")


func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	if not is_server():
		return
	var nm: String = roster.get(id, {}).get("name", "?")
	if game != null and is_instance_valid(game):
		game.on_peer_left(id) # 계정 결과(사망) 반영 후 정리
	roster.erase(id)
	loadouts.erase(id)
	if peer_acct.has(id):
		accounts.unload(peer_acct[id])
		peer_acct.erase(id)
	_set_status("%s 님이 나갔습니다" % nm)
	push_roster()


# ------------------------------------------------------------------ 대기실
@rpc("any_peer", "reliable")
func hello(pname: String, cls: String, ver: String, pin_code: String) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if ver != VERSION:
		kicked.rpc_id(id, "게임 버전이 다릅니다 (서버 %s). 최신 버전으로 업데이트하세요" % VERSION)
		return
	var nm := pname.strip_edges().left(16)
	if nm == "":
		nm = "모험가%d" % (roster.size() + 1)
	if accounts != null:
		# 온라인 서버: 이름 + PIN 으로 로그인 (없으면 새 계정)
		for other in peer_acct:
			if AccountStore.key_of(peer_acct[other]) == AccountStore.key_of(nm):
				kicked.rpc_id(id, "이미 접속 중인 계정입니다")
				return
		var r := accounts.login(nm, pin_code)
		if not r.ok:
			kicked.rpc_id(id, r.msg)
			return
		nm = r.name
		peer_acct[id] = nm
		cls = r.data.cls
		account_sync.rpc_id(id, nm, r.data, {"msg": "새 계정을 만들었습니다 (서버에 저장됩니다)" if r.created else "%s 계정으로 로그인했습니다" % nm})
	elif not Data.CLASSES.has(cls):
		cls = "fighter"
	roster[id] = {"name": nm, "cls": cls, "state": "lobby"}
	_set_status("%s 님이 들어왔습니다" % nm)
	push_roster()


@rpc("authority", "reliable")
func kicked(reason: String) -> void:
	leave()
	_set_status(reason)
	disconnected.emit(reason)


func push_roster() -> void:
	if not is_server():
		return
	set_roster.rpc(roster, pvp)
	roster_changed.emit()


@rpc("authority", "reliable")
func set_roster(r: Dictionary, pvp_flag: bool) -> void:
	roster = r
	pvp = pvp_flag
	roster_changed.emit()


# 로비에서 직업을 바꾸면 대기실 목록에 반영
func update_class(cls: String) -> void:
	if account_mode:
		return # 계정 서버는 select_class 조작으로 반영
	if mode == "host":
		if roster.has(1):
			roster[1].cls = cls
			push_roster()
	elif mode == "client":
		set_class.rpc_id(1, cls)


@rpc("any_peer", "reliable")
func set_class(cls: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and accounts == null and roster.has(id) and Data.CLASSES.has(cls):
		roster[id].cls = cls
		push_roster()


func set_pvp(v: bool) -> void:
	if is_server():
		pvp = v
		push_roster()


func raid_running() -> bool:
	for id in roster:
		if roster[id].state == "raid":
			return true
	return game != null and is_instance_valid(game) and is_server()


# ------------------------------------------------------------------ 레이드 시작
# 리더가 시작 요청 -> 서버가 모두에게 장비 제출 요청 -> 모이면 레이드 생성 -> 각자에게 시작 정보
func request_start(local_loadout = null) -> void:
	if is_server():
		server_prepare(local_loadout)
	elif is_client():
		req_start.rpc_id(1)


@rpc("any_peer", "reliable")
func req_start() -> void:
	if is_server() and multiplayer.get_remote_sender_id() == leader():
		server_prepare(null)


func server_prepare(local_loadout) -> void:
	if preparing or raid_running():
		return
	if accounts != null:
		# 온라인 서버: 서버가 각 계정에서 직접 장비를 꺼낸다 (클라이언트가 보낸 장비를 믿지 않음)
		loadouts = {}
		for id in roster:
			if roster[id].state == "lobby" and peer_acct.has(id):
				var d: Dictionary = accounts.get_data(peer_acct[id])
				loadouts[id] = Account.take_loadout(d)
				accounts.save(peer_acct[id])
				_sync_account(id, {})
		_begin()
		return
	preparing = true
	loadouts = {}
	if mode == "host" and local_loadout != null:
		loadouts[1] = local_loadout
	prepare_left = 5.0
	for id in roster:
		if id != 1 or mode == "server":
			prepare.rpc_id(id)
	_set_status("레이드 준비 중...")
	_check_prepared()


@rpc("authority", "reliable")
func prepare() -> void:
	prepare_received.emit()


func send_loadout(lo: Dictionary) -> void:
	submit_loadout.rpc_id(1, lo)


@rpc("any_peer", "reliable")
func submit_loadout(lo: Dictionary) -> void:
	if not is_server() or not preparing:
		return
	var id := multiplayer.get_remote_sender_id()
	if not roster.has(id) or not Data.CLASSES.has(lo.get("cls", "")):
		return
	loadouts[id] = lo
	_check_prepared()


func _check_prepared() -> void:
	for id in roster:
		if not loadouts.has(id):
			return
	_begin()


func _process(dt: float) -> void:
	if preparing:
		prepare_left -= dt
		if prepare_left <= 0.0:
			_begin()


func _begin() -> void:
	preparing = false
	if loadouts.is_empty():
		_set_status("참가자가 없습니다")
		return
	for id in loadouts:
		if roster.has(id):
			roster[id].state = "raid"
	push_roster()
	server_begin.emit(loadouts)
	loadouts = {}


func send_begin(id: int, info: Dictionary) -> void:
	if _alive(id):
		begin.rpc_id(id, info)


@rpc("authority", "reliable")
func begin(info: Dictionary) -> void:
	begin_received.emit(info)


# 플레이어 한 명의 레이드가 끝남 (탈출/사망)
func player_left_raid(id: int) -> void:
	if roster.has(id):
		roster[id].state = "lobby"
		push_roster()


func raid_finished() -> void:
	for id in roster:
		roster[id].state = "lobby"
	_set_status("레이드 종료 - 대기실")
	push_roster()


# ------------------------------------------------------------------ 레이드 중 (클라이언트 -> 서버)
func send_input(p: Vector3, yaw: float, pitch: float, bits: int, can_act: bool, panel: bool) -> void:
	c_input.rpc_id(1, p, yaw, pitch, bits, can_act, panel)


@rpc("any_peer", "unreliable_ordered", "call_remote", 1)
func c_input(p: Vector3, yaw: float, pitch: float, bits: int, can_act: bool, panel: bool) -> void:
	if is_server() and game != null:
		game.net_input(multiplayer.get_remote_sender_id(), p, yaw, pitch, bits, can_act, panel)


func send_press(action: String) -> void:
	c_press.rpc_id(1, action)


@rpc("any_peer", "reliable")
func c_press(action: String) -> void:
	if is_server() and game != null:
		game.net_press(multiplayer.get_remote_sender_id(), action)


func send_inv(op: String, args: Array) -> void:
	c_inv.rpc_id(1, op, args)


@rpc("any_peer", "reliable")
func c_inv(op: String, args: Array) -> void:
	if is_server() and game != null:
		game.net_inv(multiplayer.get_remote_sender_id(), op, args)


# ------------------------------------------------------------------ 레이드 중 (서버 -> 클라이언트)
# 끊긴 피어에게 보내지 않도록
func _alive(id: int) -> bool:
	return multiplayer.get_peers().has(id)


func send_snap(id: int, w: Dictionary, me: Dictionary) -> void:
	if _alive(id):
		s_snap.rpc_id(id, w, me)


@rpc("authority", "unreliable_ordered", "call_remote", 2)
func s_snap(w: Dictionary, me: Dictionary) -> void:
	if game != null and is_instance_valid(game):
		game.net_snapshot(w, me)


func send_projs(id: int, pr: PackedFloat32Array) -> void:
	if _alive(id):
		s_projs.rpc_id(id, pr)


@rpc("authority", "unreliable_ordered", "call_remote", 3)
func s_projs(pr: PackedFloat32Array) -> void:
	if game != null and is_instance_valid(game):
		game.net_projs(pr)


func send_acts(id: int, acts: PackedFloat32Array) -> void:
	if _alive(id):
		s_acts.rpc_id(id, acts)


@rpc("authority", "unreliable_ordered", "call_remote", 2)
func s_acts(acts: PackedFloat32Array) -> void:
	if game != null and is_instance_valid(game):
		game.net_actor_chunk(acts)


func send_ev(id: int, n: String, args: Array, reliable := true) -> void:
	if not _alive(id):
		return
	if reliable:
		s_ev.rpc_id(id, n, args)
	else:
		s_evu.rpc_id(id, n, args)


@rpc("authority", "reliable")
func s_ev(n: String, args: Array) -> void:
	if game != null and is_instance_valid(game):
		game.net_event(n, args)


@rpc("authority", "unreliable")
func s_evu(n: String, args: Array) -> void:
	if game != null and is_instance_valid(game):
		game.net_event(n, args)


# ------------------------------------------------------------------ 온라인 서버 계정
func _sync_account(id: int, res: Dictionary) -> void:
	if peer_acct.has(id) and _alive(id):
		account_sync.rpc_id(id, peer_acct[id], accounts.get_data(peer_acct[id]), res)


@rpc("authority", "reliable")
func account_sync(nm: String, d: Dictionary, res: Dictionary) -> void:
	account_mode = true
	SaveData.use_account(nm, d)
	SaveData.show_result(res)


# 클라이언트: 로비 조작을 서버로
func account_op(op: String, args: Array) -> void:
	if is_client():
		c_account_op.rpc_id(1, op, args)


@rpc("any_peer", "reliable")
func c_account_op(op: String, args: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or accounts == null or not peer_acct.has(id) or not roster.has(id):
		return
	if roster[id].state == "raid" or op.length() > 32 or args.size() > 4:
		return
	var nm: String = peer_acct[id]
	var d: Dictionary = accounts.get_data(nm)
	var res := Account.apply(d, op, args)
	if res.ok:
		accounts.save(nm)
		if op == "select_class":
			roster[id].cls = d.cls
			push_roster()
	_sync_account(id, res)


# 서버: 레이드 결과를 계정에 반영 (탈출 전리품 / 사망 손실)
func on_player_result(id: int, r: Dictionary) -> void:
	if accounts == null or not peer_acct.has(id):
		return
	var d: Dictionary = accounts.get_data(peer_acct[id])
	var msg := Account.apply_result(d, r)
	accounts.save(peer_acct[id])
	_sync_account(id, {"msg": msg})
