extends Node
## Main controller: menus, local input, authoritative match and networking.

const World = preload("res://scripts/World.gd")
const MatchLogic = preload("res://scripts/Match.gd")
const HUDScript = preload("res://scripts/HUD.gd")

const SPEED := 6.2
const SPRINT_SPEED := 9.6
const GRAVITY := 19.0
const JUMP_SPEED := 6.4
const WALL_CLIMB_SPEED := 4.2
const WALL_SLIDE_SPEED := 3.0
const WALL_STICK := 1.6
const WALL_JUMP_UP := 6.8
const WALL_JUMP_PUSH := 5.5
const HUNTER_SCALE := 1.32
const PRONE_CAP_HEIGHT := 0.62
const PRONE_SPEED := 2.6
const TICK := 1.0 / 15.0

var hud
var world
var logic
var scene_root: Node3D
var camera: Camera3D
var camera_arm: SpringArm3D
var flashlight: SpotLight3D
var view_gun: Node3D
var audio: AudioStreamPlayer

var mode := "menu" # menu | host | client
var is_host := true
var local_id := 1
var running := false
var paused := false
var palette_open := false
var map_index := 0
var _last_phase := ""

var players := {} # id -> state dictionary
var views := {}   # id -> {"body": CharacterBody3D, "avatar": Dictionary}
var _keys := {}
var _yaw := 0.0
var _pitch := 0.0
var _net_clock := 0.0
var _step_clock := 0.0
var _my_input := {"fw": 0.0, "sd": 0.0, "sprint": false, "jump": false}

# --- painting -------------------------------------------------------------
var paint_mode := false
var paint_color := Color.WHITE
var brush_size := 20
var pipette_mode := false
var _paint_hold := false
var _orbit_hold := false
var paint_zoom := 3.6
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var _shoot_cooldown := 0.0

func _ready() -> void:
	hud = HUDScript.new()
	add_child(hud)
	hud.ui.connect(_on_ui)
	hud.paint_color_changed.connect(_on_paint_color)
	hud.brush_changed.connect(_on_brush_changed)
	hud.pipette_toggled.connect(_on_pipette_toggled)

	audio = AudioStreamPlayer.new()
	add_child(audio)

	scene_root = Node3D.new()
	add_child(scene_root)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.08)
	env.ambient_light_color = Color(0.28, 0.34, 0.48)
	env.ambient_light_energy = 0.45
	env_node.environment = env
	scene_root.add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 38, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_bias = 0.025
	sun.directional_shadow_max_distance = 90.0
	scene_root.add_child(sun)

	camera_arm = SpringArm3D.new()
	camera_arm.rotation_order = EulerOrder.EULER_ORDER_YXZ
	camera_arm.collision_mask = 1
	camera_arm.margin = 0.18
	scene_root.add_child(camera_arm)

	camera = Camera3D.new()
	camera.fov = 76
	camera.near = 0.05
	camera.rotation_order = EulerOrder.EULER_ORDER_YXZ
	camera_arm.add_child(camera)
	camera.position = Vector3.ZERO
	flashlight = SpotLight3D.new()
	flashlight.spot_angle = deg_to_rad(30)
	flashlight.light_energy = 7.0
	flashlight.spot_range = 26.0
	flashlight.visible = false
	camera.add_child(flashlight)

	# First-person rifle sits under the camera; a separate copy is attached to
	# the hunter avatar so remote players see the weapon too.
	var gun_factory := World.new()
	view_gun = gun_factory.make_gun(camera)
	view_gun.position = Vector3(0.34, -0.30, -0.72)
	view_gun.rotation = Vector3(0, -0.08, 0)
	view_gun.scale = Vector3(0.75, 0.75, 0.75)
	view_gun.visible = false

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	set_process(true)

	var args: Array = OS.get_cmdline_user_args()
	if args.has("--auto-host"):
		call_deferred("start_host")
		if args.has("--auto-start"):
			call_deferred("_begin_host_match")
	elif args.has("--auto-join"):
		var i: int = args.find("--auto-join")
		if i + 1 < args.size():
			call_deferred("auto_join", args[i + 1])

func auto_join(url: String) -> void:
	hud.url_edit.text = url
	start_client()

# ------------------------------------------------------------------ menu ----

func _on_ui(action: String, value: int) -> void:
	match action:
		"host": start_host()
		"join": start_client()
		"help": hud.set_menu_info("MOVE: WASD (ZQSD on AZERTY), Shift sprints, Space jumps. Touch a wall in mid-air to grab it: W/S climbs, A/D slides, Space jumps off. You hang still on a wall or ceiling until you move; Space drops off a ceiling. EMOTES: V flat on the ground, B ball, N tall, M wave; press again to clear. HIDERS: always third person. P opens PAINT mode: left-drag paints, right-drag orbits the camera only, wheel zooms, pipette samples a colour. Stand still near matching props to camouflage. SEEKERS: larger body with a visible rifle, first person. Hold C to lie prone like a soldier in a trench: slow and low, with a smaller hitbox. F toggles the flashlight. Spotting or shooting a hider eliminates them instantly.")
		"paint": try_preset_paint(value)
		"pipette": _toggle_pipette()
		"leave": leave_match()

func _on_paint_color(c: Color) -> void:
	paint_color = c
	if pipette_mode:
		_toggle_pipette()

func _on_brush_changed(size: int) -> void:
	brush_size = size

func _on_pipette_toggled() -> void:
	_toggle_pipette()

func _toggle_pipette() -> void:
	pipette_mode = not pipette_mode
	hud.set_pipette(pipette_mode)

