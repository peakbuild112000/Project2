extends RefCounted
## Builds the original arena layouts from boxes and generated materials.
## Avatars carry a paintable ImageTexture (unlimited colours, brush strokes).

const AVATAR_TEX := 256

var root: Node3D
var props: Array = [] # each: {"pos": Vector3, "color": int}
var spawns: Array = []

func build(parent: Node3D, map_index: int) -> void:
	root = Node3D.new()
	parent.add_child(root)
	props.clear()
	spawns.clear()

	var cfg: Dictionary = Core.MAPS[map_index]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + map_index * 37

	var floor_mat := Core.material(cfg.floor, Core.texture(11 + map_index, cfg.floor, cfg.accent))
	floor_mat.set("uv1_scale", Vector3(14, 14, 14))
	var wall_mat := Core.material(cfg.wall, Core.texture(31 + map_index, cfg.wall, cfg.accent))
	wall_mat.set("uv1_scale", Vector3(8, 8, 8))

	# Larger arenas give hiders more places to break line of sight.
	_box(Vector3(0, -0.5, 0), Vector3(80, 1, 80), floor_mat)
	_box(Vector3(0, 3, -40), Vector3(80, 7, 1), wall_mat)
	_box(Vector3(0, 3, 40), Vector3(80, 7, 1), wall_mat)
	_box(Vector3(-40, 3, 0), Vector3(1, 7, 80), wall_mat)
	_box(Vector3(40, 3, 0), Vector3(1, 7, 80), wall_mat)

	var palette: Array = cfg.props
	# Crates: the classic solid hiding block.
	for i in range(int(cfg.get("crates", 48))):
		var c: int = palette[rng.randi() % palette.size()]
		var size := rng.randf_range(1.4, 3.2)
		var pos := Vector3(rng.randf_range(-32, 32), size * 0.5, rng.randf_range(-32, 32))
		_box(pos, Vector3(size, size, size), Core.material(Core.COLORS[c]))
		props.append({"pos": pos, "color": c})

	# Cylinders: round cover that breaks up the box silhouettes.
	for i in range(int(cfg.get("cylinders", 16))):
		var c: int = palette[rng.randi() % palette.size()]
		var pos := Vector3(rng.randf_range(-30, 30), 2.2, rng.randf_range(-30, 30))
		_cylinder(pos, 0.9, 4.4, Core.material(Core.COLORS[c]))
		props.append({"pos": pos, "color": c})

	# Low platforms: a hider can crouch behind these.
	for i in range(int(cfg.get("platforms", 9))):
		var c: int = palette[rng.randi() % palette.size()]
		var pos := Vector3(rng.randf_range(-27, 27), 0.8, rng.randf_range(-27, 27))
		_box(pos, Vector3(5.6, 0.7, 2.6), Core.material(Core.COLORS[c]))
		props.append({"pos": pos, "color": c})

	# Tall lockers: narrow vertical cover.
	for i in range(int(cfg.get("lockers", 12))):
		var c: int = palette[rng.randi() % palette.size()]
		var pos := Vector3(rng.randf_range(-31, 31), 2.35, rng.randf_range(-31, 31))
		_box(pos, Vector3(1.7, 4.7, 1.7), Core.material(Core.COLORS[c]))
		props.append({"pos": pos, "color": c})

	# Spheres: a different silhouette again.
	for i in range(int(cfg.get("spheres", 10))):
		var c: int = palette[rng.randi() % palette.size()]
		var radius := rng.randf_range(1.1, 2.1)
		var pos := Vector3(rng.randf_range(-30, 30), radius, rng.randf_range(-30, 30))
		_sphere(pos, radius, Core.material(Core.COLORS[c]))
		props.append({"pos": pos, "color": c})

	# Thin panels: maze-like partial walls.
	for i in range(int(cfg.get("panels", 10))):
		var c: int = palette[rng.randi() % palette.size()]
		var pos := Vector3(rng.randf_range(-29, 29), 1.75, rng.randf_range(-29, 29))
		_box(pos, Vector3(4.8, 3.5, 0.5), Core.material(Core.COLORS[c]))
		props.append({"pos": pos, "color": c})

	# Overhead Studio has a real ceiling, bright emissive panels and strong
	# downlights. A white suit + the FLAT emote blends into the lit floor.
	if bool(cfg.get("ceiling_lights", false)):
		_box(Vector3(0, 6.65, 0), Vector3(80, 0.3, 80), wall_mat)
		var light_mat := Core.material(Color.WHITE)
		light_mat.emission_enabled = true
		light_mat.emission = Color.WHITE
		light_mat.emission_energy = 3.0
		for x in [-24, -8, 8, 24]:
			for z in [-24, -8, 8, 24]:
				_box(Vector3(x, 6.34, z), Vector3(4.6, 0.12, 4.6), light_mat)
				var lamp := SpotLight3D.new()
				lamp.position = Vector3(x, 6.18, z)
				# Lights shine along local -Z; -90 degrees on X points down.
				lamp.rotation = Vector3(-PI * 0.5, 0, 0)
				root.add_child(lamp)
				lamp.spot_angle = deg_to_rad(68)
				lamp.spot_range = 24.0
				lamp.light_energy = 3.4
				lamp.shadow_enabled = false

	spawns = [
		Vector3(-34, 0.05, -34), Vector3(34, 0.05, -34),
		Vector3(-34, 0.05, 34), Vector3(34, 0.05, 34),
		Vector3(0, 0.05, -34), Vector3(0, 0.05, 34),
		Vector3(-34, 0.05, 0), Vector3(34, 0.05, 0),
	]

