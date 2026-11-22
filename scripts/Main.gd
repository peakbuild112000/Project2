extends Node3D

## Game shell: menus, local controls, camera, networking glue and screen flow.

enum Screen { MENU, HOWTO, LOBBY, GAME, PAUSE, ROUND_END, MATCH_END }

var director := MatchDirector.new()
var arena := Arena.new()
var hud := GameHUD.new()
var camera: Camera3D

var screen: int = Screen.MENU
var avatars: Dictionary = {}
var local_pos: Vector3 = Vector3.ZERO
var local_yaw: float = 0.0
var local_speed: float = 0.0
var stamina: float = 1.0
var color_index: int = GameState.WHITE
var flashlight: bool = false
var pointer_dir: Vector2 = Vector2.ZERO
var map_choice: int = 0

var _ui: CanvasLayer
var _menu: Panel
var _howto: Panel
var _lobby: Panel
var _pause: Panel
var _results: Panel
var _match_end: Panel
var _name_edit: LineEdit
var _pass_edit: LineEdit
var _url_edit: LineEdit
var _port_edit: LineEdit
var _lobby_text: Label
var _password_text: Label
var _status_text: Label
var _results_text: Label
var _match_text: Label
var _map_text: Label
var _keys: Dictionary = {}
var _state_send_timer: float = 0.0
var _shake: float = 0.0
var _prev_screen: int = Screen.MENU
var _debug_print: bool = false


func _ready() -> void:
	randomize()
	add_child(director)
	add_child(arena)
	add_child(hud)
	hud.setup(director)
	hud.paint_selected.connect(_on_paint_selected)
	hud.move_input.connect(_on_move_input)

	camera = Camera3D.new()
	camera.fov = 62.0
	camera.near = 0.1
	camera.far = 250.0
	add_child(camera)
	camera.make_current()

	_build_ui()

	Net.status_changed.connect(_on_status)
	Net.peer_connected.connect(_on_peer_connected)
	Net.peer_disconnected.connect(_on_peer_disconnected)
	Net.message_received.connect(_on_net_message)
	Net.connection_failed.connect(_on_connection_failed)
	director.event_fired.connect(_on_event)
	director.phase_changed.connect(_on_phase)
	director.round_started.connect(_on_round_started)
	director.round_ended.connect(_on_round_ended)
	director.auth_failed.connect(_on_auth_failed)

	_show(Screen.MENU)
	_refill_fields()

	# Debug hooks used by headless smoke tests.
	var args: Array = OS.get_cmdline_user_args()
	_debug_print = args.has("--auto-join") or args.has("--auto-host")
	if args.has("--auto-practice"):
		_on_practice()
		call_deferred("_auto_start_round")
	elif args.has("--auto-host"):
		_pass_edit.text = "TEST12"
		_on_host()
	elif args.has("--auto-join"):
		_pass_edit.text = "TEST12"
		_url_edit.text = "ws://127.0.0.1:9080"
		call_deferred("_auto_join_delayed")
	elif args.has("--test-movement"):
		_on_practice()
		call_deferred("_run_movement_test")


func _auto_join_delayed() -> void:
	await get_tree().create_timer(1.5).timeout
	_on_join()


func _auto_start_round() -> void:
	director.start_round()
	print("SMOKE: phase=", director.phase, " players=", director.players.size(), " hunter=", director.hunter_id)


# Small headless check: prove that the movement math and the white default
# still work after any refactor. It is only used by the command-line test.
func _run_movement_test() -> void:
	director.start_round()
	var start: Vector3 = local_pos
	for i in 12:
		_apply_movement(1.0 / 60.0, Vector2.RIGHT, false)
	var distance: float = start.distance_to(local_pos)
	print("MOVE: distance=", roundf(distance * 100.0) / 100.0, " color=", color_index)


func _refill_fields() -> void:
	_name_edit.text = GameState.player_name
	_port_edit.text = "9080"
	_url_edit.text = Net.default_client_url()
	if _pass_edit.text.is_empty():
		_pass_edit.text = _random_password()


func _random_password() -> String:
	var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var out := ""
	for i in 6:
		out += chars[randi() % chars.length()]
	return out


