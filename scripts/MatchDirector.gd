extends Node
class_name MatchDirector

## Authoritative match rules. The host owns this logic; clients mirror the
## snapshots it broadcasts. Offline practice uses the same code with bots.

signal event_fired(text: String, color: Color)
signal phase_changed(phase: String)
signal round_started()
signal round_ended(results: Array)
signal auth_failed(reason: String)

const ROUND_LENGTH: float = 105.0
const MAX_SPEED: float = 8.5

var players: Dictionary = {}
var layout: Dictionary = {}
var phase: String = "menu"
var round: int = 1
var total_rounds: int = 3
var time_left: float = 0.0
var hunter_id: int = 1
var map_index: int = 0
var seed: int = 0
var role: String = "hider"
var is_host: bool = false
var is_offline: bool = false
var password: String = ""
var last_results: Array = []
var winner_text: String = ""
var near_target: bool = false

var _snap_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _bot_names := ["BOT-PIXEL", "BOT-MOSS", "BOT-GLOW", "BOT-SHADE"]


func _ready() -> void:
	_rng.randomize()


func setup_host(p_password: String, p_map: int, offline: bool = false) -> void:
	is_host = true
	is_offline = offline
	password = p_password
	map_index = p_map
	players.clear()
	phase = "lobby"
	round = 1
	_set_phase("lobby")
	seed = _rng.randi_range(1, 999999)
	layout = ArenaData.build(seed, map_index)
	hunter_id = 1
	_add_player(1, GameState.player_name, offline)
	if offline:
		for i in 3:
			_add_player(2 + i, _bot_names[i], true)
		event_fired.emit("PRACTICE LOBBY READY", Color(0.4, 1, 0.7))


func setup_client() -> void:
	is_host = false
	is_offline = false
	players.clear()
	phase = "connecting"
	_set_phase("connecting")


func add_remote(id: int, name: String) -> bool:
	if phase != "lobby":
		return false
	if players.has(id):
		return true
	_add_player(id, name, false)
	return true


func _add_player(id: int, name: String, bot: bool) -> void:
	players[id] = {
		"id": id,
		"name": name,
		"bot": bot,
		"x": 0.0, "z": 0.0, "yaw": 0.0,
		"color": (id - 1) % 4,
		"speed": 0.0,
		"stamina": 1.0,
		"hide": 0.0,
		"alive": true,
		"flash": false,
		"score": 0,
		"role": "hider",
	}


func remove_player(id: int) -> void:
	if players.has(id):
		var name: String = players[id]["name"]
		players.erase(id)
		event_fired.emit(name + " LEFT THE SESSION", Color(1, 0.6, 0.4))
		if is_host:
			Net.broadcast({"t": "left", "id": id})


func player_list_msg() -> Dictionary:
	var list: Array = []
	for id in players.keys():
		var p: Dictionary = players[id]
		list.append([id, p["name"], p["role"], p["score"], 1 if p["alive"] else 0])
	return {"t": "lobby", "players": list, "phase": phase, "round": round, "map": map_index}


func host_message(id: int, msg: Dictionary) -> void:
	var t: String = str(msg.get("t", ""))
	if t == "hello":
		if str(msg.get("password", "")) != password:
			event_fired.emit("PEER %d: WRONG PASSWORD" % id, Color(1, 0.4, 0.4))
			Net.send_to(id, {"t": "auth_fail", "reason": "Wrong session password"})
			Net.kick(id, "Wrong password")
			return
		var name: String = str(msg.get("name", "PLAYER")).substr(0, 16)
		if not add_remote(id, name):
			Net.send_to(id, {"t": "auth_fail", "reason": "Session already in progress"})
			Net.kick(id, "Game already started")
			return
		Net.send_to(id, {
			"t": "welcome", "id": id, "seed": seed, "map": map_index,
			"players": player_list_msg()["players"], "phase": phase,
			"password": password,
		})
		Net.broadcast(player_list_msg())
		event_fired.emit(str(players[id]["name"]) + " JOINED", Color(0.4, 1, 0.7))
	elif t == "state" and players.has(id):
		update_state(id, msg)
	elif t == "tag" and players.has(id):
		try_tag(id)
	elif t == "chat" and players.has(id):
		Net.broadcast({"t": "chat", "from": players[id]["name"], "text": str(msg.get("text", "")).substr(0, 80)})