func _cleanup_match() -> void:
	running = false
	paused = false
	palette_open = false
	paint_mode = false
	pipette_mode = false
	_paint_hold = false
	_orbit_hold = false
	hud.set_paint_mode(false)
	hud.set_pipette(false)
	_shoot_cooldown = 0.0
	if Net.message_received.is_connected(_on_net_message):
		Net.message_received.disconnect(_on_net_message)
	if Net.peer_connected.is_connected(_on_peer_connected):
		Net.peer_connected.disconnect(_on_peer_connected)
	if Net.peer_disconnected.is_connected(_on_peer_disconnected):
		Net.peer_disconnected.disconnect(_on_peer_disconnected)
	if Net.connection_state.is_connected(_on_connection_state):
		Net.connection_state.disconnect(_on_connection_state)
	Net.stop()
	if world != null:
		world.destroy()
		world = null
	for id in views:
		var v: Dictionary = views[id]
		if is_instance_valid(v.body):
			v.body.queue_free()
	views.clear()
	players.clear()
	logic = null
	_last_phase = ""
	flashlight.visible = false
	if view_gun != null:
		view_gun.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _setup_world(map: int) -> void:
	if world != null:
		world.destroy()
	world = World.new()
	world.build(scene_root, map)
	map_index = map

func _create_player(id: int, pname: String) -> void:
	if players.has(id):
		return
	var body := CharacterBody3D.new()
	body.position = world.spawn(int(id) % 8)
	body.set_meta("player_id", id)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.5
	col.shape = cap
	# The body origin is at the feet. Lifting the capsule keeps the mesh on
	# the ground instead of floating one capsule-half above it.
	col.position.y = cap.height * 0.5
	body.add_child(col)
	scene_root.add_child(body)
	# SpringArm3D casts along its local +Z; exclude this body so the camera
	# never snaps to the character's own capsule.
	if camera_arm.has_method("add_excluded_object"):
		camera_arm.call("add_excluded_object", body.get_rid())
	var avatar: Dictionary = world.make_avatar(body, Color.WHITE, id)
	avatar.node.visible = true
	var gun: Node3D = world.make_gun(avatar.node)
	gun.position = Vector3(0.34, 1.20, -0.24)
	gun.visible = false
	views[id] = {"body": body, "avatar": avatar, "cap": cap, "col": col, "gun": gun}
	players[id] = {
		"id": id, "name": pname, "x": body.position.x, "y": body.position.y,
		"z": body.position.z, "yaw": 0.0, "color": Color.WHITE, "flash": false,
		"camo": 0.0, "seen": false, "was_seen": false, "found": false,
		"wall_grab": false, "ceiling_grab": false, "emote": "none", "prone": false,
		"input": {"fw": 0.0, "sd": 0.0, "sprint": false, "jump": false, "prone": false},
	}

func _capture() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# A LineEdit or Button can keep keyboard focus after Host/Join is clicked.
	# Release it so WASD reaches the game instead of being typed into the UI.
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	palette_open = false
	paused = false

func start_host() -> void:
	_cleanup_match()
	if not Net.start_server(hud.host_port()):
		hud.set_menu_info("Could not open the port. Try another port.")
		return
	mode = "host"
	is_host = true
	local_id = 1
	running = false
	Net.message_received.connect(_on_net_message)
	Net.peer_connected.connect(_on_peer_connected)
	Net.peer_disconnected.connect(_on_peer_disconnected)
	Net.connection_state.connect(_on_connection_state)
	logic = MatchLogic.new()
	logic.setup([1], 0)
	_setup_world(0)
	_create_player(1, hud.player_name())
	hud.show_lobby("HOSTING on port %d.\nClients join with ws://<your-ip>:%d\nAt least 2 real players are needed.\nPress ENTER when everyone is in." % [hud.host_port(), hud.host_port()])

func _on_connection_state(ok: bool, detail: String) -> void:
	print("NET: %s - %s" % [str(ok), detail])
	hud.set_menu_info(detail)
	if ok and mode == "client" and not running:
		Net.send_to_host({"t": "hello", "n": hud.player_name()})
	if not ok and mode == "client" and not running:
		hud.show_lobby(detail + "\nCheck the URL and that the host is running.")

func _on_peer_connected(id: int) -> void:
	print("PEER CONNECTED: %d" % id)
	_create_player(id, "Guest %d" % id)
	if not logic.ids.has(id):
		logic.ids.append(id)
	if logic.ids.size() >= 2:
		hud.set_menu_info("Player %d joined. %d connected. Press ENTER to start." % [id, logic.ids.size()])
	else:
		hud.set_menu_info("Player %d joined. Need 1 more real player." % id)
	if running and logic != null:
		_send_welcome(id)

func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	if views.has(id):
		var v: Dictionary = views[id]
		if is_instance_valid(v.body):
			v.body.queue_free()
		views.erase(id)
	if logic.ids.has(id):
		logic.ids.erase(id)
	hud.set_menu_info("Player %d left. %d connected." % [id, logic.ids.size()])

func _begin_host_match() -> void:
	if logic == null or running:
		return
	if logic.ids.size() < 2:
		hud.set_menu_info("Need at least 2 real players. Wait for another player to join.")
		return
	logic.map_index = 0
	logic.setup(logic.ids.duplicate(), 0)
	for id in logic.ids:
		var st: Dictionary = players.get(id, {})
		if not st.is_empty():
			st.color = Color.WHITE
			_apply_fill(int(id), Color.WHITE)
	logic.start_round()
	running = true
	print("HOST MATCH STARTED: %s" % str(logic.ids))
	for id in logic.ids:
		if players.has(id):
			_send_welcome(id)
	_after_new_round()
	hud.show_game()
	hud.log_line("Match started on %s." % Core.MAPS[map_index].name)
	_capture()

func _send_welcome(id: int) -> void:
	if logic == null:
		return
	var names := {}
	for pid in logic.ids:
		if players.has(int(pid)):
			names[str(pid)] = str(players[int(pid)].name)
	Net.send_to(id, {
		"t": "welcome", "id": id, "map": map_index,
		"ids": logic.ids.duplicate(), "names": names,
		"snapshot": _snapshot(),
	})