func destroy() -> void:
	if root != null and is_instance_valid(root):
		root.queue_free()
	root = null
	props.clear()
	spawns.clear()

## Per-hider shadow switch. The world sun keeps casting; only this suit opts
## out. Applied to every mesh part so emotes cannot restore a lost shadow.
func set_shadow(av: Dictionary, on: bool) -> void:
	var mode: int = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for p in av.get("parts", []):
		if p is MeshInstance3D:
			p.cast_shadow = mode

## How well a hider painted `color` blends at this position (0..1).
## Uses real colour distance, so any painted colour can match the decor.
func camo_at(pos: Vector3, color: Color) -> float:
	var best := 0.0
	for p in props:
		var pd: Dictionary = p
		var prop_col: Color = Core.COLORS[int(pd.color)]
		var d := pos.distance_to(Vector3(pd.pos.x, 0, pd.pos.z))
		if d >= 5.5:
			continue
		var diff := Vector4(color.r - prop_col.r, color.g - prop_col.g, color.b - prop_col.b, 0)
		var closeness: float = 1.0 - clampf(diff.length() / 1.25, 0.0, 1.0)
		var v := closeness * (1.0 - d / 5.5)
		if v > best:
			best = v
	return best

func spawn(i: int) -> Vector3:
	if spawns.is_empty():
		return Vector3(0, 0.05, 0)
	return spawns[i % spawns.size()]

func _box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	body.add_child(mesh)
	root.add_child(body)