func _style_box(color: Color, border: Color, radius: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.set_corner_radius_all(radius)
	return sb


func _panel(parent: Node, pos: Vector2, size: Vector2, color: Color = Color(0.015, 0.02, 0.06, 0.92)) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size
	p.add_theme_stylebox_override("panel", _style_box(color, Color(0.2, 0.55, 0.85, 0.6)))
	parent.add_child(p)
	return p


func _label(parent: Node, text: String, pos: Vector2, size: Vector2, font_size: int = 20, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.add_theme_font_size_override("font_size", font_size)
	l.modulate = color
	parent.add_child(l)
	return l


func _button(parent: Node, text: String, pos: Vector2, size: Vector2, callback: Callable, color: Color = Color(0.08, 0.24, 0.38)) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.add_theme_font_size_override("font_size", 20)
	var sb := _style_box(color, Color(0.35, 0.8, 1.0, 0.75), 8)
	b.add_theme_stylebox_override("normal", sb)
	var hover := _style_box(color.lightened(0.22), Color(0.8, 1, 1, 0.95), 8)
	b.add_theme_stylebox_override("hover", hover)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b


func _field(parent: Node, placeholder: String, pos: Vector2, size: Vector2, secret: bool = false) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.position = pos
	e.size = size
	e.secret = secret
	e.add_theme_font_size_override("font_size", 18)
	e.add_theme_stylebox_override("normal", _style_box(Color(0.03, 0.05, 0.11, 0.95), Color(0.2, 0.45, 0.7, 0.7), 6))
	parent.add_child(e)
	return e


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Menu panels still take clicks; empty space lets the game see the mouse.
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	# Main menu
	_menu = _panel(root, Vector2(340, 70), Vector2(600, 580))
	_label(_menu, "CHROMA", Vector2(0, 22), Vector2(600, 62), 58, Color(0.2, 0.9, 1)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(_menu, "CHAMELEON", Vector2(0, 78), Vector2(600, 62), 58, Color(1, 0.3, 0.65)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(_menu, "HIDE  -  PAINT  -  SURVIVE", Vector2(0, 144), Vector2(600, 28), 17, Color(0.8, 0.88, 1)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit = _field(_menu, "YOUR NAME", Vector2(60, 194), Vector2(480, 36))
	_pass_edit = _field(_menu, "SESSION PASSWORD", Vector2(60, 238), Vector2(230, 36))
	_port_edit = _field(_menu, "PORT", Vector2(306, 238), Vector2(105, 36))
	_url_edit = _field(_menu, "SERVER URL (JOIN)", Vector2(60, 282), Vector2(480, 36))
	_label(_menu, "Password + port are used when hosting. URL is used when joining.",
		Vector2(60, 322), Vector2(480, 22), 13, Color(0.55, 0.65, 0.8))
	_button(_menu, "PRACTICE (BOTS)", Vector2(60, 356), Vector2(480, 46), _on_practice, Color(0.08, 0.32, 0.25))
	_button(_menu, "HOST SESSION", Vector2(60, 410), Vector2(480, 46), _on_host, Color(0.28, 0.2, 0.05))
	_button(_menu, "JOIN SESSION", Vector2(60, 464), Vector2(480, 46), _on_join, Color(0.12, 0.2, 0.4))
	_button(_menu, "HOW TO PLAY", Vector2(60, 518), Vector2(230, 40), _on_howto, Color(0.16, 0.16, 0.24))
	_button(_menu, "QUIT", Vector2(310, 518), Vector2(230, 40), _on_quit, Color(0.24, 0.1, 0.12))
	_status_text = _label(_menu, "", Vector2(60, 560), Vector2(480, 20), 13, Color(1, 0.7, 0.4))

	# How to play
	_howto = _panel(root, Vector2(280, 70), Vector2(720, 580))
	_label(_howto, "HOW TO PLAY", Vector2(30, 24), Vector2(660, 44), 34, Color(0.3, 0.9, 1))
	var help := """
ONE player is randomly chosen as the HUNTER. Everyone else is a HIDER.

HIDERS
  - Press 1-4 (or mouse wheel) to paint yourself the same color as nearby props.
  - Stand still: movement destroys your camouflage.
  - Survive 1:45 and your team wins.

HUNTER
  - Press F for a flashlight that reveals camouflaged players.
  - Get close and press E (or right click) to TAG a hider.
  - Tag every hider before the timer ends.

ALL PLAYERS
  - WASD / arrows to move, SHIFT to sprint (uses stamina).
  - Each player uses their own screen: desktop or Web browser. No split screen.
  - The host PC is the server. Web players connect over wss:// via a tunnel.
"""
	var help_label := _label(_howto, help, Vector2(30, 86), Vector2(660, 420), 18, Color(0.85, 0.9, 1))
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(_howto, "BACK", Vector2(280, 520), Vector2(160, 44), func(): _show(Screen.MENU))

	# Lobby
	_lobby = _panel(root, Vector2(330, 100), Vector2(620, 520))
	_label(_lobby, "SESSION LOBBY", Vector2(30, 22), Vector2(560, 42), 34, Color(0.3, 0.9, 1))
	_password_text = _label(_lobby, "PASSWORD: ------", Vector2(30, 70), Vector2(560, 30), 22, Color(1, 0.85, 0.35))
	_map_text = _label(_lobby, "MAP: NEON ALLEY", Vector2(30, 106), Vector2(360, 28), 19, Color(0.8, 0.9, 1))
	_button(_lobby, "< MAP", Vector2(400, 102), Vector2(90, 34), _prev_map)
	_button(_lobby, "MAP >", Vector2(500, 102), Vector2(90, 34), _next_map)
	_lobby_text = _label(_lobby, "PLAYERS: 0", Vector2(30, 150), Vector2(560, 250), 19, Color(0.9, 0.95, 1))
	_button(_lobby, "START ROUND", Vector2(30, 410), Vector2(270, 48), _on_start_round, Color(0.1, 0.35, 0.2))
	var wait_label := _label(_lobby, "WAIT FOR HOST", Vector2(320, 410), Vector2(270, 48), 18, Color(0.7, 0.75, 0.85))
	wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(_lobby, "BACK TO MENU", Vector2(190, 466), Vector2(240, 40), _on_back_to_menu, Color(0.2, 0.14, 0.16))

	# Pause
	_pause = _panel(root, Vector2(460, 220), Vector2(360, 280))
	_label(_pause, "PAUSED", Vector2(0, 24), Vector2(360, 44), 36, Color(0.3, 0.9, 1)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(_pause, "RESUME", Vector2(60, 90), Vector2(240, 46), _on_resume)
	_button(_pause, "LEAVE MATCH", Vector2(60, 148), Vector2(240, 46), _on_back_to_menu, Color(0.25, 0.12, 0.14))

	# Round results
	_results = _panel(root, Vector2(330, 100), Vector2(620, 520))
	_label(_results, "ROUND OVER", Vector2(30, 22), Vector2(560, 42), 34, Color(1, 0.85, 0.3))
	_results_text = _label(_results, "", Vector2(30, 78), Vector2(560, 290), 19, Color(0.9, 0.95, 1))
	_button(_results, "NEXT ROUND", Vector2(30, 390), Vector2(270, 48), _on_next_round, Color(0.1, 0.35, 0.2))
	_button(_results, "BACK TO LOBBY", Vector2(320, 390), Vector2(270, 48), _on_back_lobby)

	# Match end
	_match_end = _panel(root, Vector2(330, 100), Vector2(620, 520))
	_label(_match_end, "MATCH OVER", Vector2(30, 22), Vector2(560, 42), 34, Color(1, 0.5, 0.3))
	_match_text = _label(_match_end, "", Vector2(30, 78), Vector2(560, 290), 19, Color(0.9, 0.95, 1))
	_button(_match_end, "PLAY AGAIN", Vector2(30, 390), Vector2(270, 48), _on_play_again, Color(0.1, 0.35, 0.2))
	_button(_match_end, "MAIN MENU", Vector2(320, 390), Vector2(270, 48), _on_back_to_menu)


func _show(next: int) -> void:
	if screen != next:
		_prev_screen = screen
	screen = next
	_menu.visible = next == Screen.MENU
	_howto.visible = next == Screen.HOWTO
	_lobby.visible = next == Screen.LOBBY
	_pause.visible = next == Screen.PAUSE
	_results.visible = next == Screen.ROUND_END
	_match_end.visible = next == Screen.MATCH_END
	hud.visible = next == Screen.GAME or next == Screen.PAUSE
	_refill_lobby()


func _refill_lobby() -> void:
	if director.players.is_empty():
		_lobby_text.text = "PLAYERS: 0"
		return
	var text: String = ""
	for id in director.players.keys():
		var p: Dictionary = director.players[id]
		var mark: String = "★ HUNTER" if int(id) == director.hunter_id else "HIDER"
		text += "%s  %-16s  %s\n" % [mark, str(p["name"]).substr(0, 16), "READY" if p["alive"] else "OUT"]
	_lobby_text.text = "PLAYERS (%d):\n\n%s" % [director.players.size(), text]
	_password_text.text = "SESSION PASSWORD: %s" % director.password
	_map_text.text = "MAP: %s" % GameState.map_name(map_choice)


func _on_status(text: String) -> void:
	if _debug_print:
		print("STATUS: ", text)
	_status_text.text = text


func _on_event(text: String, color: Color) -> void:
	if _debug_print:
		print("EVENT: ", text)
	hud.show_banner(text, color)
	_shake = 0.25


func _on_auth_failed(reason: String) -> void:
	_status_text.text = "REJECTED: " + reason
	hud.show_banner("REJECTED: " + reason, Color(1, 0.4, 0.4))


func _on_connection_failed(reason: String) -> void:
	if _debug_print:
		print("CONNECTION FAILED: ", reason)
	_status_text.text = "CONNECTION FAILED: " + (reason if not reason.is_empty() else "host unreachable")
	director.setup_client()


func _on_peer_connected(id: int) -> void:
	hud.show_banner("PLAYER %d CONNECTED" % id, Color(0.4, 1, 0.7))


func _on_peer_disconnected(id: int) -> void:
	if Net.mode == "server":
		director.remove_player(id)
		_refill_lobby()


func _on_net_message(id: int, msg: Dictionary) -> void:
	if _debug_print:
		print("NET[", id, "]: ", JSON.stringify(msg).substr(0, 180))
	if Net.mode == "server":
		director.host_message(id, msg)
	else:
		director.client_message(msg)
	_refill_lobby()


func _on_phase(phase: String) -> void:
	if phase == "lobby":
		_show(Screen.LOBBY)
	elif phase == "menu":
		_show(Screen.MENU)
	elif phase == "connecting":
		_show(Screen.LOBBY)
		_lobby_text.text = "CONNECTING...\n" + _url_edit.text
	elif phase == "matchover":
		_show(Screen.MATCH_END)
		_fill_results(_match_text)


func _on_round_started() -> void:
	arena.build(director.layout)
	var ids: Array = director.players.keys()
	var my_index: int = maxi(0, ids.find(Net.local_id))
	local_pos = arena.spawn_for(my_index)
	local_yaw = atan2(-local_pos.x, -local_pos.z)
	local_speed = 0.0
	stamina = 1.0
	flashlight = false
	pointer_dir = Vector2.ZERO
	map_choice = director.map_index
	var me: Dictionary = director.local_state()
	color_index = int(me.get("color", GameState.WHITE))
	for id in avatars.keys():
		avatars[id].queue_free()
	avatars.clear()
	_show(Screen.GAME)
	var role_text: String = "YOU ARE THE HUNTER" if director.role == "hunter" else "YOU ARE A HIDER"
	hud.show_banner("ROUND %d - %s" % [director.round, role_text],
		Color(1, 0.4, 0.3) if director.role == "hunter" else Color(0.4, 1, 0.7))
	AudioManager.play("start")


func _on_round_ended(_results: Array) -> void:
	_show(Screen.ROUND_END)
	_fill_results(_results_text)
	AudioManager.play("gameover")


func _fill_results(target: Label) -> void:
	var text: String = director.winner_text + "\n\n"
	var place: int = 1
	for entry in director.last_results:
		var mark: String = "HUNTER" if str(entry.get("role", "")) == "hunter" else "HIDER"
		text += "%d. %-16s %-7s %6d\n" % [place, str(entry.get("name", "?")).substr(0, 16), mark, int(entry.get("score", 0))]
		place += 1
	target.text = text


func _on_practice() -> void:
	_apply_identity()
	map_choice = map_choice % 3
	Net.start_offline()
	director.setup_host("", map_choice, true)
	_show(Screen.LOBBY)
	AudioManager.play("click")


func _on_host() -> void:
	_apply_identity()
	var pwd: String = _pass_edit.text.strip_edges()
	if pwd.is_empty():
		pwd = _random_password()
		_pass_edit.text = pwd
	var p: int = clampi(int(_port_edit.text), 1024, 65535)
	if not Net.start_server(p, pwd):
		return
	director.setup_host(pwd, map_choice, false)
	_show(Screen.LOBBY)
	AudioManager.play("start")


func _on_join() -> void:
	_apply_identity()
	var url: String = _url_edit.text.strip_edges()
	director.setup_client()
	if not Net.start_client(url, _pass_edit.text.strip_edges()):
		return
	_show(Screen.LOBBY)
	_lobby_text.text = "CONNECTING...\n" + url
	AudioManager.play("click")


func _apply_identity() -> void:
	var n: String = _name_edit.text.strip_edges().substr(0, 16)
	if not n.is_empty():
		GameState.player_name = n
	GameState.save_settings()


func _prev_map() -> void:
	map_choice = wrapi(map_choice - 1, 0, 3)
	director.map_index = map_choice
	_refill_lobby()
	AudioManager.play("click")


func _next_map() -> void:
	map_choice = wrapi(map_choice + 1, 0, 3)
	director.map_index = map_choice
	_refill_lobby()
	AudioManager.play("click")


func _on_start_round() -> void:
	if Net.mode == "server" or Net.mode == "offline":
		director.start_round()


func _on_next_round() -> void:
	if Net.mode == "server" or Net.mode == "offline":
		director.next_round()


func _on_play_again() -> void:
	if Net.mode == "server" or Net.mode == "offline":
		director.back_to_lobby()
		_show(Screen.LOBBY)


func _on_back_lobby() -> void:
	if Net.mode == "server" or Net.mode == "offline":
		director.back_to_lobby()


func _on_resume() -> void:
	_show(Screen.GAME)


func _on_back_to_menu() -> void:
	Net.stop()
	director.players.clear()
	director.phase = "menu"
	director.role = "hider"
	for id in avatars.keys():
		avatars[id].queue_free()
	avatars.clear()
	_show(Screen.MENU)


func _on_howto() -> void:
	_show(Screen.HOWTO)


func _on_quit() -> void:
	get_tree().quit()


func _pressed(code: int) -> bool:
	var down: bool = Input.is_key_pressed(code)
	var was: bool = bool(_keys.get(code, false))
	_keys[code] = down
	return down and not was


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP and screen == Screen.GAME:
		_paint(color_index + 1)
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and screen == Screen.GAME:
		_paint(color_index - 1)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and screen == Screen.GAME:
		_try_tag()


func _process(delta: float) -> void:
	var esc: bool = _pressed(KEY_ESCAPE)
	if esc:
		if screen == Screen.GAME:
			_show(Screen.PAUSE)
			return
		elif screen == Screen.PAUSE:
			_show(Screen.GAME)
			return
		elif screen not in [Screen.MENU, Screen.HOWTO]:
			_on_back_to_menu()
			return

	if screen == Screen.GAME:
		_update_local(delta)
		director.tick(delta)
		_update_avatars(delta)
		_update_camera(delta)
		_update_net_state(delta)
		_check_tag_range()
	else:
		_update_idle(delta)
		_update_avatars(delta)


func _update_local(delta: float) -> void:
	# Keyboard and the on-screen pad can be used at the same time. Adding the
	# vectors means holding two keys (or two buttons) still gives one speed.
	var dir: Vector2 = _keyboard_direction() + pointer_dir
	if dir.length() > 1.0:
		dir = dir.normalized()
	var sprint: bool = Input.is_key_pressed(KEY_SHIFT) and stamina > 0.05 and dir.length() > 0.0
	_apply_movement(delta, dir, sprint)
	_handle_action_keys()


func _keyboard_direction() -> Vector2:
	var x: float = 0.0
	var z: float = 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): z += 1.0
	return Vector2(x, z)


func _apply_movement(delta: float, dir: Vector2, sprint: bool) -> void:
	var moving: bool = dir.length() > 0.01
	var base: float = 4.5 if director.role == "hider" else 4.2
	var speed: float = base * (1.55 if sprint else 1.0)
	if sprint:
		stamina = maxf(0.0, stamina - delta * 0.3)
	else:
		stamina = minf(1.0, stamina + delta * 0.2)

	local_speed = speed if moving else 0.0
	if moving:
		local_pos = arena.move_with_collision(local_pos, Vector3(dir.x, 0, dir.y) * speed * delta)
		local_yaw = atan2(-dir.x, -dir.y)


func _handle_action_keys() -> void:
	if _pressed(KEY_1): _paint(0)
	if _pressed(KEY_2): _paint(1)
	if _pressed(KEY_3): _paint(2)
	if _pressed(KEY_4): _paint(3)
	if _pressed(KEY_5): _paint(GameState.WHITE)
	if _pressed(KEY_F) and director.role == "hunter":
		flashlight = not flashlight
		AudioManager.play("switch")
	if _pressed(KEY_E):
		_try_tag()


func _on_move_input(direction: Vector2) -> void:
	pointer_dir = direction


func _on_paint_selected(index: int) -> void:
	_paint(index)


func _paint(index: int) -> void:
	color_index = wrapi(index, 0, GameState.PALETTE.size())
	AudioManager.play("switch", -4.0, 0.9 + randf() * 0.25)
	_shake = maxf(_shake, 0.08)
	if avatars.has(Net.local_id):
		avatars[Net.local_id].paint_splash()


func _try_tag() -> void:
	if director.role != "hunter" or not director.near_target:
		return
	if Net.mode == "client":
		Net.send({"t": "tag"})
	else:
		director.try_tag(Net.local_id)
	AudioManager.play("hit")


func _check_tag_range() -> void:
	if director.role != "hunter":
		director.near_target = false
		return
	var found: bool = false
	for id in director.players.keys():
		if int(id) == Net.local_id:
			continue
		var p: Dictionary = director.players[id]
		if not p["alive"] or p["role"] == "hunter":
			continue
		var dx: float = float(p["x"]) - local_pos.x
		var dz: float = float(p["z"]) - local_pos.z
		if dx * dx + dz * dz < 7.8:
			found = true
			break
	director.near_target = found


func _update_net_state(delta: float) -> void:
	_state_send_timer -= delta
	if _state_send_timer > 0.0:
		return
	_state_send_timer = 1.0 / 15.0
	var msg: Dictionary = {
		"t": "state", "x": round_to(local_pos.x), "z": round_to(local_pos.z),
		"yaw": round_to(local_yaw), "c": color_index,
		"sp": round_to(local_speed), "st": round_to(stamina), "fl": flashlight,
	}
	if Net.mode == "client":
		Net.send(msg)
	elif Net.mode == "offline" or Net.mode == "server":
		director.update_state(Net.local_id, msg)


func round_to(v: float) -> float:
	return roundf(v * 100.0) / 100.0


func _update_avatars(delta: float) -> void:
	for id in director.players.keys():
		if not avatars.has(id):
			var p: Dictionary = director.players[id]
			var av := HumanAvatar.new()
			av.setup(int(id), str(p["name"]), int(id) == Net.local_id)
			add_child(av)
			av.global_position = Vector3(float(p["x"]), 0, float(p["z"]))
			avatars[id] = av
	var stale: Array = []
	for id in avatars.keys():
		if not director.players.has(id):
			stale.append(id)
	for id in stale:
		avatars[id].queue_free()
		avatars.erase(id)
	for id in avatars.keys():
		var p: Dictionary = director.players[id]
		if int(id) == Net.local_id:
			p["x"] = local_pos.x
			p["z"] = local_pos.z
			p["yaw"] = local_yaw
			p["color"] = color_index
			p["speed"] = local_speed
			p["stamina"] = stamina
			p["alive"] = GameState.alive
		var av: HumanAvatar = avatars[id]
		av.update_visual(delta, p, director.role, Net.local_id, flashlight, camera.global_position)


func _update_camera(delta: float) -> void:
	var focus: Vector3 = local_pos
	if not bool(GameState.alive) and director.players.has(director.hunter_id):
		var hp: Dictionary = director.players[director.hunter_id]
		focus = Vector3(float(hp["x"]), 0, float(hp["z"]))
	var desired: Vector3 = focus + Vector3(0, 6.8, 9.6)
	camera.global_position = camera.global_position.lerp(desired, clampf(delta * 5.0, 0.0, 1.0))
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.8)
		camera.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.12
	camera.look_at(focus + Vector3(0, 1.1, -1.8))


func _update_idle(delta: float) -> void:
	var t: float = Time.get_ticks_msec() * 0.0001
	var focus := Vector3(sin(t) * 4.0, 0, cos(t) * 4.0)
	var desired: Vector3 = Vector3(sin(t * 1.3) * 14.0, 8.5, cos(t * 1.3) * 14.0)
	camera.global_position = camera.global_position.lerp(desired, clampf(delta * 2.0, 0.0, 1.0))
	camera.look_at(focus)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.8)
