extends Node
## Main controller: menus, local input, bots, authoritative match and networking.

const World = preload("res://scripts/World.gd")
const MatchLogic = preload("res://scripts/Match.gd")
const HUDScript = preload("res://scripts/HUD.gd")

const SPEED := 6.2
const SPRINT_SPEED := 9.6
const GRAVITY := 19.0
const JUMP_SPEED := 6.4
const TICK := 1.0 / 15.0

var hud
var world
var logic
var scene_root: Node3D
var camera: Camera3D
var flashlight: SpotLight3D
var audio: AudioStreamPlayer

var mode := "offline" # offline | host | client
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

func _ready() -> void:
	hud = HUDScript.new()
	add_child(hud)
	hud.ui.connect(_on_ui)

	audio = AudioStreamPlayer.new()
	add_child(audio)

	scene_root = Node3D.new()
	add_child(scene_root)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 38, 0)
	sun.light_energy = 1.15
	scene_root.add_child(sun)

	camera = Camera3D.new()
	camera.fov = 76
	camera.near = 0.05
	camera.rotation_order = EulerOrder.EULER_ORDER_YXZ
	scene_root.add_child(camera)
	flashlight = SpotLight3D.new()
	flashlight.spot_angle = deg_to_rad(30)
	flashlight.light_energy = 7.0
	flashlight.spot_range = 26.0
	flashlight.visible = false
	camera.add_child(flashlight)

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	set_process(true)

	var args: Array = OS.get_cmdline_user_args()
	if args.has("--auto-practice"):
		call_deferred("start_offline")
	elif args.has("--auto-host"):
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
		"practice": start_offline()
		"host": start_host()
		"join": start_client()
		"help": hud.set_menu_info("HIDERS: press 1-5 to paint your white suit the colour of a nearby prop, then stand still. Matching colour + stillness = camouflage. SEEKERS: F toggles the flashlight, E tags a hider at close range. You can also click the colour swatches with Tab open.")
		"paint": try_paint(value)
		"leave": leave_match()

func _cleanup_match() -> void:
	running = false
	paused = false
	palette_open = false
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
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _setup_world(map: int) -> void:
	if world != null:
		world.destroy()
	world = World.new()
	world.build(scene_root, map)
	map_index = map

func _create_player(id: int, pname: String, is_bot: bool) -> void:
	if players.has(id):
		return
	var body := CharacterBody3D.new()
	body.position = world.spawn(int(id) % 8)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.5
	col.shape = cap
	body.add_child(col)
	scene_root.add_child(body)
	var avatar: Dictionary = world.make_avatar(body, 4)
	avatar.node.visible = (id != local_id)
	views[id] = {"body": body, "avatar": avatar}
	players[id] = {
		"id": id, "name": pname, "x": body.position.x, "y": body.position.y,
		"z": body.position.z, "yaw": 0.0, "color": 4, "flash": false,
		"camo": 0.0, "seen": true, "found": false, "bot": is_bot,
		"input": {"fw": 0.0, "sd": 0.0, "sprint": false, "jump": false},
	}

func _capture() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	palette_open = false
	paused = false

func start_offline() -> void:
	_cleanup_match()
	mode = "offline"
	is_host = true
	local_id = 1
	running = true
	logic = MatchLogic.new()
	logic.setup([1, 2, 3, 4], 0)
	_setup_world(0)
	_create_player(1, hud.player_name(), false)
	_create_player(2, "Bot Ada", true)
	_create_player(3, "Bot Bix", true)
	_create_player(4, "Bot Cy", true)
	logic.start_round()
	_after_new_round()
	hud.show_game()
	hud.log_line("PRACTICE: 3 bots joined. Rounds start now.")
	_capture()

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
	_create_player(1, hud.player_name(), false)
	hud.show_lobby("HOSTING on port %d.\nClients join with ws://<your-ip>:%d\nPress ENTER when everyone is in.\nBots fill empty slots." % [hud.host_port(), hud.host_port()])

func _on_connection_state(ok: bool, detail: String) -> void:
	print("NET: %s - %s" % [str(ok), detail])
	hud.set_menu_info(detail)
	if ok and mode == "client" and not running:
		Net.send_to_host({"t": "hello", "n": hud.player_name()})
	if not ok and mode == "client" and not running:
		hud.show_lobby(detail + "\nCheck the URL and that the host is running.")