func _cylinder(pos: Vector3, radius: float, height: float, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	mesh.mesh = cyl
	mesh.material_override = mat
	body.add_child(mesh)
	root.add_child(body)

func _sphere(pos: Vector3, radius: float, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	col.shape = shape
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = radius
	mesh.mesh = sph
	mesh.material_override = mat
	body.add_child(mesh)
	root.add_child(body)

## Simple generated rifle. Used both as a first-person viewmodel and as a
## prop attached to the hunter's avatar so other players can see it.
func make_gun(parent: Node3D) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	var metal := Core.material(Color(0.08, 0.10, 0.13))
	var stock := Core.material(Color(0.20, 0.14, 0.09))
	_gun_part(holder, Vector3(0.13, 0.13, 0.74), Vector3(0, 0, -0.30), metal)
	_gun_part(holder, Vector3(0.09, 0.09, 0.34), Vector3(0, 0.02, -0.82), metal)
	_gun_part(holder, Vector3(0.15, 0.22, 0.16), Vector3(0, -0.17, -0.06), stock)
	_gun_part(holder, Vector3(0.17, 0.10, 0.28), Vector3(0, 0.00, 0.20), stock)
	_gun_part(holder, Vector3(0.05, 0.05, 0.07), Vector3(0, 0.11, -0.88), metal)
	return holder

func _gun_part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)

## Low-poly human avatar with its own paintable texture.
## Each body part owns a distinct cell of a 3x2 UV atlas, so a stroke lands on
## the exact spot that was clicked instead of repeating on every limb.
## Returns {"node", "mat", "image", "texture"}.
const ATLAS_COLS := 3
const ATLAS_ROWS := 2

func make_avatar(parent: Node3D, color: Color, owner_id: int) -> Dictionary:
	var holder := Node3D.new()
	parent.add_child(holder)

	var img := Image.create(AVATAR_TEX, AVATAR_TEX, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.82
	mat.metallic = 0.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var parts: Array = []
	parts.append(_part(holder, BoxMesh.new(), Vector3(0.62, 0.78, 0.34), Vector3(0, 1.05, 0), mat, owner_id, 0))
	parts.append(_part(holder, SphereMesh.new(), Vector3(0.42, 0.42, 0.42), Vector3(0, 1.68, 0), mat, owner_id, 1))
	parts.append(_part(holder, BoxMesh.new(), Vector3(0.18, 0.66, 0.18), Vector3(-0.42, 1.02, 0), mat, owner_id, 2))
	parts.append(_part(holder, BoxMesh.new(), Vector3(0.18, 0.66, 0.18), Vector3(0.42, 1.02, 0), mat, owner_id, 3))
	parts.append(_part(holder, BoxMesh.new(), Vector3(0.22, 0.66, 0.22), Vector3(-0.17, 0.34, 0), mat, owner_id, 4))
	parts.append(_part(holder, BoxMesh.new(), Vector3(0.22, 0.66, 0.22), Vector3(0.17, 0.34, 0), mat, owner_id, 5))

	return {"node": holder, "mat": mat, "image": img, "texture": tex,
		"parts": parts, "pose": "none"}

## Applies a visual pose to an avatar. Poses are cosmetic only: the invisible
## paint colliders keep their original transforms so painting still lands on
## the right atlas cell.
func set_pose(av: Dictionary, pose: String) -> void:
	if av.get("pose", "none") == pose:
		return
	av.pose = pose
	var node: Node3D = av.node
	var parts: Array = av.get("parts", [])
	node.rotation = Vector3.ZERO
	node.scale = Vector3.ONE
	node.position = Vector3.ZERO
	for p in parts:
		p.rotation = Vector3.ZERO
		p.scale = Vector3.ONE
	match pose:
		"flat":
			# Lie just above the floor instead of sinking underneath it.
			node.scale = Vector3(1.45, 0.12, 1.45)
			node.position.y = -0.02
		"ball":
			node.scale = Vector3(0.80, 0.58, 0.80)
			node.position.y = -0.26
		"tall":
			node.scale = Vector3(0.68, 1.35, 0.68)
			node.position.y = 0.12
		"wave":
			if parts.size() > 3:
				parts[3].rotation.z = -2.3
		"prone":
			# Belly-down pose: the avatar lies along its local forward axis.
			node.rotation.x = -PI * 0.5
			node.position.y = 0.22

func _part(parent: Node3D, src: Mesh, size: Vector3, pos: Vector3, mat: Material, owner_id: int, part_index: int) -> MeshInstance3D:
	if src is BoxMesh:
		src.size = size
	elif src is SphereMesh:
		src.radius = size.x * 0.5

	var arrays: Array = src.surface_get_arrays(0).duplicate(true)
	var src_uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var atlas_uv := PackedVector2Array()
	var pad := 0.03
	for uv in src_uv:
		var u := pad + clampf(uv.x, 0.0, 1.0) * (1.0 - 2.0 * pad)
		var v := pad + clampf(uv.y, 0.0, 1.0) * (1.0 - 2.0 * pad)
		var col := part_index % ATLAS_COLS
		var row := int(part_index / ATLAS_COLS)
		atlas_uv.append(Vector2((float(col) + u) / float(ATLAS_COLS), (float(row) + v) / float(ATLAS_ROWS)))
	arrays[Mesh.ARRAY_TEX_UV] = atlas_uv

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)

	# Invisible collider on layer 2: the brush raycast hits this, the game shot
	# raycast (layer 1) never does, and it never blocks player movement.
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var faces := PackedVector3Array()
	var face_uvs := PackedVector2Array()
	for i in range(0, indices.size(), 3):
		for j in range(3):
			var vi: int = indices[i + j]
			faces.append(verts[vi])
			face_uvs.append(atlas_uv[vi])

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var collider := StaticBody3D.new()
	collider.position = pos
	collider.collision_layer = 2
	collider.collision_mask = 0
	collider.set_meta("owner_id", owner_id)
	collider.set_meta("faces", faces)
	collider.set_meta("face_uvs", face_uvs)
	collider.add_child(cs)
	parent.add_child(collider)
	return mi
