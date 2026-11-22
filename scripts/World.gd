extends RefCounted
## Builds the three original arena layouts from boxes and generated materials.

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

## How well a hider of the given paint color blends at this position (0..1).
func camo_at(pos: Vector3, color: int) -> float:
	var best := 0.0
	for p in props:
		if int(p.color) != color:
			continue
		var d := pos.distance_to(Vector3(p.pos.x, 0, p.pos.z))
		if d < 5.5:
			var v := 1.0 - d / 5.5
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

## Low-poly human avatar. Returns {"node": Node3D, "mat": StandardMaterial3D}.
func make_avatar(parent: Node3D, color: int) -> Dictionary:
	var holder := Node3D.new()
	parent.add_child(holder)
	var mat := Core.material(Core.COLORS[color])
	_part(holder, BoxMesh.new(), Vector3(0.62, 0.78, 0.34), Vector3(0, 1.05, 0), mat)
	_part(holder, SphereMesh.new(), Vector3(0.42, 0.42, 0.42), Vector3(0, 1.68, 0), mat)
	_part(holder, BoxMesh.new(), Vector3(0.18, 0.66, 0.18), Vector3(-0.42, 1.02, 0), mat)
	_part(holder, BoxMesh.new(), Vector3(0.18, 0.66, 0.18), Vector3(0.42, 1.02, 0), mat)
	_part(holder, BoxMesh.new(), Vector3(0.22, 0.66, 0.22), Vector3(-0.17, 0.34, 0), mat)
	_part(holder, BoxMesh.new(), Vector3(0.22, 0.66, 0.22), Vector3(0.17, 0.34, 0), mat)
	return {"node": holder, "mat": mat}

func _part(parent: Node3D, mesh: Mesh, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	if mesh is BoxMesh:
		mesh.size = size
	elif mesh is SphereMesh:
		mesh.radius = size.x * 0.5
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