func _on_peer_connected(id: int) -> void:
	print("PEER CONNECTED: %d" % id)
	_create_player(id, "Guest %d" % id, false)
	if not logic.ids.has(id):
		logic.ids.append(id)
	hud.set_menu_info("Player %d joined. %d connected. Press ENTER to start." % [id, logic.ids.size()])
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
	while logic.ids.size() < 3:
		var bid: int = 100 + logic.ids.size()
		logic.ids.append(bid)
		_create_player(bid, "Bot %d" % bid, true)
	logic.map_index = 0
	logic.setup(logic.ids.duplicate(), 0)
	for id in logic.ids:
		var st: Dictionary = players.get(id, {})
		if not st.is_empty():
			st.color = 4
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
					}
					st.yaw = float(msg.get("yaw", 0))
			"paint":
				if players.has(from_id) and _role_of(from_id) == "HIDER":
					players[from_id].color = clampi(int(msg.get("c", 4)), 0, 4)
			"flash":
				if players.has(from_id):
					players[from_id].flash = not bool(players[from_id].flash)
			"tag":
				try_tag(from_id)
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
				_create_player(pid, str(names_raw.get(str(pid), "Player")), false)
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
		"event":
			hud.log_line(str(msg.get("msg", "")))

func _apply_snapshot(s: Dictionary) -> void:
	if s.is_empty() or logic == null or not running:
		return
	logic.phase = str(s.get("phase", logic.phase))
	logic.time_left = float(s.get("time", logic.time_left))
	logic.round = int(s.get("round", logic.round))
	logic.hunter_id = int(s.get("hunter", logic.hunter_id))
	logic.map_index = int(s.get("map", logic.map_index))
	var sc := {}
	for k in s.get("scores", {}):
		sc[int(k)] = int(s.scores[k])
	logic.scores = sc
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
			_create_player(pid, str(pd.get("n", "Player")), false)
		var st: Dictionary = players[pid]
		st.name = str(pd.get("n", st.name))
		st.x = float(pd.get("x", st.x))
		st.y = float(pd.get("y", st.y))
		st.z = float(pd.get("z", st.z))
		st.yaw = float(pd.get("yaw", st.yaw))
		st.color = clampi(int(pd.get("color", 4)), 0, 4)
		st.flash = bool(pd.get("flash", false))
		st.camo = clampf(float(pd.get("camo", 0)), 0, 1)
		st.seen = bool(pd.get("seen", true))
		st.found = bool(pd.get("found", false))
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
			"yaw": st.yaw, "color": st.color, "flash": st.flash,
			"camo": st.camo, "seen": st.seen, "found": st.found,
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

func try_paint(idx: int) -> void:
	if not running or idx < 0 or idx >= Core.COLORS.size():
		return
	if _role_of(local_id) != "HIDER":
		hud.log_line("Only hiders can paint.")
		return
	if is_host:
		players[local_id].color = idx
		hud.log_line("Painted %s." % Core.COLOR_NAMES[idx])
	else:
		Net.send_to_host({"t": "paint", "c": idx})
	_play("paint")

func try_flash() -> void:
	if not running or _role_of(local_id) != "SEEKER" or not players.has(local_id):
		return
	if is_host:
		players[local_id].flash = not bool(players[local_id].flash)
	else:
		Net.send_to_host({"t": "flash"})
	_play("flash")

func try_tag(by_id: int = -1) -> void:
	var who := local_id if by_id < 0 else by_id
	if not running or logic == null or logic.phase != "seeking":
		return
	if _role_of(who) != "SEEKER":
		if who == local_id:
			hud.log_line("Only the seeker can tag.")
		return
	if not is_host:
		if who == local_id:
			Net.send_to_host({"t": "tag"})
		return
	var me: Dictionary = players.get(who, {})
	if me.is_empty():
		return
	var best := -1
	var best_d := 3.2
	for id in players:
		if id == who or logic.found.get(id, false):
			continue
		var st: Dictionary = players[id]
		var d := Vector3(st.x - me.x, 0, st.z - me.z).length()
		if d < best_d:
			best_d = d
			best = id
	if best < 0:
		return
	if logic.tag(best):
		var name := str(players[best].name)
		hud.log_line("%s tagged %s!" % [players[who].name, name])
		_play("found")
		Net.broadcast({"t": "event", "msg": "%s tagged %s!" % [players[who].name, name]})
		if logic.phase == "round_end":
			_on_phase_change("round_end")

