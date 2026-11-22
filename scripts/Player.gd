extends Node3D
class_name HumanAvatar

## A small low-poly human figure. Everyone joins as a clean white mannequin,
## then paints their suit to match the colored crates around the arena.
## The host sends a hide value with every snapshot; we use it to fade figures
## from the hunter's point of view when they are properly camouflaged.

var player_id: int = 1
var player_name: String = "PLAYER"
var is_local: bool = false

# Materials are kept as fields so a color change or a camouflage fade only
# touches a handful of objects instead of rebuilding the character.
var _suit_mat: StandardMaterial3D
var _trim_mat: StandardMaterial3D
var _skin_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _pupil_mat: StandardMaterial3D

var _torso: MeshInstance3D
var _arms: Array[MeshInstance3D] = []
var _legs: Array[MeshInstance3D] = []
var _name_label: Label3D
var _flashlight: SpotLight3D
var _crown: Node3D

var _color_index: int = GameState.WHITE
var _time: float = 0.0
var _visible_alpha: float = 1.0
var _splash: float = 0.0
var _dead: bool = false


func setup(id: int, pname: String, local: bool) -> void:
	player_id = id
	player_name = pname
	is_local = local
	_build()


func _make_material(color: Color, emission: float = 0.15) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 1.0)
	mat.emission_enabled = emission > 0.0
	mat.emission = color
	mat.emission_energy_multiplier = emission
	mat.roughness = 0.45
	mat.metallic = 0.08
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	return mat


