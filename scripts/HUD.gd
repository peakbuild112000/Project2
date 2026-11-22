extends CanvasLayer
class_name GameHUD

## In-game overlay. The color swatches and the small movement pad are real
## buttons, so a player can paint and walk with the mouse alone. Keyboard
## controls still work; they are simply not required.

signal paint_selected(color_index: int)
signal move_input(direction: Vector2)

var director: MatchDirector

var _role_label: Label
var _timer_label: Label
var _score_label: Label
var _round_label: Label
var _hide_fill: ColorRect
var _hide_text: Label
var _stamina_fill: ColorRect
var _roster: VBoxContainer
var _banner: Label
var _tag_prompt: Label
var _flash_label: Label

var _swatches: Array[Button] = []
var _move_buttons: Dictionary = {}
var _held_directions: Dictionary = {}
var _built: bool = false
var _banner_time: float = 0.0


func setup(d: MatchDirector) -> void:
	director = d
	if not _built:
		_build()
	_built = true


func _style_box(color: Color, border: Color, radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.set_corner_radius_all(radius)
	return sb


func _panel(parent: Node, pos: Vector2, size: Vector2, color: Color = Color(0.02, 0.03, 0.09, 0.72), border: Color = Color(0.25, 0.5, 0.8, 0.55)) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size
	p.add_theme_stylebox_override("panel", _style_box(color, border))
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


func _icon_button(parent: Node, text: String, pos: Vector2, size: Vector2, bg: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_stylebox_override("normal", _style_box(bg, Color(1, 1, 1, 0.55), 6))
	b.add_theme_stylebox_override("hover", _style_box(bg.lightened(0.25), Color(1, 1, 1, 0.9), 6))
	b.add_theme_stylebox_override("pressed", _style_box(bg.darkened(0.25), Color(1, 1, 1, 0.9), 6))
	parent.add_child(b)
	return b


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Let clicks outside a button fall through to the 3D game (right-click tag).
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top := _panel(root, Vector2(24, 18), Vector2(1240, 74))
	_role_label = _label(top, "HIDER", Vector2(16, 8), Vector2(220, 34), 28, Color(0.4, 1, 0.7))
	_round_label = _label(top, "ROUND 1/3", Vector2(16, 42), Vector2(220, 26), 16, Color(0.7, 0.8, 0.95))
	_timer_label = _label(top, "1:45", Vector2(520, 6), Vector2(200, 50), 40, Color.WHITE)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label = _label(top, "SCORE 0", Vector2(1010, 12), Vector2(210, 28), 24, Color(1, 0.85, 0.35))
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_flash_label = _label(top, "FLASHLIGHT: F", Vector2(930, 44), Vector2(290, 24), 15, Color(0.8, 0.9, 1))
	_flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var roster_panel := _panel(root, Vector2(24, 108), Vector2(250, 210))
	var roster_title := _label(roster_panel, "PLAYERS", Vector2(12, 6), Vector2(220, 24), 16, Color(0.6, 0.8, 1))
	_roster = VBoxContainer.new()
	_roster.position = Vector2(12, 34)
	_roster.add_theme_constant_override("separation", 4)
	roster_panel.add_child(_roster)

	var bottom := _panel(root, Vector2(24, 596), Vector2(640, 104))
	_label(bottom, "PAINT - CLICK A COLOR", Vector2(12, 6), Vector2(280, 22), 15, Color(0.6, 0.8, 1))
	for i in GameState.PALETTE.size():
		var color: Color = GameState.color_for(i)
		var sw := _icon_button(bottom, "", Vector2(12 + i * 56, 32), Vector2(46, 26), color)
		sw.pressed.connect(_on_swatch_pressed.bind(i))
		_swatches.append(sw)
		var caption: String = "W" if i == GameState.WHITE else str(i + 1)
		_label(bottom, caption, Vector2(25 + i * 56, 62), Vector2(24, 20), 13, Color(0.8, 0.85, 1))

	_label(bottom, "CAMO", Vector2(300, 6), Vector2(80, 22), 15, Color(0.6, 0.8, 1))
	var hide_bg := ColorRect.new()
	hide_bg.position = Vector2(300, 32)
	hide_bg.size = Vector2(170, 18)
	hide_bg.color = Color(0.05, 0.08, 0.14, 0.9)
	bottom.add_child(hide_bg)
	_hide_fill = ColorRect.new()
	_hide_fill.position = Vector2(300, 32)
	_hide_fill.size = Vector2(0, 18)
	_hide_fill.color = Color(0.4, 1, 0.7)
	bottom.add_child(_hide_fill)
	_hide_text = _label(bottom, "0%", Vector2(480, 8), Vector2(60, 24), 15, Color.WHITE)

	_label(bottom, "STAMINA", Vector2(300, 58), Vector2(100, 22), 14, Color(0.6, 0.8, 1))
	var st_bg := ColorRect.new()
	st_bg.position = Vector2(400, 62)
	st_bg.size = Vector2(140, 10)
	st_bg.color = Color(0.05, 0.08, 0.14, 0.9)
	bottom.add_child(st_bg)
	_stamina_fill = ColorRect.new()
	_stamina_fill.position = Vector2(400, 62)
	_stamina_fill.size = Vector2(140, 10)
	_stamina_fill.color = Color(0.3, 0.8, 1.0)
	bottom.add_child(_stamina_fill)

	_build_move_pad(root)

	_banner = _label(root, "", Vector2(340, 150), Vector2(600, 60), 34, Color(1, 0.85, 0.3))
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag_prompt = _label(root, "", Vector2(490, 440), Vector2(300, 40), 22, Color(1, 0.4, 0.4))
	_tag_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint := _label(root, "CLICK A COLOR TO PAINT  |  WASD OR ARROWS TO MOVE  |  F FLASHLIGHT  |  E / RIGHT-CLICK TAG  |  ESC PAUSE",
		Vector2(140, 688), Vector2(1000, 24), 14, Color(0.6, 0.7, 0.85))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_move_pad(root: Node) -> void:
	var pad := _panel(root, Vector2(1010, 590), Vector2(230, 112))
	_label(pad, "MOUSE MOVE", Vector2(12, 4), Vector2(200, 22), 13, Color(0.6, 0.8, 1))
	var key_bg := Color(0.08, 0.18, 0.3, 0.95)
	var up := _icon_button(pad, "^", Vector2(90, 26), Vector2(48, 34), key_bg)
	var left := _icon_button(pad, "<", Vector2(38, 64), Vector2(48, 34), key_bg)
	var down := _icon_button(pad, "v", Vector2(90, 64), Vector2(48, 34), key_bg)
	var right := _icon_button(pad, ">", Vector2(142, 64), Vector2(48, 34), key_bg)
	_connect_pad_button(up, Vector2(0, -1))
	_connect_pad_button(left, Vector2(-1, 0))
	_connect_pad_button(down, Vector2(0, 1))
	_connect_pad_button(right, Vector2(1, 0))


func _connect_pad_button(button: Button, direction: Vector2) -> void:
	_move_buttons[button] = direction
	button.button_down.connect(_on_move_down.bind(button))
	button.button_up.connect(_on_move_up.bind(button))
	button.mouse_exited.connect(_on_move_exit.bind(button))


func _on_move_down(_button: Button) -> void:
	_held_directions[_button] = _move_buttons[_button]
	_emit_move()


func _on_move_up(button: Button) -> void:
	_held_directions.erase(button)
	_emit_move()


func _on_move_exit(button: Button) -> void:
	if _held_directions.has(button):
		_held_directions.erase(button)
		_emit_move()


func _emit_move() -> void:
	var direction := Vector2.ZERO
	for dir in _held_directions.values():
		direction += dir
	if direction.length() > 1.0:
		direction = direction.normalized()
	move_input.emit(direction)


func _on_swatch_pressed(index: int) -> void:
	paint_selected.emit(index)


func show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.modulate = color
	_banner_time = 2.6


func _process(delta: float) -> void:
	if not _built or director == null:
		return
	if _banner_time > 0.0:
		_banner_time -= delta
		_banner.modulate.a = clampf(_banner_time, 0.0, 1.0)
	else:
		_banner.text = ""

	var is_hunter: bool = director.role == "hunter"
	_role_label.text = "HUNTER" if is_hunter else "HIDER"
	_role_label.modulate = Color(1, 0.45, 0.35) if is_hunter else Color(0.4, 1, 0.7)
	_round_label.text = "ROUND %d/%d  -  %s" % [director.round, director.total_rounds, GameState.map_name(director.map_index)]
	var t: int = maxi(0, int(director.time_left))
	_timer_label.text = "%d:%02d" % [t / 60, t % 60]
	_timer_label.modulate = Color(1, 0.35, 0.3) if t < 20 else Color.WHITE

	var me: Dictionary = director.local_state()
	_score_label.text = "SCORE %d" % int(me.get("score", 0))
	var hide: float = clampf(float(me.get("hide", 0.0)), 0.0, 1.0)
	_hide_fill.size.x = 170.0 * hide
	_hide_fill.color = Color(1 - hide, 0.35 + hide * 0.6, 0.35)
	_hide_text.text = "%d%%" % int(hide * 100.0)
	_stamina_fill.size.x = 140.0 * clampf(float(me.get("stamina", 1.0)), 0.0, 1.0)

	var my_color: int = int(me.get("color", GameState.WHITE))
	for i in _swatches.size():
		var sw: Button = _swatches[i]
		var active: bool = i == my_color
		sw.scale = Vector2(1.16, 1.16) if active else Vector2.ONE
		sw.modulate = Color.WHITE if active else Color(0.55, 0.6, 0.7)

	# Only rebuild the roster when something in it actually changed.
	var sig: String = ""
	for id in director.players.keys():
		var p: Dictionary = director.players[id]
		sig += "%d:%s:%d:%d:%d;" % [
			id, p["name"], int(p["score"]),
			1 if p["alive"] else 0,
			1 if int(id) == director.hunter_id else 0,
		]
	if _roster.get_meta("sig", "") != sig:
		for child in _roster.get_children():
			child.queue_free()
		_roster.set_meta("sig", sig)
		for id in director.players.keys():
			var p: Dictionary = director.players[id]
			var row := Label.new()
			var mark: String = "★" if int(id) == director.hunter_id else "●"
			row.text = "%s %-14s %5d" % [mark, str(p["name"]).substr(0, 14), int(p["score"])]
			row.add_theme_font_size_override("font_size", 16)
			var col: Color = Color(1, 0.8, 0.25) if int(id) == director.hunter_id else GameState.color_for(int(p["color"]))
			row.modulate = col if p["alive"] else Color(0.4, 0.4, 0.45)
			_roster.add_child(row)

	_flash_label.visible = is_hunter
	_tag_prompt.text = "E - TAG!" if (is_hunter and director.near_target) else ""