func _bot_input(st: Dictionary, delta: float) -> Dictionary:
	var inp := {"fw": 0.0, "sd": 0.0, "sprint": false, "jump": false}
	var here := Vector3(st.x, 0, st.z)
	if _role_of(st.id) == "SEEKER":
		var target := -1
		var best := 1.0e9
		for id in players:
			if id == st.id or logic.found.get(id, false):
				continue
			var other: Dictionary = players[id]
			var d := here.distance_to(Vector3(other.x, 0, other.z))
			if d < best:
				best = d
				target = id
		if target >= 0:
			var t: Dictionary = players[target]
			var to := Vector3(t.x, 0, t.z) - here
			var want: float = atan2(-to.x, -to.z)
			st.yaw = lerp_angle(st.yaw, want, clampf(delta * 2.4, 0, 1))
			st.flash = true
			if best > 2.4:
				inp.fw = 1.0
			elif logic.phase == "seeking":
				try_tag(st.id)
		else:
			inp.fw = 0.35
	else:
		if int(st.color) == 4 and not world.props.is_empty():
			var pick: Dictionary = world.props[randi() % world.props.size()]
			st.color = int(pick.color)
		var goal: Vector3 = here
		var best_d := 1.0e9
		for p in world.props:
			var pd: Dictionary = p
			if int(pd.color) != int(st.color):
				continue
			var d := here.distance_to(Vector3(pd.pos.x, 0, pd.pos.z))
			if d < best_d:
				best_d = d
				goal = Vector3(pd.pos.x, 0, pd.pos.z)
		if best_d > 1.8:
			var to := goal - here
			var want: float = atan2(-to.x, -to.z)
			st.yaw = lerp_angle(st.yaw, want, clampf(delta * 2.0, 0, 1))
			inp.fw = 0.75
		else:
			inp.fw = 0.0
	return inp

func _simulate(delta: float) -> void:
	for id in players:
		var st: Dictionary = players[id]
		var body: CharacterBody3D = views[id].body
		if st.found and logic.phase != "hiding":
			body.velocity = Vector3.ZERO
			continue
		var inp: Dictionary = st.input
		if st.bot:
			inp = _bot_input(st, delta)
		var yaw := float(st.yaw)
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		var move := fwd * float(inp.fw) + right * float(inp.sd)
		if move.length() > 1.0:
			move = move.normalized()
		var speed := SPRINT_SPEED if inp.sprint else SPEED
		body.velocity.x = move.x * speed
		body.velocity.z = move.z * speed
		if bool(inp.jump) and body.is_on_floor():
			body.velocity.y = JUMP_SPEED
			_play("step")
		inp.jump = false
		body.velocity.y -= GRAVITY * delta
		body.move_and_slide()
		st.x = body.position.x
		st.y = body.position.y
		st.z = body.position.z
		# out-of-bounds safety
		if absf(st.x) > 26.0 or absf(st.z) > 26.0 or st.y < -3.0:
			body.position = world.spawn(int(id) % 8)
			body.velocity = Vector3.ZERO

func _update_camo() -> void:
	var hunter: Dictionary = players.get(logic.hunter_id, {})
	for id in players:
		var st: Dictionary = players[id]
		var body: CharacterBody3D = views[id].body
		var speed := Vector2(body.velocity.x, body.velocity.z).length()
		var base: float = world.camo_at(Vector3(st.x, 0, st.z), int(st.color))
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
		st.seen = seen

func _after_new_round() -> void:
	for id in players:
		var st: Dictionary = players[id]
		st.color = 4
		st.found = false
		st.camo = 0.0
		st.flash = false
		var body: CharacterBody3D = views[id].body
		body.position = world.spawn(int(id) % 8)
		body.velocity = Vector3.ZERO
	_last_phase = "hiding"

