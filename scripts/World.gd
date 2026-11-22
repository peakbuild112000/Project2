extends RefCounted
## Builds the three original arena layouts from boxes and generated materials.
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
	floor_mat.set("uv1_scale", Vector3(9, 9, 9))
	var wall_mat := Core.material(cfg.wall, Core.texture(31 + map_index, cfg.wall, cfg.accent))
	wall_mat.set("uv1_scale", Vector3(5, 5, 5))

	_box(Vector3(0, -0.5, 0), Vector3(52, 1, 52), floor_mat)
	_box(Vector3(0, 3, -26), Vector3(52, 7, 1), wall_mat)
	_box(Vector3(0, 3, 26), Vector3(52, 7, 1), wall_mat)
	_box(Vector3(-26, 3, 0), Vector3(1, 7, 52), wall_mat)
	_box(Vector3(26, 3, 0), Vector3(1, 7, 52), wall_mat)

	var palette: Array = cfg.props
	for i in range(30):
		var c: int = palette[rng.randi() % palette.size()]
		var size := rng.randf_range(1.3, 2.8)
		var pos := Vector3(rng.randf_range(-21, 21), size * 0.5, rng.randf_range(-21, 21))
		_box(pos, Vector3(size, size, size), Core.material(Core.COLORS[c]))
		props.append({"pos": pos, "color": c})

	for i in range(9):
		var c: int = palette[rng.randi() % palette.size()]
		var pos := Vector3(rng.randf_range(-19, 19), 2.2, rng.randf_range(-19, 19))
		_cylinder(pos, 0.85, 4.4, Core.material(Core.COLORS[c]))
		props.append({"pos": pos, "color": c})

	for i in range(5):
		var c: int = palette[rng.randi() % palette.size()]
		var pos := Vector3(rng.randf_range(-16, 16), 1.5, rng.randf_range(-16, 16))
		_box(pos, Vector3(5.0, 0.6, 2.4), Core.material(Core.COLORS[c]))
		props.append({"pos": pos, "color": c})

	spawns = [
		Vector3(-20, 1, -20), Vector3(20, 1, -20),
		Vector3(-20, 1, 20), Vector3(20, 1, 20),
		Vector3(0, 1, -20), Vector3(0, 1, 20),
		Vector3(-20, 1, 0), Vector3(20, 1, 0),
	]

func destroy() -> void:
	if root != null and is_instance_valid(root):
		root.queue_free()
	root = null
	props.clear()
	spawns.clear()

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
		return Vector3(0, 1, 0)
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

	_part(holder, BoxMesh.new(), Vector3(0.62, 0.78, 0.34), Vector3(0, 1.05, 0), mat, owner_id, 0)
	_part(holder, SphereMesh.new(), Vector3(0.42, 0.42, 0.42), Vector3(0, 1.68, 0), mat, owner_id, 1)
	_part(holder, BoxMesh.new(), Vector3(0.18, 0.66, 0.18), Vector3(-0.42, 1.02, 0), mat, owner_id, 2)
	_part(holder, BoxMesh.new(), Vector3(0.18, 0.66, 0.18), Vector3(0.42, 1.02, 0), mat, owner_id, 3)
	_part(holder, BoxMesh.new(), Vector3(0.22, 0.66, 0.22), Vector3(-0.17, 0.34, 0), mat, owner_id, 4)
	_part(holder, BoxMesh.new(), Vector3(0.22, 0.66, 0.22), Vector3(0.17, 0.34, 0), mat, owner_id, 5)

	return {"node": holder, "mat": mat, "image": img, "texture": tex}

func _part(parent: Node3D, src: Mesh, size: Vector3, pos: Vector3, mat: Material, owner_id: int, part_index: int) -> void:
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