func start_client() -> void:
	_cleanup_match()
	mode = "client"
	is_host = false
	local_id = -1
	running = false
	Net.message_received.connect(_on_net_message)
	Net.connection_state.connect(_on_connection_state)
	hud.show_lobby("Connecting to %s ..." % hud.join_url())
	Net.start_client(hud.join_url())

# ------------------------------------------------------------- networking ----

func _on_net_message(from_id: int, msg: Dictionary) -> void:
	var t := str(msg.get("t", ""))
	if is_host:
		match t:
			"hello":
				if players.has(from_id):
					players[from_id].name = str(msg.get("n", "Player"))
				if running:
					_send_welcome(from_id)
			"input":
				if players.has(from_id):
					var st: Dictionary = players[from_id]
					st.input = {
						"fw": clampf(float(msg.get("fw", 0)), -1, 1),
						"sd": clampf(float(msg.get("sd", 0)), -1, 1),
						"sprint": bool(msg.get("sprint", false)),
						"jump": bool(msg.get("jump", false)),
						"prone": bool(msg.get("prone", false)),
					}
					st.yaw = float(msg.get("yaw", 0))
			"paint_stroke":
				if players.has(from_id):
					var c := Color.from_string(str(msg.get("c", "#ffffff")), Color.WHITE)
					var u := clampf(float(msg.get("u", 0)), 0, 1)
					var v := clampf(float(msg.get("v", 0)), 0, 1)
					var size := clampi(int(msg.get("s", 20)), 2, 64)
					_apply_stroke(from_id, u, v, c, size)
					Net.broadcast({"t": "paint_stroke", "id": from_id,
						"u": u, "v": v, "c": c.to_html(false), "s": size})
			"paint_fill":
				if players.has(from_id):
					var c := Color.from_string(str(msg.get("c", "#ffffff")), Color.WHITE)
					_apply_fill(from_id, c)
					Net.broadcast({"t": "paint_fill", "id": from_id, "c": c.to_html(false)})
			"flash":
				if players.has(from_id):
					players[from_id].flash = not bool(players[from_id].flash)
			"emote":
				if players.has(from_id):
					var e := str(msg.get("e", "none"))
					players[from_id].emote = e
					Net.broadcast({"t": "emote", "id": from_id, "e": e})
			"shoot":
				_resolve_shot(from_id)
		return

	match t:
		"welcome":
			local_id = int(msg.get("id", 1))
			var ids_raw: Array = msg.get("ids", [])
			var names_raw: Dictionary = msg.get("names", {})
			var m := int(msg.get("map", 0))
			_setup_world(m)
			for raw in ids_raw:
				var pid := int(raw)
				_create_player(pid, str(names_raw.get(str(pid), "Player")))
			running = true
			print("WELCOME: id=%d players=%d map=%d" % [local_id, players.size(), m])
			logic = MatchLogic.new()
			logic.setup(ids_raw.duplicate(), m)
			_apply_snapshot(msg.get("snapshot", {}))
			hud.show_game()
			hud.log_line("Connected as %s (id %d)." % [players[local_id].name, local_id])
			_capture()
		"snapshot":
			_apply_snapshot(msg)
		"paint_stroke":
			var pid := int(msg.get("id", -1))
			if players.has(pid):
				_apply_stroke(pid, clampf(float(msg.get("u", 0)), 0, 1),
					clampf(float(msg.get("v", 0)), 0, 1),
					Color.from_string(str(msg.get("c", "#ffffff")), Color.WHITE),
					clampi(int(msg.get("s", 20)), 2, 64))
		"paint_fill":
			var pid := int(msg.get("id", -1))
			if players.has(pid):
				_apply_fill(pid, Color.from_string(str(msg.get("c", "#ffffff")), Color.WHITE))
		"event":
			hud.log_line(str(msg.get("msg", "")))
		"emote":
			var eid := int(msg.get("id", -1))
			if players.has(eid):
				players[eid].emote = str(msg.get("e", "none"))

func _apply_snapshot(s: Dictionary) -> void:
	if s.is_empty() or logic == null or not running:
		return
	logic.phase = str(s.get("phase", logic.phase))
	logic.time_left = float(s.get("time", logic.time_left))
	logic.round = int(s.get("round", logic.round))
	logic.hunter_id = int(s.get("hunter", logic.hunter_id))
	logic.map_index = int(s.get("map", logic.map_index))
	var fd := {}
	for k in s.get("found", {}):
		fd[int(k)] = bool(s.found[k])
	logic.found = fd
	var list: Array = s.get("players", [])
	for raw in list:
		var pd: Dictionary = raw
		var pid := int(pd.get("id", -1))
		if pid < 0:
			continue
		if not players.has(pid):
			_create_player(pid, str(pd.get("n", "Player")))
		var st: Dictionary = players[pid]
		st.name = str(pd.get("n", st.name))
		st.x = float(pd.get("x", st.x))
		st.y = float(pd.get("y", st.y))
		st.z = float(pd.get("z", st.z))
		st.yaw = float(pd.get("yaw", st.yaw))
		st.color = Color.from_string(str(pd.get("col", "#ffffff")), Color.WHITE)
		st.flash = bool(pd.get("flash", false))
		st.camo = clampf(float(pd.get("camo", 0)), 0, 1)
		st.seen = bool(pd.get("seen", false))
		st.found = bool(pd.get("found", false))
		st.emote = str(pd.get("em", st.emote))
		st.prone = bool(pd.get("pr", false))
	var phase_now: String = str(logic.phase)
	if phase_now != _last_phase:
		_on_phase_change(phase_now)
		_last_phase = phase_now

func _snapshot() -> Dictionary:
	var list: Array = []
	for id in players:
		var st: Dictionary = players[id]
		list.append({
			"id": id, "n": st.name, "x": st.x, "y": st.y, "z": st.z,
			"yaw": st.yaw, "col": st.color.to_html(false), "flash": st.flash,
			"camo": st.camo, "seen": st.seen, "found": st.found, "em": st.emote,
			"pr": st.prone,
		})
	var base: Dictionary = logic.snapshot()
	base["t"] = "snapshot"
	base["players"] = list
	return base