func _on_phase_change(phase: String) -> void:
	print("PHASE: %s round=%d time=%.1f players=%d" % [phase, logic.round, logic.time_left, players.size()])
	match phase:
		"seeking":
			hud.log_line("SEEKERS ARE IN! Hide now!")
			_play("flash")
		"round_end":
			hud.log_line("Round over!")
			_play("tag")
			_show_result()
		"new_round":
			_after_new_round()
			hud.show_game()
			hud.log_line("ROUND %d/%d — fresh paint!" % [logic.round, 3])
		"match_end":
			_show_result()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _show_result() -> void:
	if logic == null:
		return
	var text := "ROUND %d / %d  —  %s\n\n" % [logic.round, 3, Core.MAPS[logic.map_index].name]
	text += "You were the %s.\n" % _role_of(local_id)
	var found_count := 0
	for k in logic.found:
		if logic.found[k]:
			found_count += 1
	text += "Hiders found: %d / %d\n\nSCORES\n" % [found_count, maxi(0, logic.ids.size() - 1)]
	for id in logic.scores:
		var nm := "Player"
		if players.has(int(id)):
			nm = players[int(id)].name
		text += "%s: %d\n" % [nm, logic.scores[id]]
	if logic.phase == "match_end":
		text += "\nMATCH OVER"
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
		var avatar: Dictionary = v.avatar
		var c: Color = Core.COLORS[int(st.color)]
		var alpha := 1.0
		if id != local_id:
			if local_role == "SEEKER" and _role_of(id) == "HIDER" and not bool(st.seen):
				alpha = 0.05
			elif local_role == "HIDER" and _role_of(id) == "HIDER":
				alpha = 0.32
			if bool(st.found):
				alpha = 0.14
		avatar.mat.albedo_color = Color(c.r, c.g, c.b, alpha)
	if local_id > 0 and views.has(local_id):
		var b: CharacterBody3D = views[local_id].body
		camera.position = b.position + Vector3(0, 1.62, 0)
		camera.rotation = Vector3(_pitch, _yaw, 0)
		var me: Dictionary = players[local_id]
		flashlight.visible = bool(me.flash) and local_role == "SEEKER"

func _update_hud() -> void:
	if logic == null or not players.has(local_id):
		return
	var st: Dictionary = players[local_id]
	var role := _role_of(local_id)
	var hiding := ""
	if role == "HIDER":
		hiding = "Camouflage %d%%  —  match a nearby colour, stand still" % int(float(st.camo) * 100.0)
	else:
		hiding = "Flashlight %s  —  E / right click to tag" % ("ON" if st.flash else "OFF")
	var scores_txt := ""
	for id in logic.scores:
		var nm := "P"
		if players.has(int(id)):
			nm = str(players[int(id)].name).substr(0, 8)
		scores_txt += "%s %d   " % [nm, logic.scores[id]]
	var phase_name := str(logic.phase).to_upper()
	if logic.phase == "hiding":
		phase_name = "HIDING  %d/%d" % [logic.round, 3]
	elif logic.phase == "seeking":
		phase_name = "SEEKING  %d/%d" % [logic.round, 3]
	hud.update_hud({
		"phase": phase_name,
		"time": logic.time_left,
		"role": "YOU ARE: %s" % role,
		"hide": hiding,
		"scores": scores_txt,
	})

func _process(delta: float) -> void:
	if not running or paused or palette_open:
		return
	if _keys.get(KEY_LEFT, false):
		_yaw += 2.0 * delta
	if _keys.get(KEY_RIGHT, false):
		_yaw -= 2.0 * delta
	if _keys.get(KEY_UP, false):
		_pitch = clampf(_pitch + 1.5 * delta, -1.2, 1.2)
	if _keys.get(KEY_DOWN, false):
		_pitch = clampf(_pitch - 1.5 * delta, -1.2, 1.2)

	if is_host:
		if players.has(local_id):
			var me: Dictionary = players[local_id]
			me.input = {
				"fw": _axis(KEY_W, KEY_S), "sd": _axis(KEY_D, KEY_A),
				"sprint": _keys.get(KEY_SHIFT, false), "jump": _my_input.jump,
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
				"t": "input", "fw": _axis(KEY_W, KEY_S), "sd": _axis(KEY_D, KEY_A),
				"sprint": _keys.get(KEY_SHIFT, false), "jump": _my_input.jump, "yaw": _yaw,
			})
			_my_input.jump = false

	_update_views(delta)
	_update_hud()

func _axis(pos: int, neg: int) -> float:
	var v := 0.0
	if _keys.get(pos, false):
		v += 1.0
	if _keys.get(neg, false):
		v -= 1.0
	return v

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		_keys[k.keycode] = k.pressed
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_1: try_paint(0)
			KEY_2: try_paint(1)
			KEY_3: try_paint(2)
			KEY_4: try_paint(3)
			KEY_5: try_paint(4)
			KEY_F: try_flash()
			KEY_E: try_tag()
			KEY_TAB:
				if running:
					palette_open = not palette_open
					Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if palette_open else Input.MOUSE_MODE_CAPTURED)
			KEY_ESCAPE: _toggle_pause()
			KEY_L:
				if running and (paused or palette_open):
					leave_match()
			KEY_ENTER:
				if mode == "host" and not running:
					_begin_host_match()
	elif event is InputEventMouseMotion:
		if running and not paused and not palette_open and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			var m: InputEventMouseMotion = event
			_yaw -= m.relative.x * 0.0026
			_pitch = clampf(_pitch - m.relative.y * 0.0026, -1.2, 1.2)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			try_tag()

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
