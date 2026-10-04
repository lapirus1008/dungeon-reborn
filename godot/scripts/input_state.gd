# 입력 추상화: 로컬 플레이어는 키보드/마우스, 원격 플레이어는 네트워크로 받은 입력
class_name InputState
extends RefCounted

# 네트워크로 보내는 "누르고 있는" 동작 (비트 순서 고정)
const HELD := ["move_forward", "move_back", "move_left", "move_right", "sprint", "attack", "secondary", "interact", "skill_q", "skill_e"]
# 한 번 누름 이벤트로 보내는 동작
const PRESS := ["attack", "secondary", "skill_q", "skill_e", "jump", "weapon1", "weapon2", "use3", "interact", "use4", "use5", "torch"]

var remote := false
var held := {}
var pending := {} # 다음 프레임에 처리할 눌림
var just := {}
var can_act := true # 마우스가 잡혀 있고 메뉴/패널이 닫힘
var panel := false # 인벤토리/전리품/메뉴 열림


func _init(is_remote := false) -> void:
	remote = is_remote


static func pack_held() -> int:
	var bits := 0
	for i in HELD.size():
		if InputMap.has_action(HELD[i]) and Input.is_action_pressed(HELD[i]):
			bits |= 1 << i
	return bits


func set_held_bits(bits: int) -> void:
	for i in HELD.size():
		held[HELD[i]] = (bits & (1 << i)) != 0


func push_press(action: String) -> void:
	pending[action] = true


# 원격 입력: 매 프레임 시작 시 쌓인 눌림을 이번 프레임의 just로 확정
func begin_frame() -> void:
	if remote:
		just = pending
		pending = {}


func pressed(action: String) -> bool:
	if not remote:
		return Input.is_action_pressed(action)
	return held.get(action, false) or just.get(action, false)


func just_pressed(action: String) -> bool:
	if not remote:
		return Input.is_action_just_pressed(action)
	return just.get(action, false)


func strength(action: String) -> float:
	if not remote:
		return Input.get_action_strength(action)
	return 1.0 if held.get(action, false) else 0.0