# ---------------------------------------------------------------- gameplay ----

func _role_of(id: int) -> String:
	if logic != null and id == logic.hunter_id:
		return "SEEKER"
	return "HIDER"

func _play(kind: String) -> void:
	audio.stream = Core.sfx(kind)
	audio.play()

# ---------------------------------------------------------------- painting ----

func _barycentric(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var den := d00 * d11 - d01 * d01
	if absf(den) < 0.0000001:
		return Vector3(1, 0, 0)
	var w1 := (d11 * d20 - d01 * d21) / den
	var w2 := (d00 * d21 - d01 * d20) / den
	return Vector3(1.0 - w1 - w2, w1, w2)

## Raycasts the avatar's invisible per-part collider and returns the exact
## atlas UV under the cursor. Returns (-1,-1) when the click missed the avatar.
func _avatar_uv_at(pos: Vector2) -> Vector2:
	var from := camera.project_ray_origin(pos)
	var dir := camera.project_ray_normal(pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	q.collision_mask = 2
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return Vector2(-1, -1)
	var col: Object = hit.collider
	if not (col is StaticBody3D) or not col.has_meta("owner_id"):
		return Vector2(-1, -1)
	if int(col.get_meta("owner_id")) != local_id:
		return Vector2(-1, -1)
	var faces: PackedVector3Array = col.get_meta("faces")
	var face_uvs: PackedVector2Array = col.get_meta("face_uvs")
	var fi := int(hit.face_index)
	if fi < 0 or fi * 3 + 2 >= faces.size():
		return Vector2(-1, -1)
	var a := faces[fi * 3]
	var b := faces[fi * 3 + 1]
	var c := faces[fi * 3 + 2]
	var w := _barycentric(col.to_local(hit.position), a, b, c)
	return face_uvs[fi * 3] * w.x + face_uvs[fi * 3 + 1] * w.y + face_uvs[fi * 3 + 2] * w.z

func _apply_stroke(id: int, u: float, v: float, color: Color, size: int) -> void:
	if not views.has(id):
		return
	var av: Dictionary = views[id].avatar
	var img: Image = av.image
	var cx: int = int(clampf(u, 0, 1) * float(img.get_width() - 1))
	var cy: int = int(clampf(v, 0, 1) * float(img.get_height() - 1))
	var r: int = clampi(size, 2, 64)
	for y in range(maxi(0, cy - r), mini(img.get_height(), cy + r + 1)):
		for x in range(maxi(0, cx - r), mini(img.get_width(), cx + r + 1)):
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy <= r * r:
				img.set_pixel(x, y, color)
	av.texture.update(img)
	if players.has(id):
		players[id].color = color

func _apply_fill(id: int, color: Color) -> void:
	if not views.has(id):
		return
	var av: Dictionary = views[id].avatar
	var img: Image = av.image
	img.fill(color)
	av.texture.update(img)
	if players.has(id):
		players[id].color = color

func try_preset_paint(idx: int) -> void:
	if not running or idx < 0 or idx >= Core.COLORS.size():
		return
	if _role_of(local_id) != "HIDER":
		hud.log_line("Only hiders can paint.")
		return
	var c: Color = Core.COLORS[idx]
	paint_color = c
	hud.set_color(c)
	_apply_fill(local_id, c)
	if is_host:
		Net.broadcast({"t": "paint_fill", "id": local_id, "c": c.to_html(false)})
	else:
		Net.send_to_host({"t": "paint_fill", "c": c.to_html(false)})
	_play("paint")
	hud.log_line("Colour: %s" % Core.COLOR_NAMES[idx])

func _set_paint_mode(on: bool) -> void:
	if not running:
		return
	if on and _role_of(local_id) != "HIDER":
		hud.log_line("The seeker stays in first person and cannot paint.")
		return
	paint_mode = on
	_paint_hold = false
	_orbit_hold = false
	if on:
		_orbit_yaw = _yaw
		_orbit_pitch = _pitch
	hud.set_paint_mode(on)
	if views.has(local_id):
		views[local_id].avatar.node.visible = _role_of(local_id) == "HIDER"
	pipette_mode = false
	hud.set_pipette(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED)

func _paint_at(pos: Vector2) -> void:
	if not running or not views.has(local_id):
		return
	var uv := _avatar_uv_at(pos)
	if uv.x < 0.0 or uv.y < 0.0:
		return
	var u := clampf(uv.x, 0, 1)
	var v := clampf(uv.y, 0, 1)
	_apply_stroke(local_id, u, v, paint_color, brush_size)
	if is_host:
		Net.broadcast({"t": "paint_stroke", "id": local_id, "u": u, "v": v,
			"c": paint_color.to_html(false), "s": brush_size})
	else:
		Net.send_to_host({"t": "paint_stroke", "u": u, "v": v,
			"c": paint_color.to_html(false), "s": brush_size})

## Reads the REAL rendered pixel under the cursor: albedo + lights + shadows.
## A red prop in a dark corner is therefore sampled as dark red, not bright red.
func _rendered_color_at(pos: Vector2) -> Color:
	var tex := get_viewport().get_texture()
	if tex == null:
		return Color(-1, -1, -1, 1)
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return Color(-1, -1, -1, 1)
	var size := img.get_size()
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0 or size.x <= 0 or size.y <= 0:
		return Color(-1, -1, -1, 1)
	var x := clampi(int(pos.x / vp.x * float(size.x)), 0, size.x - 1)
	var y := clampi(int(pos.y / vp.y * float(size.y)), 0, size.y - 1)
	var c := img.get_pixel(x, y)
	if c.a < 0.01:
		return Color(-1, -1, -1, 1)
	return Color(c.r, c.g, c.b, 1.0)

func _pipette_at(pos: Vector2) -> void:
	var picked := _rendered_color_at(pos)

	# If the pointer is over the paint panel (or the capture is unavailable),
	# fall back to the material colour under the ray.
	if picked.r < 0.0 or (hud.paint_panel != null and hud.paint_panel.visible and hud.paint_panel.get_global_rect().has_point(pos)):
		var fallback := Color.WHITE
		var uv := _avatar_uv_at(pos)
		if uv.x >= 0.0 and views.has(local_id):
			var img: Image = views[local_id].avatar.image
			fallback = img.get_pixel(
				int(clampf(uv.x, 0, 1) * float(img.get_width() - 1)),
				int(clampf(uv.y, 0, 1) * float(img.get_height() - 1)))
		else:
			var from := camera.project_ray_origin(pos)
			var dir := camera.project_ray_normal(pos)
			var q := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
			q.collision_mask = 1
			var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
			if not hit.is_empty() and hit.collider is StaticBody3D:
				for c in hit.collider.get_children():
					if c is MeshInstance3D and c.material_override is StandardMaterial3D:
						fallback = c.material_override.albedo_color
						break
		picked = fallback

	paint_color = picked
	hud.set_color(picked)
	pipette_mode = false
	hud.set_pipette(false)
	hud.log_line("Pipette (lighting and shadows included): #%s" % picked.to_html(false))
	_play("paint")

# ---------------------------------------------------------------- shooting ----

func try_flash() -> void:
	if not running or _role_of(local_id) != "SEEKER" or not players.has(local_id):
		return
	if is_host:
		players[local_id].flash = not bool(players[local_id].flash)
	else:
		Net.send_to_host({"t": "flash"})
	_play("flash")

## Cosmetic emote. Pressing the same key again returns to the normal pose.
func try_emote(emote: String) -> void:
	if not running or not players.has(local_id):
		return
	var st: Dictionary = players[local_id]
	var next := "none" if str(st.emote) == emote else emote
	st.emote = next
	if is_host:
		world.set_pose(views[local_id].avatar, next)
		Net.broadcast({"t": "emote", "id": local_id, "e": next})
	else:
		Net.send_to_host({"t": "emote", "e": next})
	hud.log_line("Emote: %s" % next)

func _try_shoot(by_id: int = -1) -> void:
	var who := local_id if by_id < 0 else by_id
	if not running or logic == null or logic.phase != "seeking":
		return
	if _role_of(who) != "SEEKER":
		if who == local_id:
			hud.log_line("Only the seeker can shoot.")
		return
	if who == local_id and _shoot_cooldown > 0.0:
		return
	if not is_host:
		if who == local_id:
			Net.send_to_host({"t": "shoot"})
			_shoot_cooldown = 0.28
		return
	_resolve_shot(who)
	if who == local_id:
		_shoot_cooldown = 0.28

func _resolve_shot(by_id: int) -> void:
	if logic == null or logic.phase != "seeking" or not players.has(by_id):
		return
	var me: Dictionary = players[by_id]
	var eye := 0.52 if bool(me.prone) else 1.62
	var from := Vector3(float(me.x), float(me.y) + eye * HUNTER_SCALE, float(me.z))
	var dir: Vector3
	if by_id == local_id and is_host:
		dir = -camera.transform.basis.z
	else:
		var hy := float(me.yaw)
		dir = Vector3(-sin(hy), 0, -cos(hy))
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * 45.0)
	q.collision_mask = 1
	q.exclude = [views[by_id].body.get_rid()]
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_play("flash")
		return
	var col: Object = hit.collider
	if not (col is CharacterBody3D) or not col.has_meta("player_id"):
		_play("flash")
		return
	var target := int(col.get_meta("player_id"))
	if target == by_id or _role_of(target) != "HIDER" or logic.found.get(target, false):
		_play("flash")
		return
	if logic.tag(target):
		var name := str(players[target].name)
		hud.log_line("%s SHOT %s: eliminated!" % [players[by_id].name, name])
		_play("found")
		Net.broadcast({"t": "event", "msg": "%s shot %s: eliminated!" % [players[by_id].name, name]})
		if logic.phase == "round_end":
			_on_phase_change("round_end")

func _simulate(delta: float) -> void:
	for id in players:
		var st: Dictionary = players[id]
		var body: CharacterBody3D = views[id].body
		if st.found and logic.phase != "hiding":
			body.velocity = Vector3.ZERO
			st.wall_grab = false
			st.ceiling_grab = false
			continue
		var inp: Dictionary = st.input
		# Only the seeker can lie prone. The capsule shrinks to a low profile,
		# which also lowers the camera and the shot origin.
		var prone := bool(inp.prone) and _role_of(id) == "SEEKER"
		st.prone = prone
		var cap: CapsuleShape3D = views[id].cap
		var col: CollisionShape3D = views[id].col
		var target_height := PRONE_CAP_HEIGHT if prone else 1.5
		if absf(cap.height - target_height) > 0.001:
			cap.height = target_height
			col.position.y = target_height * 0.5
		var want_jump := bool(inp.jump) and not prone
		inp.jump = false
		var grabbing := bool(st.wall_grab) and not prone
		var ceiling := bool(st.ceiling_grab) and not prone
		var on_floor := body.is_on_floor()
		var on_wall := body.is_on_wall()
		var on_ceiling := body.is_on_ceiling()
		var wall_n := body.get_wall_normal()
		var wall_jumped := false

		# A wall jump pushes away and up; a ceiling jump drops straight down.
		if grabbing and want_jump:
			body.velocity.y = WALL_JUMP_UP
			body.velocity.x = wall_n.x * WALL_JUMP_PUSH
			body.velocity.z = wall_n.z * WALL_JUMP_PUSH
			grabbing = false
			want_jump = false
			on_wall = false # do not re-grab on the same frame we leap off
			wall_jumped = true
		elif ceiling and want_jump:
			body.velocity.y = -WALL_JUMP_UP
			ceiling = false
			want_jump = false
			on_ceiling = false
			wall_jumped = true
		elif want_jump and on_floor:
			body.velocity.y = JUMP_SPEED
			_play("step")
			want_jump = false

		# Airborne contact grabs automatically: walls and ceilings.
		if not prone and not grabbing and not ceiling and not on_floor:
			if on_wall and wall_n.length_squared() > 0.1:
				grabbing = true
			elif on_ceiling:
				ceiling = true

		if grabbing:
			# No input means hanging perfectly still. W/S climbs, A/D slides.
			var climb := float(inp.fw)
			body.velocity.y = climb * WALL_CLIMB_SPEED
			var tangent := Vector3(-wall_n.z, 0, wall_n.x)
			var slide := float(inp.sd) * WALL_SLIDE_SPEED
			body.velocity.x = tangent.x * slide - wall_n.x * WALL_STICK
			body.velocity.z = tangent.z * slide - wall_n.z * WALL_STICK
			# Reaching the top, the floor, or the end of the wall lets go.
			if on_floor or not on_wall:
				grabbing = false
				body.velocity.y = maxf(body.velocity.y, 0.0)
		elif ceiling:
			# Move freely while hanging under the ceiling, gravity suppressed.
			var yaw := float(st.yaw)
			var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
			var right := Vector3(cos(yaw), 0, -sin(yaw))
			var move := fwd * float(inp.fw) + right * float(inp.sd)
			if move.length() > 1.0:
				move = move.normalized()
			var speed := PRONE_SPEED if prone else (SPRINT_SPEED if inp.sprint else SPEED)
			body.velocity.x = move.x * speed
			body.velocity.z = move.z * speed
			body.velocity.y = 0.12
			if not on_ceiling or on_floor:
				ceiling = false
		else:
			var yaw := float(st.yaw)
			var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
			var right := Vector3(cos(yaw), 0, -sin(yaw))
			var move := fwd * float(inp.fw) + right * float(inp.sd)
			if move.length() > 1.0:
				move = move.normalized()
			var speed := PRONE_SPEED if prone else (SPRINT_SPEED if inp.sprint else SPEED)
			# Keep the wall-jump push for this frame; normal input resumes next.
			if not wall_jumped:
				body.velocity.x = move.x * speed
				body.velocity.z = move.z * speed
			body.velocity.y -= GRAVITY * delta

		st.wall_grab = grabbing
		st.ceiling_grab = ceiling
		body.move_and_slide()
		st.x = body.position.x
		st.y = body.position.y
		st.z = body.position.z
		if absf(st.x) > 38.0 or absf(st.z) > 38.0 or st.y < -3.0:
			body.position = world.spawn(int(id) % 8)
			body.velocity = Vector3.ZERO
			st.wall_grab = false
			st.ceiling_grab = false

func _update_camo() -> void:
	var hunter: Dictionary = players.get(logic.hunter_id, {})
	for id in players:
		var st: Dictionary = players[id]
		var body: CharacterBody3D = views[id].body
		var speed := Vector2(body.velocity.x, body.velocity.z).length()
		var base: float = world.camo_at(Vector3(st.x, 0, st.z), st.color)
		var still := 1.0 if speed < 0.65 else 0.0
		st.camo = clampf(base * 0.8 + still * 0.2, 0.0, 1.0)
		var seen := true
		if id != logic.hunter_id and logic.phase == "seeking" and not hunter.is_empty():
			var me := Vector3(st.x, 0, st.z)
			var hp := Vector3(hunter.x, 0, hunter.z)
			var d := me.distance_to(hp)
			seen = false
			if d < 3.4:
				seen = true
			elif bool(hunter.flash) and d < 20.0:
				var hy := float(hunter.yaw)
				var fwd := Vector3(-sin(hy), 0, -cos(hy))
				var dir := (me - hp).normalized()
				if fwd.dot(dir) > 0.72 and st.camo < 0.93:
					seen = true
			elif st.camo < 0.45 and d < 10.0:
				seen = true
		# Being seen means instant elimination. No scoring is involved.
		if seen and not bool(st.was_seen):
			if id != logic.hunter_id and logic.phase == "seeking" and logic.tag(id):
				var msg := "%s was spotted and eliminated!" % str(players[id].name)
				hud.log_line(msg)
				_play("found")
				Net.broadcast({"t": "event", "msg": msg})
				if logic.phase == "round_end":
					_on_phase_change("round_end")
		st.was_seen = seen
		st.seen = seen

func _after_new_round() -> void:
	for id in players:
		var st: Dictionary = players[id]
		st.color = Color.WHITE
		st.found = false
		st.camo = 0.0
		st.flash = false
		st.seen = false
		st.was_seen = false
		st.wall_grab = false
		st.ceiling_grab = false
		st.emote = "none"
		st.prone = false
		st.input.prone = false
		var cap: CapsuleShape3D = views[id].cap
		cap.height = 1.5
		views[id].col.position.y = cap.height * 0.5
		_apply_fill(int(id), Color.WHITE)
		var body: CharacterBody3D = views[id].body
		body.position = world.spawn(int(id) % 8)
		body.velocity = Vector3.ZERO
	paint_color = Color.WHITE
	hud.set_color(Color.WHITE)
	_last_phase = "hiding"

func _on_phase_change(phase: String) -> void:
	print("PHASE: %s round=%d time=%.1f players=%d" % [phase, logic.round, logic.time_left, players.size()])
	match phase:
		"hiding":
			# Clients receive the new round as phase "hiding", not as the
			# host-only "new_round" event. Reset visuals and close the result
			# panel here too, otherwise the client stays stuck on it.
			_after_new_round()
			hud.show_game()
			if logic.round > 1:
				hud.log_line("ROUND %d/%d — paint again!" % [logic.round, 3])
		"seeking":
			hud.log_line("SEEKERS ARE IN! Hide!")
			_play("flash")
		"round_end":
			hud.log_line("Round over!")
			_play("tag")
			_show_result()
			if paint_mode:
				_set_paint_mode(false)
		"new_round":
			_after_new_round()
			hud.show_game()
			hud.log_line("ROUND %d/%d — paint again!" % [logic.round, 3])
		"match_end":
			_show_result()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _show_result() -> void:
	if logic == null:
		return
	var text := "ROUND %d / %d  —  %s\n\n" % [logic.round, 3, Core.MAPS[logic.map_index].name]
	text += "You were %s.\n" % _role_of(local_id)
	var found_count := 0
	for k in logic.found:
		if logic.found[k]:
			found_count += 1
	text += "Hiders eliminated: %d / %d\n" % [found_count, maxi(0, logic.ids.size() - 1)]
	text += "\nThe seeker wins by eliminating every hider.\nSurvive until the timer ends to win as a hider."
	if logic.phase == "match_end":
		text += "\n\nMATCH OVER"
	hud.show_result(text)

func _update_views(delta: float) -> void:
	var local_role := _role_of(local_id)
	for id in players:
		var st: Dictionary = players[id]
		var v: Dictionary = views[id]
		var body: CharacterBody3D = v.body
		if not is_host and id == local_id:
			body.position = Vector3(st.x, st.y, st.z)
		elif not is_host:
			body.position = body.position.lerp(Vector3(st.x, st.y, st.z), clampf(delta * 12.0, 0, 1))
		# The character follows the player's yaw, not the PAINT camera orbit.
		body.rotation.y = float(st.yaw)
		var role := _role_of(id)
		# Hunters are visibly larger than hiders. Scaling the body also scales
		# the capsule and the attached rifle, so collision matches the model.
		body.scale = Vector3.ONE if role == "HIDER" else Vector3(HUNTER_SCALE, HUNTER_SCALE, HUNTER_SCALE)
		var avatar: Dictionary = v.avatar
		avatar.node.visible = (id != local_id) or (role == "HIDER")
		var alpha := 1.0
		if id != local_id:
			if local_role == "SEEKER" and role == "HIDER" and not bool(st.seen):
				alpha = 0.05
			elif local_role == "HIDER" and role == "HIDER":
				alpha = 0.32
			if bool(st.found):
				alpha = 0.14
		avatar.mat.albedo_color = Color(1, 1, 1, alpha)
		var pose := str(st.emote)
		if bool(st.prone):
			pose = "prone"
		world.set_pose(avatar, pose)
		var gun: Node3D = v.gun
		gun.visible = role == "SEEKER"
	if local_id > 0 and views.has(local_id):
		var b: CharacterBody3D = views[local_id].body
		var me: Dictionary = players[local_id]
		if local_role == "HIDER":
			# Hiders always see their own avatar from a third-person camera.
			# In PAINT mode the camera uses its own orbit angles, so orbiting
			# never changes the direction the character is facing.
			var dist := paint_zoom if paint_mode else 4.2
			var cy := _orbit_yaw if paint_mode else _yaw
			var cp := clampf(_orbit_pitch if paint_mode else _pitch, -0.45, 0.75)
			var focus := b.position + Vector3(0, 1.2, 0)
			var off := Vector3(sin(cy) * cos(cp), sin(cp) + 0.25, cos(cy) * cos(cp)) * dist
			# SpringArm3D extends along local +Z, so aim local -Z away from
			# the desired camera position. The camera keeps zero rotation and
			# therefore looks back along the arm toward the focus.
			camera_arm.position = focus
			camera_arm.look_at(focus - off)
			camera_arm.spring_length = dist
			camera.rotation = Vector3.ZERO
		else:
			# Seekers stay in first person. A zero-length arm keeps the
			# camera exactly at eye height and disables spring collision.
			# The hunter is scaled up, and lying prone drops the eye line.
			var eye := 0.52 if bool(me.prone) else 1.62
			camera_arm.position = b.position + Vector3(0, eye * HUNTER_SCALE, 0)
			camera_arm.rotation = Vector3(_pitch, _yaw, 0)
			camera_arm.spring_length = 0.0
			camera.rotation = Vector3.ZERO
		flashlight.visible = bool(me.flash) and local_role == "SEEKER"
		view_gun.visible = local_role == "SEEKER" and not paint_mode

func _update_hud() -> void:
	if logic == null or not players.has(local_id):
		return
	var st: Dictionary = players[local_id]
	var role := _role_of(local_id)
	var detail := ""
	if role == "HIDER":
		detail = "Camouflage %d%%  —  P = paint, stay still near a matching prop" % int(float(st.camo) * 100.0)
	else:
		detail = "Flashlight %s  —  hold C to lie prone  —  spotting or shooting a hider eliminates instantly" % ("ON" if st.flash else "OFF")
	if paint_mode:
		detail = "PAINT  —  colour #%s  •  brush %dpx  •  zoom %.1f  •  pipette %s" % [
			paint_color.to_html(false), brush_size, paint_zoom, "ON" if pipette_mode else "OFF"]
	var phase_name := str(logic.phase).to_upper()
	if logic.phase == "hiding":
		phase_name = "HIDING  %d/%d" % [logic.round, 3]
	elif logic.phase == "seeking":
		phase_name = "SEEKING  %d/%d" % [logic.round, 3]
	hud.update_hud({
		"phase": phase_name,
		"time": logic.time_left,
		"role": "YOU ARE: %s" % role,
		"hide": detail,
	})

func _process(delta: float) -> void:
	if not running or paused:
		return
	_shoot_cooldown = maxf(0.0, _shoot_cooldown - delta)

	# Paint mode keeps the match alive (timers, network) but the painter
	# stands still so the avatar is easy to hit with the brush.
	var frozen := paint_mode

	# Arrow keys follow the same rule: in PAINT mode they orbit the camera,
	# outside PAINT mode they turn the player's look direction.
	if paint_mode:
		if _key_down(KEY_LEFT):
			_orbit_yaw += 2.0 * delta
		if _key_down(KEY_RIGHT):
			_orbit_yaw -= 2.0 * delta
		if _key_down(KEY_UP):
			_orbit_pitch = clampf(_orbit_pitch + 1.5 * delta, -0.45, 0.75)
		if _key_down(KEY_DOWN):
			_orbit_pitch = clampf(_orbit_pitch - 1.5 * delta, -0.45, 0.75)
	else:
		if _key_down(KEY_LEFT):
			_yaw += 2.0 * delta
		if _key_down(KEY_RIGHT):
			_yaw -= 2.0 * delta
		if _key_down(KEY_UP):
			_pitch = clampf(_pitch + 1.5 * delta, -1.2, 1.2)
		if _key_down(KEY_DOWN):
			_pitch = clampf(_pitch - 1.5 * delta, -1.2, 1.2)

	if is_host:
		if players.has(local_id):
			var me: Dictionary = players[local_id]
			me.input = {
				"fw": 0.0 if frozen else _fw_axis(),
				"sd": 0.0 if frozen else _sd_axis(),
				"sprint": not frozen and _key_down(KEY_SHIFT), "jump": false if frozen else _my_input.jump,
				"prone": not frozen and _key_down(KEY_C),
			}
			me.yaw = _yaw
			_my_input.jump = false
		_simulate(delta)
		_update_camo()
		var ev: String = logic.update(delta)
		if not ev.is_empty():
			_on_phase_change(ev)
		_net_clock += delta
		if _net_clock >= TICK and mode == "host":
			_net_clock = 0.0
			Net.broadcast(_snapshot())
		_step_clock += delta
		if _step_clock > 0.42:
			_step_clock = 0.0
			var st: Dictionary = players.get(local_id, {})
			if not st.is_empty() and views[local_id].body.is_on_floor() and Vector2(views[local_id].body.velocity.x, views[local_id].body.velocity.z).length() > 2.0:
				_play("step")
	else:
		_net_clock += delta
		if _net_clock >= TICK:
			_net_clock = 0.0
			Net.send_to_host({
				"t": "input", "fw": 0.0 if frozen else _fw_axis(),
				"sd": 0.0 if frozen else _sd_axis(),
				"sprint": not frozen and _key_down(KEY_SHIFT),
				"jump": false if frozen else _my_input.jump, "yaw": _yaw,
				"prone": not frozen and _key_down(KEY_C),
			})
			_my_input.jump = false

	_update_views(delta)
	_update_hud()

func _key_down(code: int) -> bool:
	# Poll the live keyboard state instead of relying only on _input(). A
	# focused UI control can swallow key events before the node sees them;
	# the Input singleton still knows the key is held. Check the physical key
	# too so AZERTY (ZQSD) and other layouts keep the same WASD positions.
	if Input.is_key_pressed(code) or Input.is_physical_key_pressed(code):
		return true
	return bool(_keys.get(code, false))

func _fw_axis() -> float:
	var v := 0.0
	if _key_down(KEY_W) or _key_down(KEY_Z):
		v += 1.0
	if _key_down(KEY_S):
		v -= 1.0
	return v

func _sd_axis() -> float:
	var v := 0.0
	if _key_down(KEY_D):
		v += 1.0
	if _key_down(KEY_A) or _key_down(KEY_Q):
		v -= 1.0
	return v

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		# Store both the layout keycode and the physical key. Physical codes
		# make WASD work on AZERTY too (ZQSD), for the host and for joiners.
		_keys[k.keycode] = k.pressed
		var code: int = k.keycode
		if k.physical_keycode != KEY_UNKNOWN:
			_keys[k.physical_keycode] = k.pressed
			code = k.physical_keycode
		if not k.pressed or k.echo:
			return
		match code:
			KEY_1: try_preset_paint(0)
			KEY_2: try_preset_paint(1)
			KEY_3: try_preset_paint(2)
			KEY_4: try_preset_paint(3)
			KEY_5: try_preset_paint(4)
			KEY_P: _set_paint_mode(not paint_mode)
			KEY_SPACE: _my_input.jump = not paint_mode
			KEY_V: try_emote("flat")
			KEY_B: try_emote("ball")
			KEY_N: try_emote("tall")
			KEY_M: try_emote("wave")
			KEY_F: try_flash()
			KEY_E: _try_shoot()
			KEY_ESCAPE:
				if paint_mode:
					_set_paint_mode(false)
				else:
					_toggle_pause()
			KEY_L:
				if running and (paused or paint_mode):
					leave_match()
			KEY_ENTER:
				if mode == "host" and not running:
					_begin_host_match()
	elif event is InputEventMouseMotion:
		var m: InputEventMouseMotion = event
		if running and not paused:
			if paint_mode:
				if _paint_hold:
					_paint_at(m.position)
				elif _orbit_hold:
					# Right-drag orbits the camera only. The character keeps
					# its own yaw, so it does not turn with the brush view.
					_orbit_yaw -= m.relative.x * 0.006
					_orbit_pitch = clampf(_orbit_pitch - m.relative.y * 0.006, -0.45, 0.75)
			elif Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				_yaw -= m.relative.x * 0.0026
				_pitch = clampf(_pitch - m.relative.y * 0.0026, -1.2, 1.2)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if not running or paused:
			return
		if paint_mode:
			if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				paint_zoom = clampf(paint_zoom - 0.4, 1.8, 7.0)
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				paint_zoom = clampf(paint_zoom + 0.4, 1.8, 7.0)
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					if pipette_mode:
						_pipette_at(mb.position)
					else:
						_paint_hold = true
						_paint_at(mb.position)
				else:
					_paint_hold = false
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				_orbit_hold = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_try_shoot()

func _toggle_pause() -> void:
	if not running:
		return
	paused = not paused
	if paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		hud.show_lobby("PAUSED\nPress ESC to resume. Press L to leave the match.")
	else:
		_capture()
		hud.show_game()

func leave_match() -> void:
	_cleanup_match()
	hud.show_menu()