func _add_mesh(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = mat
	part.position = pos
	parent.add_child(part)
	return part


func _build() -> void:
	var white: Color = GameState.color_for(GameState.WHITE)
	_suit_mat = _make_material(white, 0.04)
	_trim_mat = _make_material(Color(0.72, 0.74, 0.8), 0.03)
	_skin_mat = _make_material(Color(1.0, 0.86, 0.74), 0.02)
	_eye_mat = _make_material(Color(1, 1, 1), 0.1)
	_pupil_mat = _make_material(Color(0.04, 0.05, 0.09), 0.0)

	# Torso and hips.
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.34
	torso_mesh.height = 0.95
	torso_mesh.radial_segments = 14
	_torso = _add_mesh(torso_mesh, _suit_mat, Vector3(0, 1.24, 0))
	_torso.scale = Vector3(1.0, 1.0, 0.78)

	var hips := BoxMesh.new()
	hips.size = Vector3(0.62, 0.28, 0.36)
	_add_mesh(hips, _trim_mat, Vector3(0, 0.78, 0))

	# Head, face and a simple hair cap.
	var head := SphereMesh.new()
	head.radius = 0.34
	head.height = 0.68
	head.radial_segments = 18
	_add_mesh(head, _skin_mat, Vector3(0, 1.92, -0.02))

	var hair := SphereMesh.new()
	hair.radius = 0.35
	hair.height = 0.7
	hair.radial_segments = 18
	var hair_part := _add_mesh(hair, _trim_mat, Vector3(0, 2.0, 0.02))
	hair_part.scale = Vector3(1.02, 0.62, 1.02)

	for side in [-1.0, 1.0]:
		var eye := SphereMesh.new()
		eye.radius = 0.075
		eye.height = 0.15
		_add_mesh(eye, _eye_mat, Vector3(side * 0.13, 1.96, -0.31))
		var pupil := SphereMesh.new()
		pupil.radius = 0.035
		pupil.height = 0.07
		_add_mesh(pupil, _pupil_mat, Vector3(side * 0.13, 1.96, -0.37))

	# Arms and hands. We keep references so they can swing while walking.
	for side in [-1.0, 1.0]:
		var arm := CylinderMesh.new()
		arm.top_radius = 0.09
		arm.bottom_radius = 0.075
		arm.height = 0.72
		arm.radial_segments = 10
		var arm_part := _add_mesh(arm, _suit_mat, Vector3(side * 0.48, 1.25, 0))
		arm_part.rotation.z = side * 0.12
		_arms.append(arm_part)

		var hand := SphereMesh.new()
		hand.radius = 0.11
		hand.height = 0.22
		_add_mesh(hand, _skin_mat, Vector3(side * 0.54, 0.86, 0))

	# Legs and shoes.
	for side in [-1.0, 1.0]:
		var leg := CylinderMesh.new()
		leg.top_radius = 0.13
		leg.bottom_radius = 0.11
		leg.height = 0.78
		leg.radial_segments = 10
		_legs.append(_add_mesh(leg, _suit_mat, Vector3(side * 0.19, 0.42, 0)))

		var shoe := BoxMesh.new()
		shoe.size = Vector3(0.23, 0.13, 0.38)
		_add_mesh(shoe, _trim_mat, Vector3(side * 0.19, 0.07, -0.08))

	_name_label = Label3D.new()
	_name_label.text = player_name
	_name_label.font_size = 34
	_name_label.pixel_size = 0.007
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.outline_size = 8
	_name_label.outline_modulate = Color(0, 0, 0, 0.9)
	_name_label.modulate = Color(1, 1, 1, 0.95)
	_name_label.position = Vector3(0, 2.75, 0)
	add_child(_name_label)

	# Only the hunter wears a crown and carries a spotlight.
	_crown = Node3D.new()
	add_child(_crown)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.28
	ring.outer_radius = 0.36
	ring.ring_segments = 20
	var gold := _make_material(Color(1.0, 0.78, 0.15), 1.2)
	_add_mesh(ring, gold, Vector3(0, 2.42, -0.02), _crown)
	for i in 5:
		var spike := CylinderMesh.new()
		spike.top_radius = 0.0
		spike.bottom_radius = 0.05
		spike.height = 0.2
		var angle: float = TAU * float(i) / 5.0
		_add_mesh(spike, gold, Vector3(cos(angle) * 0.32, 2.57, -0.02 + sin(angle) * 0.32), _crown)
	_crown.visible = false

	_flashlight = SpotLight3D.new()
	_flashlight.light_color = Color(1.0, 0.96, 0.8)
	_flashlight.light_energy = 0.0
	_flashlight.spot_range = 18.0
	_flashlight.spot_angle = 24.0
	_flashlight.spot_angle_attenuation = 0.35
	_flashlight.position = Vector3(0, 1.65, -0.45)
	add_child(_flashlight)


func set_color(index: int) -> void:
	var next: int = wrapi(index, 0, GameState.PALETTE.size())
	if next == _color_index and _suit_mat != null:
		return
	_color_index = next
	var c: Color = GameState.color_for(next)

	if next == GameState.WHITE:
		_trim_mat.albedo_color = Color(0.72, 0.74, 0.8, 1.0)
		_trim_mat.emission = Color(0.72, 0.74, 0.8)
	else:
		_trim_mat.albedo_color = Color(c.r * 0.55, c.g * 0.55, c.b * 0.55, 1.0)
		_trim_mat.emission = c * 0.6

	_suit_mat.albedo_color = Color(c.r, c.g, c.b, _suit_mat.albedo_color.a)
	_suit_mat.emission = c
	_suit_mat.emission_energy_multiplier = 0.04 if next == GameState.WHITE else 0.35


func paint_splash() -> void:
	# A tiny pop when the player picks a paint color. Purely cosmetic.
	_splash = 1.0


func set_hunter(is_hunter: bool) -> void:
	_crown.visible = is_hunter
	_name_label.modulate = Color(1, 0.85, 0.3, 0.98) if is_hunter else Color(1, 1, 1, 0.92)


func set_flashlight(on: bool) -> void:
	if _flashlight != null:
		_flashlight.light_energy = 7.0 if on else 0.0


func set_dead(dead: bool) -> void:
	_dead = dead
	visible = not dead


func update_visual(delta: float, state: Dictionary, viewer_role: String, viewer_id: int, flashlight_on: bool, viewer_pos: Vector3) -> void:
	if state.is_empty() or _suit_mat == null:
		return

	_time += delta
	var target := Vector3(float(state.get("x", 0.0)), 0.0, float(state.get("z", 0.0)))
	global_position = global_position.lerp(target, clampf(delta * 18.0, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, float(state.get("yaw", 0.0)), clampf(delta * 12.0, 0.0, 1.0))

	set_color(int(state.get("color", GameState.WHITE)))
	set_hunter(str(state.get("role", "hider")) == "hunter")
	set_dead(not bool(state.get("alive", true)))
	if _dead:
		return

	_animate_walk(delta, float(state.get("speed", 0.0)))
	_apply_camouflage(delta, state, viewer_role, viewer_id, flashlight_on, viewer_pos)


func _animate_walk(delta: float, speed: float) -> void:
	var strength: float = clampf(speed / 4.5, 0.0, 1.0)
	var swing: float = sin(_time * 11.0) * 0.55 * strength
	for i in _arms.size():
		_arms[i].rotation.x = swing if i == 0 else -swing
	for i in _legs.size():
		_legs[i].rotation.x = -swing if i == 0 else swing

	if _splash > 0.0:
		_splash = maxf(0.0, _splash - delta * 3.5)
		var puff: float = 1.0 + sin(_splash * PI) * 0.12
		_torso.scale = Vector3(puff, 1.0, 0.78 * puff)
	else:
		_torso.scale = Vector3(1.0, 1.0, 0.78)


func _apply_camouflage(delta: float, state: Dictionary, viewer_role: String, viewer_id: int, flashlight_on: bool, viewer_pos: Vector3) -> void:
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

	_visible_alpha = lerp(_visible_alpha, clampf(alpha, 0.08, 1.0), clampf(delta * 10.0, 0.0, 1.0))
	for mat in [_suit_mat, _trim_mat, _skin_mat, _eye_mat, _pupil_mat]:
		mat.albedo_color.a = _visible_alpha
	_name_label.modulate.a = _visible_alpha * (0.95 if is_local else 0.8)
	_flashlight.light_energy = 7.0 if (str(state.get("role", "")) == "hunter" and flashlight_on) else 0.0