func update_state(id: int, msg: Dictionary) -> void:
	if not players.has(id) or phase != "playing":
		return
	var p: Dictionary = players[id]
	var nx: float = clampf(float(msg.get("x", p["x"])), -ArenaData.ARENA_HALF + 1.0, ArenaData.ARENA_HALF - 1.0)
	var nz: float = clampf(float(msg.get("z", p["z"])), -ArenaData.ARENA_HALF + 1.0, ArenaData.ARENA_HALF - 1.0)
	var dx: float = nx - float(p["x"])
	var dz: float = nz - float(p["z"])
	var step: float = sqrt(dx * dx + dz * dz)
	var max_step: float = MAX_SPEED * 0.14
	if step > max_step and step > 0.001:
		nx = float(p["x"]) + dx / step * max_step
		nz = float(p["z"]) + dz / step * max_step
	p["x"] = nx
	p["z"] = nz
	p["yaw"] = float(msg.get("yaw", p["yaw"]))
	p["color"] = wrapi(int(msg.get("c", p["color"])), 0, 4)
	p["speed"] = clampf(float(msg.get("sp", 0.0)), 0.0, MAX_SPEED)
	p["stamina"] = clampf(float(msg.get("st", 1.0)), 0.0, 1.0)
	p["flash"] = bool(msg.get("fl", false))
	if p["role"] == "hider":
		var surface: float = ArenaData.surface_match(nx, nz, int(p["color"]), layout)
		var still: float = clampf(1.0 - p["speed"] / 3.0, 0.0, 1.0)
		p["hide"] = clampf(surface * 0.55 + still * 0.32 + 0.13, 0.0, 1.0)
	else:
		p["hide"] = 0.0


func try_tag(id: int) -> void:
	if phase != "playing" or not players.has(id):
		return
	var hunter: Dictionary = players[id]
	if hunter["role"] != "hunter" or not hunter["alive"]:
		return
	var best_id: int = -1
	var best_dist: float = 2.8
	for other_id in players.keys():
		if other_id == id:
			continue
		var p: Dictionary = players[other_id]
		if not p["alive"] or p["role"] == "hunter":
			continue
		var dx: float = float(p["x"]) - float(hunter["x"])
		var dz: float = float(p["z"]) - float(hunter["z"])
		var dist: float = sqrt(dx * dx + dz * dz)
		if dist < best_dist:
			best_dist = dist
			best_id = other_id
	if best_id == -1:
		return
	var target: Dictionary = players[best_id]
	target["alive"] = false
	if best_id == Net.local_id:
		GameState.alive = false
	hunter["score"] = int(hunter["score"]) + 120
	event_fired.emit("%s CAUGHT %s" % [hunter["name"], target["name"]], Color(1, 0.35, 0.4))
	Net.broadcast({"t": "event", "text": "%s CAUGHT %s" % [hunter["name"], target["name"]], "c": 1})
	if count_alive_hiders() == 0:
		end_round("hunter")


func count_alive_hiders() -> int:
	var n: int = 0
	for id in players.keys():
		var p: Dictionary = players[id]
		if p["alive"] and p["role"] == "hider":
			n += 1
	return n


func start_round() -> void:
	if not is_host:
		return
	if not is_offline and players.size() < 2:
		event_fired.emit("NEED AT LEAST 2 PLAYERS", Color(1, 0.7, 0.2))
		return
	seed = _rng.randi_range(1, 999999)
	layout = ArenaData.build(seed, map_index)
	var ids: Array = players.keys()
	hunter_id = int(ids[_rng.randi() % ids.size()])
	var spawns: Array = layout["spawns"]
	var i: int = 0
	for id in ids:
		var p: Dictionary = players[id]
		var sp: Vector3 = spawns[i % spawns.size()]
		p["x"] = sp.x + _rng.randf_range(-1.0, 1.0)
		p["z"] = sp.z + _rng.randf_range(-1.0, 1.0)
		p["yaw"] = atan2(-p["x"], -p["z"])
		p["color"] = _rng.randi() % 4
		p["speed"] = 0.0
		p["stamina"] = 1.0
		p["hide"] = 0.0
		p["alive"] = true
		p["flash"] = false
		p["role"] = "hunter" if id == hunter_id else "hider"
		i += 1
	time_left = ROUND_LENGTH
	GameState.alive = true
	GameState.score = 0
	phase = "playing"
	_set_phase("playing")
	role = "hunter" if Net.local_id == hunter_id else "hider"
	event_fired.emit("HUNTER IS %s - ROUND %d" % [players[hunter_id]["name"], round], Color(1, 0.8, 0.2))
	Net.broadcast({
		"t": "start", "round": round, "seed": seed, "map": map_index,
		"hunter": hunter_id, "tl": time_left,
		"players": player_list_msg()["players"],
	})
	round_started.emit()


