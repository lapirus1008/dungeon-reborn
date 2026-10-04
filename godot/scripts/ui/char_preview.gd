# 3D 캐릭터 미리보기 (직업 선택 화면, 던전 인벤토리 가운데 창)
class_name CharPreview
extends SubViewportContainer

var vp: SubViewport
var pivot: Node3D
var rig: CharacterRig
var spin := true
var _key := ""


func _init(sz := Vector2(300, 340)) -> void:
	stretch = true
	custom_minimum_size = sz
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_2X
	vp.size = Vector2i(sz)
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.5, 0.48)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.position = Vector3(0, 1.15, 4.6)
	cam.look_at_from_position(cam.position, Vector3(0, 0.95, 0), Vector3.UP)
	vp.add_child(cam)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.6, 0.5, 0)
	key.light_energy = 1.3
	key.light_color = Color(1.0, 0.86, 0.7)
	vp.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.5, 2.2, -1.8)
	rim.light_color = Color(0.5, 0.6, 1.0)
	rim.light_energy = 1.4
	rim.omni_range = 6.0
	vp.add_child(rim)
	var floor_disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.9
	cm.bottom_radius = 0.9
	cm.height = 0.02
	floor_disc.mesh = cm
	floor_disc.material_override = Models.mat(Color(0.12, 0.1, 0.09))
	vp.add_child(floor_disc)
	pivot = Node3D.new()
	vp.add_child(pivot)


# 직업 / 들고 있는 무기 모델 / 투구 여부로 모델 교체 (같으면 그대로)
func set_char(cls: String, wmodel: String, helmet := true) -> void:
	var k := "%s|%s|%s" % [cls, wmodel, helmet]
	if k == _key:
		return
	_key = k
	for c in pivot.get_children():
		c.queue_free()
	rig = Models.hero_rig(cls, wmodel, helmet)
	pivot.add_child(rig.node)
	rig.node.rotation.y = PI # 정면이 카메라 쪽


func _process(dt: float) -> void:
	if not is_visible_in_tree() or rig == null:
		return
	if spin:
		pivot.rotation.y += dt * 0.5
	rig.animate(dt, {"move": 0.0, "windup": -1.0, "attack": -1.0, "aim": false, "block": false, "dead_t": -1.0, "cast": false, "spin": false})
