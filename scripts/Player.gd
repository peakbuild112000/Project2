extends Node3D
class_name ChameleonAvatar

## Low-poly chameleon avatar used for the local player, remote players and
## practice bots. Visibility can be faded for a hunter's point of view so a
## well-camouflaged hider is genuinely hard to spot.

var player_id: int = 1
var player_name: String = "PLAYER"
var is_local: bool = false

var _body_mat: StandardMaterial3D
var _accent_mat: StandardMaterial3D
var _tail_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _pupil_mat: StandardMaterial3D
var _name_label: Label3D
var _tail: Array[MeshInstance3D] = []
var _feet: Array[MeshInstance3D] = []
var _spot: SpotLight3D
var _crown: Node3D
var _color_index: int = 0
var _time: float = 0.0
var _target_pos: Vector3 = Vector3.ZERO
var _visible_alpha: float = 1.0
var _dead: bool = false


func setup(id: int, pname: String, local: bool) -> void:
	player_id = id
	player_name = pname
	is_local = local
	_build()


func _mat(color: Color, emission: float = 0.4) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 1.0)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = emission
	mat.roughness = 0.4
	mat.metallic = 0.12
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	return mat


func _mesh(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build() -> void:
	_body_mat = _mat(GameState.color_for(0), 0.55)
	_accent_mat = _mat(GameState.color_for(0) * 0.55, 0.25)
	_tail_mat = _mat(GameState.color_for(0), 0.5)
	_eye_mat = _mat(Color(1, 1, 1), 0.2)
	_pupil_mat = _mat(Color(0.02, 0.02, 0.05), 0.0)

	var capsule := CapsuleMesh.new()
	capsule.radius = 0.42
	capsule.height = 1.1
	capsule.radial_segments = 16
	_mesh(capsule, _body_mat, Vector3(0, 0.82, 0))

	var head := SphereMesh.new()
	head.radius = 0.52
	head.height = 1.04
	head.radial_segments = 18
	var head_mi := _mesh(head, _body_mat, Vector3(0, 1.45, -0.22))
	head_mi.scale = Vector3(1.12, 0.92, 1.0)

	var snout := SphereMesh.new()
	snout.radius = 0.28
	snout.height = 0.56
	snout.radial_segments = 12
	var snout_mi := _mesh(snout, _body_mat, Vector3(0, 1.26, -0.6))
	snout_mi.scale = Vector3(1.2, 0.7, 0.8)

	for side in [-1.0, 1.0]:
		var eye := SphereMesh.new()
		eye.radius = 0.21
		eye.height = 0.42
		eye.radial_segments = 14
		_mesh(eye, _eye_mat, Vector3(side * 0.33, 1.63, -0.52))
		var pupil := SphereMesh.new()
		pupil.radius = 0.095
		pupil.height = 0.19
		_mesh(pupil, _pupil_mat, Vector3(side * 0.35, 1.63, -0.69))

	for i in 3:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.11
		cone.height = 0.27
		cone.radial_segments = 8
		_mesh(cone, _accent_mat, Vector3(0, 1.95 - i * 0.03, -0.12 + i * 0.2))

	for x in [-0.32, 0.32]:
		for z in [-0.25, 0.38]:
			var foot := BoxMesh.new()
			foot.size = Vector3(0.22, 0.14, 0.36)
			_feet.append(_mesh(foot, _accent_mat, Vector3(x, 0.1, z)))

	for i in 6:
		var seg := SphereMesh.new()
		seg.radius = 0.19 - i * 0.022
		seg.height = seg.radius * 2.0
		seg.radial_segments = 10
		_tail.append(_mesh(seg, _tail_mat, Vector3(0, 0.66 + i * 0.08, 0.44 + i * 0.25)))

	_name_label = Label3D.new()
	_name_label.text = player_name
	_name_label.font_size = 34
	_name_label.pixel_size = 0.007
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.outline_size = 8
	_name_label.outline_modulate = Color(0, 0, 0, 0.9)
	_name_label.modulate = Color(1, 1, 1, 0.95)
	_name_label.position = Vector3(0, 2.45, 0)
	add_child(_name_label)

	_crown = Node3D.new()
	add_child(_crown)
	var crown_ring := TorusMesh.new()
	crown_ring.inner_radius = 0.28
	crown_ring.outer_radius = 0.36
	crown_ring.ring_segments = 20
	var gold := _mat(Color(1.0, 0.78, 0.15), 1.6)
	_mesh(crown_ring, gold, Vector3(0, 2.12, -0.2), _crown)
	for i in 5:
		var spike := CylinderMesh.new()
		spike.top_radius = 0.0
		spike.bottom_radius = 0.06
		spike.height = 0.22
		var a: float = TAU * float(i) / 5.0
		_mesh(spike, gold, Vector3(cos(a) * 0.32, 2.28, -0.2 + sin(a) * 0.32), _crown)
	_crown.visible = false

	_spot = SpotLight3D.new()
	_spot.light_color = Color(1.0, 0.96, 0.8)
	_spot.light_energy = 0.0
	_spot.spot_range = 18.0
	_spot.spot_angle = 24.0
	_spot.spot_angle_attenuation = 0.35
	_spot.position = Vector3(0, 1.4, -0.6)
	add_child(_spot)


func set_color(index: int) -> void:
	if index == _color_index and _body_mat != null:
		return
	_color_index = wrapi(index, 0, 4)
	var c: Color = GameState.color_for(_color_index)
	for mat in [_body_mat, _tail_mat]:
		mat.albedo_color = Color(c.r, c.g, c.b, mat.albedo_color.a)
		mat.emission = c
	_accent_mat.albedo_color = Color(c.r * 0.55, c.g * 0.55, c.b * 0.55, _accent_mat.albedo_color.a)
	_accent_mat.emission = c * 0.6


func set_hunter(is_hunter: bool) -> void:
	_crown.visible = is_hunter
	_name_label.modulate = Color(1, 0.85, 0.3, 0.98) if is_hunter else Color(1, 1, 1, 0.92)


func set_flashlight(on: bool) -> void:
	if _spot != null:
		_spot.light_energy = 7.0 if on else 0.0


func set_dead(dead: bool) -> void:
	_dead = dead
	visible = not dead


func update_visual(delta: float, state: Dictionary, viewer_role: String, viewer_id: int, flashlight_on: bool, viewer_pos: Vector3) -> void:
	if state.is_empty() or _body_mat == null:
		return
	_time += delta
	_target_pos = Vector3(float(state.get("x", 0.0)), 0.0, float(state.get("z", 0.0)))
	global_position = global_position.lerp(_target_pos, clampf(delta * 18.0, 0.0, 1.0))
	var target_yaw: float = float(state.get("yaw", 0.0))
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 12.0, 0.0, 1.0))
	set_color(int(state.get("color", 0)))
	set_hunter(str(state.get("role", "hider")) == "hunter")
	set_dead(not bool(state.get("alive", true)))
	if _dead:
		return

	var speed: float = float(state.get("speed", 0.0))
	for i in _feet.size():
		_feet[i].position.y = 0.1 + maxf(0.0, sin(_time * 12.0 + i * PI)) * 0.07 * clampf(speed / 4.0, 0.0, 1.0)
	for i in _tail.size():
		_tail[i].position.x = sin(_time * 6.0 - i * 0.5) * 0.07

	var alpha: float = 1.0
	var is_hider: bool = str(state.get("role", "hider")) == "hider"
	if viewer_role == "hunter" and is_hider and player_id != viewer_id:
		var hide: float = clampf(float(state.get("hide", 0.0)), 0.0, 1.0)
		var dist: float = global_position.distance_to(viewer_pos)
		alpha = 0.12 + (1.0 - hide) * 0.88
		if flashlight_on:
			alpha = maxf(alpha, 0.65)
		if dist < 4.5:
			alpha = maxf(alpha, 0.8)
		alpha = clampf(alpha, 0.08, 1.0)
	_visible_alpha = lerp(_visible_alpha, alpha, clampf(delta * 10.0, 0.0, 1.0))
	for mat in [_body_mat, _accent_mat, _tail_mat, _eye_mat, _pupil_mat]:
		mat.albedo_color.a = _visible_alpha
	_name_label.modulate.a = _visible_alpha * (0.95 if is_local else 0.8)
	if _spot != null:
		_spot.light_energy = 7.0 if (str(state.get("role", "")) == "hunter" and flashlight_on) else 0.0