func tick(delta: float) -> void:
	if phase != "playing":
		return
	time_left -= delta
	if is_offline:
		_tick_bots(delta)
	if time_left <= 0.0:
		time_left = 0.0
		end_round("hiders")
	if is_host:
		_snap_timer -= delta
		if _snap_timer <= 0.0:
			_snap_timer = 0.08
			Net.broadcast(snapshot_msg())


func snapshot_msg() -> Dictionary:
	var arr: Array = []
	for id in players.keys():
		var p: Dictionary = players[id]
		arr.append([
			id,
			sn(float(p["x"]), 2), sn(float(p["z"]), 2), sn(float(p["yaw"]), 2),
			int(p["color"]), sn(float(p["hide"]), 2),
			1 if p["alive"] else 0, int(p["score"]),
			1 if p["role"] == "hunter" else 0, sn(float(p["stamina"]), 2),
		])
	return {"t": "snap", "p": arr, "tl": sn(time_left, 1), "h": hunter_id}


func sn(value: float, digits: int) -> float:
	var mul: float = pow(10.0, digits)
	return roundf(value * mul) / mul


func apply_snapshot(msg: Dictionary) -> void:
	time_left = float(msg.get("tl", time_left))
	hunter_id = int(msg.get("h", hunter_id))
	var arr: Array = msg.get("p", [])
	for entry in arr:
		if not (entry is Array) or entry.size() < 10:
			continue
		var id: int = int(entry[0])
		if not players.has(id):
			_add_player(id, "PLAYER %d" % id, false)
		var p: Dictionary = players[id]
		p["x"] = float(entry[1]); p["z"] = float(entry[2]); p["yaw"] = float(entry[3])
		p["color"] = int(entry[4]); p["hide"] = float(entry[5])
		p["alive"] = bool(int(entry[6])); p["score"] = int(entry[7])
		p["role"] = "hunter" if bool(int(entry[8])) else "hider"
		p["stamina"] = float(entry[9])
	role = "hunter" if Net.local_id == hunter_id else "hider"
	var me: Dictionary = players.get(Net.local_id, {})
	if not me.is_empty():
		GameState.alive = bool(me["alive"])
		GameState.score = int(me["score"])


func end_round(winner: String) -> void:
	if phase != "playing":
		return
	phase = "roundend"
	_set_phase("roundend")
	for id in players.keys():
		var p: Dictionary = players[id]
		if p["role"] == "hider" and p["alive"]:
			p["score"] = int(p["score"]) + 150 + int(float(p["hide"]) * 100.0)
		elif p["role"] == "hunter" and winner == "hunter":
			p["score"] = int(p["score"]) + 200 + int(time_left * 2.0)
	last_results = []
	for id in players.keys():
		var p: Dictionary = players[id]
		last_results.append({
			"id": id, "name": p["name"], "score": int(p["score"]),
			"role": p["role"], "alive": p["alive"],
		})
	last_results.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	winner_text = "HUNTERS WIN" if winner == "hunter" else "HIDERS WIN"
	event_fired.emit(winner_text, Color(1, 0.85, 0.3))
	Net.broadcast({"t": "round_end", "results": last_results, "winner": winner_text})
	round_ended.emit(last_results)


func next_round() -> void:
	if not is_host:
		return
	if round >= total_rounds:
		phase = "matchover"
		_set_phase("matchover")
		Net.broadcast({"t": "match_over", "results": last_results})
		GameState.record_result(int(players.get(Net.local_id, {}).get("score", 0)), Net.local_id == hunter_id)
		return
	round += 1
	start_round()


func back_to_lobby() -> void:
	if not is_host:
		return
	phase = "lobby"
	round = 1
	for id in players.keys():
		var p: Dictionary = players[id]
		p["score"] = 0
		p["alive"] = true
	_set_phase("lobby")
	Net.broadcast(player_list_msg())


