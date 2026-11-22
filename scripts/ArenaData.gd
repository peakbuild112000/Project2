extends RefCounted
class_name ArenaData

## Deterministic arena description. The host generates it from a seed and sends
## that seed to clients, so everyone renders the exact same map.

const ARENA_HALF: float = 17.0
const THEMES := [
	{
		"name": "NEON ALLEY",
		"bg": Color(0.015, 0.02, 0.07),
		"fog": Color(0.02, 0.04, 0.12),
		"floor": "res://assets/textures/floor_neon.png",
		"wall": "res://assets/textures/wall_neon.png",
		"light": Color(0.55, 0.8, 1.0),
		"glow": 0.9,
	},
	{
		"name": "SUNSET CANYON",
		"bg": Color(0.10, 0.045, 0.03),
		"fog": Color(0.22, 0.09, 0.05),
		"floor": "res://assets/textures/floor_canyon.png",
		"wall": "res://assets/textures/wall_canyon.png",
		"light": Color(1.0, 0.68, 0.38),
		"glow": 0.55,
	},
	{
		"name": "FROZEN VAULT",
		"bg": Color(0.02, 0.06, 0.11),
		"fog": Color(0.08, 0.18, 0.26),
		"floor": "res://assets/textures/floor_frost.png",
		"wall": "res://assets/textures/wall_frost.png",
		"light": Color(0.7, 0.9, 1.0),
		"glow": 0.75,
	},
]


static func theme(index: int) -> Dictionary:
	return THEMES[wrapi(index, 0, THEMES.size())]


static func build(seed: int, map_index: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var props: Array[Dictionary] = []

	# Colored cover blocks. Each has a palette index so hiders can match it.
	for i in 20:
		var px: float = rng.randf_range(-13.5, 13.5)
		var pz: float = rng.randf_range(-13.5, 13.5)
		if Vector2(px, pz).length() < 5.5:
			px += 7.0 if px >= 0.0 else -7.0
		var w: float = rng.randf_range(1.8, 3.6)
		var d: float = rng.randf_range(1.8, 3.6)
		var h: float = rng.randf_range(1.6, 3.4)
		props.append({
			"x": px, "z": pz, "w": w, "d": d, "h": h,
			"c": rng.randi() % 4,
			"rot": 0.0 if rng.randf() < 0.6 else PI * 0.5,
		})

	# Taller pillars break line of sight.
	for i in 6:
		var px: float = rng.randf_range(-14.0, 14.0)
		var pz: float = rng.randf_range(-14.0, 14.0)
		if Vector2(px, pz).length() < 5.0:
			pz += 7.0 if pz >= 0.0 else -7.0
		props.append({
			"x": px, "z": pz, "w": 1.3, "d": 1.3,
			"h": rng.randf_range(3.2, 4.6),
			"c": rng.randi() % 4,
			"rot": rng.randf_range(0.0, PI),
		})

	var spawns: Array[Vector3] = []
	for i in 10:
		var angle: float = TAU * float(i) / 10.0
		spawns.append(Vector3(cos(angle) * 13.0, 0.0, sin(angle) * 13.0))

	return {
		"seed": seed,
		"map": map_index,
		"props": props,
		"spawns": spawns,
		"theme": theme(map_index),
	}


static func clamp_position(pos: Vector3) -> Vector3:
	var limit: float = ARENA_HALF - 1.0
	pos.x = clampf(pos.x, -limit, limit)
	pos.z = clampf(pos.z, -limit, limit)
	pos.y = 0.0
	return pos


static func collides(pos: Vector3, layout: Dictionary, radius: float = 0.55) -> bool:
	for prop in layout["props"]:
		var dx: float = absf(pos.x - float(prop["x"]))
		var dz: float = absf(pos.z - float(prop["z"]))
		var hw: float = float(prop["w"]) * 0.5 + radius
		var hd: float = float(prop["d"]) * 0.5 + radius
		if dx < hw and dz < hd:
			return true
	return false


static func surface_match(x: float, z: float, color_index: int, layout: Dictionary) -> float:
	var best: float = 0.0
	var cover: float = 0.0
	for prop in layout["props"]:
		var dx: float = x - float(prop["x"])
		var dz: float = z - float(prop["z"])
		var dist: float = sqrt(dx * dx + dz * dz)
		var reach: float = maxf(float(prop["w"]), float(prop["d"])) * 0.5 + 2.0
		if int(prop["c"]) == color_index:
			best = maxf(best, clampf(1.0 - dist / reach, 0.0, 1.0))
		if dist < reach + 0.8:
			cover = maxf(cover, 0.22)
	return clampf(best + cover, 0.0, 1.0)
