extends Node3D
class_name Arena

## Builds one of the three textured maps from the deterministic layout.

var layout: Dictionary = {}
var theme: Dictionary = {}
var prop_materials: Array[StandardMaterial3D] = []

var _floor: MeshInstance3D
var _we: WorldEnvironment


func clear_arena() -> void:
	for child in get_children():
		child.queue_free()
	prop_materials.clear()


func build(new_layout: Dictionary) -> void:
	clear_arena()
	layout = new_layout
	theme = ArenaData.theme(int(layout.get("map", 0)))

	_setup_environment()
	_setup_lights()
	_setup_floor()
	_setup_walls()
	_setup_props()
	_setup_details()


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = theme["bg"]
	env.fog_enabled = true
	env.fog_light_color = theme["fog"]
	env.fog_density = 0.021
	env.glow_enabled = true
	env.glow_intensity = float(theme["glow"])
	env.glow_bloom = 0.28
	env.glow_hdr_threshold = 0.85
	_we = WorldEnvironment.new()
	_we.environment = env
	add_child(_we)


func _setup_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_color = theme["light"]
	sun.light_energy = 1.35
	sun.rotation_degrees = Vector3(-48, 32, 0)
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.4, 0.55, 1.0)
	fill.light_energy = 0.45
	fill.rotation_degrees = Vector3(-25, -140, 0)
	add_child(fill)


func _textured_material(path: String, tint: Color, tile: Vector3, emission: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var tex: Texture2D = load(path)
	if tex != null:
		mat.albedo_texture = tex
	mat.albedo_color = tint
	mat.uv1_scale = tile
	mat.roughness = 0.72
	mat.metallic = 0.05
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = tint
		mat.emission_energy_multiplier = emission
	return mat


func _setup_floor() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(34, 34)
	var mat := _textured_material(str(theme["floor"]), Color(1, 1, 1), Vector3(9, 9, 1))
	mat.roughness = 0.55
	mat.metallic = 0.18
	_floor = MeshInstance3D.new()
	_floor.mesh = mesh
	_floor.material_override = mat
	add_child(_floor)

	# Center emblem so players have a visual anchor.
	var ring := TorusMesh.new()
	ring.inner_radius = 3.4
	ring.outer_radius = 3.6
	ring.ring_segments = 48
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.2, 0.9, 1.0)
	rmat.emission_enabled = true
	rmat.emission = Color(0.2, 0.9, 1.0)
	rmat.emission_energy_multiplier = 1.2
	var ri := MeshInstance3D.new()
	ri.mesh = ring
	ri.material_override = rmat
	ri.position.y = 0.035
	add_child(ri)


func _setup_walls() -> void:
	var wall_mat := _textured_material(str(theme["wall"]), Color(0.8, 0.85, 1.0), Vector3(8, 2, 1))
	var h: float = 5.0
	var specs := [
		[Vector3(0, h * 0.5, -ArenaData.ARENA_HALF), Vector3(34, h, 0.8)],
		[Vector3(0, h * 0.5, ArenaData.ARENA_HALF), Vector3(34, h, 0.8)],
		[Vector3(-ArenaData.ARENA_HALF, h * 0.5, 0), Vector3(0.8, h, 34)],
		[Vector3(ArenaData.ARENA_HALF, h * 0.5, 0), Vector3(0.8, h, 34)],
	]
	for s in specs:
		var box := BoxMesh.new()
		box.size = s[1]
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = wall_mat
		mi.position = s[0]
		add_child(mi)

	# Glowing top rails in the four palette colors.
	var colors := GameState.PALETTE
	for i in 4:
		var stripe := BoxMesh.new()
		stripe.size = Vector3(34, 0.09, 0.12)
		var smat := StandardMaterial3D.new()
		smat.albedo_color = colors[i]
		smat.emission_enabled = true
		smat.emission = colors[i]
		smat.emission_energy_multiplier = 2.0
		var smi := MeshInstance3D.new()
		smi.mesh = stripe
		smi.material_override = smat
		smi.position = Vector3(0, 4.85, -ArenaData.ARENA_HALF + i * 0.0)
		smi.position.z = -ArenaData.ARENA_HALF + 0.1 + i * 0.12
		add_child(smi)


func _setup_props() -> void:
	for prop in layout.get("props", []):
		var w: float = float(prop["w"])
		var h: float = float(prop["h"])
		var d: float = float(prop["d"])
		var c: int = int(prop["c"])
		var tint: Color = GameState.color_for(c)
		var mat := _textured_material(str(theme["wall"]), tint * 0.85, Vector3(2, 2, 2), 0.28)
		prop_materials.append(mat)
		var box := BoxMesh.new()
		box.size = Vector3(w, h, d)
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = mat
		mi.position = Vector3(float(prop["x"]), h * 0.5, float(prop["z"]))
		mi.rotation.y = float(prop["rot"])
		add_child(mi)

		var cap := BoxMesh.new()
		cap.size = Vector3(w * 0.96, 0.06, d * 0.96)
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = tint
		cmat.emission_enabled = true
		cmat.emission = tint
		cmat.emission_energy_multiplier = 1.5
		var cmi := MeshInstance3D.new()
		cmi.mesh = cap
		cmi.material_override = cmat
		cmi.position = Vector3(float(prop["x"]), h + 0.04, float(prop["z"]))
		cmi.rotation.y = float(prop["rot"])
		add_child(cmi)


func _setup_details() -> void:
	# Floating neon motes give the arena depth.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(layout.get("seed", 1))
	var mote_mesh := SphereMesh.new()
	mote_mesh.radius = 0.045
	mote_mesh.height = 0.09
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.95, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.95, 1.0)
	mat.emission_energy_multiplier = 2.0
	for i in 90:
		var mi := MeshInstance3D.new()
		mi.mesh = mote_mesh
		mi.material_override = mat
		mi.position = Vector3(rng.randf_range(-16, 16), rng.randf_range(0.4, 4.6), rng.randf_range(-16, 16))
		add_child(mi)


func move_with_collision(pos: Vector3, delta: Vector3) -> Vector3:
	var attempt: Vector3 = ArenaData.clamp_position(pos + Vector3(delta.x, 0, 0))
	if not ArenaData.collides(attempt, layout):
		pos = attempt
	attempt = ArenaData.clamp_position(pos + Vector3(0, 0, delta.z))
	if not ArenaData.collides(attempt, layout):
		pos = attempt
	return pos


func spawn_for(index: int) -> Vector3:
	var spawns: Array = layout.get("spawns", [])
	if spawns.is_empty():
		return Vector3.ZERO
	return ArenaData.clamp_position(spawns[index % spawns.size()])