func client_message(msg: Dictionary) -> void:
	var t: String = str(msg.get("t", ""))
	match t:
		"welcome":
			Net.local_id = int(msg.get("id", 1))
			GameState.local_id = Net.local_id
			seed = int(msg.get("seed", 1))
			map_index = int(msg.get("map", 0))
			layout = ArenaData.build(seed, map_index)
			var list: Array = msg.get("players", [])
			for entry in list:
				if entry is Array and entry.size() >= 2:
					_add_player(int(entry[0]), str(entry[1]), false)
			password = str(msg.get("password", ""))
			phase = str(msg.get("phase", "lobby"))
			_set_phase(phase)
			event_fired.emit("AUTHENTICATED AS PLAYER %d" % Net.local_id, Color(0.4, 1, 0.7))
		"lobby":
			var list: Array = msg.get("players", [])
			for id in players.keys():
				if not list_has_id(list, id):
					players.erase(id)
			for entry in list:
				if entry is Array and entry.size() >= 2 and not players.has(int(entry[0])):
					_add_player(int(entry[0]), str(entry[1]), false)
			phase = str(msg.get("phase", "lobby"))
			round = int(msg.get("round", round))
			map_index = int(msg.get("map", map_index))
			_set_phase(phase)
		"start":
			round = int(msg.get("round", 1))
			seed = int(msg.get("seed", seed))
			map_index = int(msg.get("map", map_index))
			layout = ArenaData.build(seed, map_index)
			hunter_id = int(msg.get("hunter", 1))
			time_left = float(msg.get("tl", ROUND_LENGTH))
			var list: Array = msg.get("players", [])
			players.clear()
			for entry in list:
				if entry is Array and entry.size() >= 2:
					_add_player(int(entry[0]), str(entry[1]), false)
			phase = "playing"
			role = "hunter" if Net.local_id == hunter_id else "hider"
			GameState.alive = true
			GameState.score = 0
			_set_phase("playing")
			round_started.emit()
		"snap":
			apply_snapshot(msg)
		"event":
			event_fired.emit(str(msg.get("text", "")), GameState.color_for(int(msg.get("c", 2))))
		"chat":
			event_fired.emit("%s: %s" % [msg.get("from", "?"), msg.get("text", "")], Color(0.8, 0.9, 1))
		"left":
			players.erase(int(msg.get("id", -1)))
		"round_end":
			last_results = msg.get("results", [])
			winner_text = str(msg.get("winner", ""))
			phase = "roundend"
			_set_phase("roundend")
			round_ended.emit(last_results)
		"match_over":
			last_results = msg.get("results", [])
			phase = "matchover"
			_set_phase("matchover")
		"auth_fail", "kicked":
			auth_failed.emit(str(msg.get("reason", "Rejected by server")))


func list_has_id(list: Array, id: int) -> bool:
	for entry in list:
		if entry is Array and entry.size() >= 1 and int(entry[0]) == id:
			return true
	return false


func _set_phase(next: String) -> void:
	var changed: bool = phase != next
	phase = next
	GameState.phase = next
	if changed:
		phase_changed.emit(next)


func local_state() -> Dictionary:
	return players.get(Net.local_id, {})


func _tick_bots(delta: float) -> void:
	for id in players.keys():
		var p: Dictionary = players[id]
		if not p["bot"] or not p["alive"]:
			continue
		var target := Vector2(float(p["x"]), float(p["z"]))
		var move_speed: float = 4.2
		if p["role"] == "hunter":
			move_speed = 4.8
			var best: Dictionary = {}
			var best_d: float = 999.0
			for oid in players.keys():
				if oid == id:
					continue
				var o: Dictionary = players[oid]
				if not o["alive"]:
					continue
				var d: float = Vector2(float(o["x"]) - float(p["x"]), float(o["z"]) - float(p["z"])).length()
				if d < best_d:
					best_d = d
					best = o
			if not best.is_empty():
				target = Vector2(float(best["x"]), float(best["z"]))
				if best_d < 2.6:
					try_tag(id)
		else:
			var props: Array = layout.get("props", [])
			var nearest: Dictionary = {}
			var nearest_d: float = 999.0
			for prop in props:
				if int(prop["c"]) != int(p["color"]):
					continue
				var d: float = Vector2(float(prop["x"]) - float(p["x"]), float(prop["z"]) - float(p["z"])).length()
				if d < nearest_d:
					nearest_d = d
					nearest = prop
			if not nearest.is_empty() and nearest_d > 1.6:
				target = Vector2(float(nearest["x"]), float(nearest["z"]))
			elif _rng.randf() < 0.004:
				p["color"] = _rng.randi() % 4
		var delta_vec: Vector2 = target - Vector2(float(p["x"]), float(p["z"]))
		if delta_vec.length() > 0.15:
			var dir: Vector2 = delta_vec.normalized()
			var nx: float = float(p["x"]) + dir.x * move_speed * delta
			var nz: float = float(p["z"]) + dir.y * move_speed * delta
			var test := ArenaData.clamp_position(Vector3(nx, 0, nz))
			if not ArenaData.collides(test, layout):
				p["x"] = test.x
				p["z"] = test.z
			p["yaw"] = atan2(dir.x, dir.y)
			p["speed"] = move_speed
		else:
			p["speed"] = 0.0
		if p["role"] == "hider":
			var surface: float = ArenaData.surface_match(float(p["x"]), float(p["z"]), int(p["color"]), layout)
			p["hide"] = clampf(surface * 0.55 + 0.45, 0.0, 1.0)
