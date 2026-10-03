# 끌어다 놓는 구역 (상인 판매대)
class_name DropZone
extends PanelContainer

var on_op: Callable
var drop_outside := false


func _enter_tree() -> void:
	InvDrag.register(self)


func _exit_tree() -> void:
	InvDrag.unregister(self)


func drop_target(_gp: Vector2, d) -> Dictionary:
	if d.src == "equip":
		return {}
	return {"dst": "sell"}
