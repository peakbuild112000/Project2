extends CanvasLayer
## All interface elements, assembled in code so the project has no UI files.
## The whole UI lives on a fixed 1280x720 design surface that is centred and
## scaled to the current viewport, so any fixed resolution works correctly.

signal ui(action: String, value: int)
signal paint_color_changed(color: Color)
signal brush_changed(size: int)
signal pipette_toggled()

const DESIGN_W := 1280.0
const DESIGN_H := 720.0

var root: Control
var surface: Control
var menu_group: Control
var hud_group: Control
var result_group: Control
var menu_info: Label
var phase_label: Label
var time_label: Label
var role_label: Label
var hide_label: Label
var score_label: Label
var log_label: Label
var result_label: Label
var name_edit: LineEdit
var url_edit: LineEdit
var port_edit: LineEdit
var swatches: Array = []
var paint_panel: Panel
var color_picker: ColorPickerButton
var pipette_button: Button
var brush_buttons: Array = []
var _log_lines: Array = []

func _ready() -> void:
	layer = 20
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	surface = Control.new()
	surface.anchor_left = 0.5
	surface.anchor_top = 0.5
	surface.anchor_right = 0.5
	surface.anchor_bottom = 0.5
	surface.offset_left = -DESIGN_W * 0.5
	surface.offset_top = -DESIGN_H * 0.5
	surface.offset_right = DESIGN_W * 0.5
	surface.offset_bottom = DESIGN_H * 0.5
	surface.pivot_offset = Vector2(DESIGN_W * 0.5, DESIGN_H * 0.5)
	root.add_child(surface)

	if not get_viewport().size_changed.is_connected(_fit):
		get_viewport().size_changed.connect(_fit)
	call_deferred("_fit")

	_build_menu()
	_build_hud()
	_build_result()
	show_menu()

## Scale the design surface to fit any resolution while keeping the aspect ratio.
func _fit() -> void:
	if surface == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var s: float = minf(vp.x / DESIGN_W, vp.y / DESIGN_H)
	s = maxf(s, 0.2)
	surface.scale = Vector2(s, s)

func _make_group() -> Control:
	var g := Control.new()
	g.set_anchors_preset(Control.PRESET_FULL_RECT)
	surface.add_child(g)
	return g

func _place(c: Control, x: float, y: float, w: float, h: float, ax: float = 0.0, ay: float = 0.0) -> void:
	c.anchor_left = ax
	c.anchor_top = ay
	c.anchor_right = ax
	c.anchor_bottom = ay
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + w
	c.offset_bottom = y + h

func _panel(parent: Control, x: float, y: float, w: float, h: float, ax: float = 0.0, ay: float = 0.0, col: Color = Color(0.02, 0.03, 0.08, 0.88)) -> Panel:
	var p := Panel.new()
	_place(p, x, y, w, h, ax, ay)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = Color(0.10, 0.85, 0.95, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p

func _label(parent: Control, text: String, x: float, y: float, w: float, h: float, ax: float = 0.0, ay: float = 0.0, size: int = 18, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	_place(l, x, y, w, h, ax, ay)
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

func _button(parent: Control, text: String, action: String, value: int, x: float, y: float, w: float, h: float, ax: float = 0.0, ay: float = 0.0) -> Button:
	var b := Button.new()
	_place(b, x, y, w, h, ax, ay)
	b.text = text
	b.pressed.connect(_on_pressed.bind(action, value))
	parent.add_child(b)
	return b

func _input_line(parent: Control, placeholder: String, value: String, x: float, y: float, w: float, h: float) -> LineEdit:
	var e := LineEdit.new()
	_place(e, x, y, w, h, 0.5, 0.5)
	e.placeholder_text = placeholder
	e.text = value
	parent.add_child(e)
	return e

func _on_pressed(action: String, value: int) -> void:
	ui.emit(action, value)

func _on_color_changed(c: Color) -> void:
	paint_color_changed.emit(c)

func _on_brush_pressed(size: int) -> void:
	for b in brush_buttons:
		var sb: StyleBoxFlat = b.get_theme_stylebox("normal")
		if sb != null:
			sb.bg_color = Color(0.16, 0.20, 0.32)
	var btn: Button = brush_buttons[size]
	var active: StyleBoxFlat = btn.get_theme_stylebox("normal")
	if active != null:
		active.bg_color = Color(0.10, 0.85, 0.95, 0.55)
	brush_changed.emit([8, 20, 38][size])

func _build_menu() -> void:
	menu_group = _make_group()
	var bg := _panel(menu_group, -640, -360, 1280, 720, 0.5, 0.5, Color(0.01, 0.02, 0.06, 0.95))
	_label(bg, "CHROMA CHAMELEON", -300, -292, 600, 58, 0.5, 0.5, 42, Color(0.10, 0.85, 0.95))
	_label(bg, "Paint yourself. Blend in. Survive the seeker.", -300, -238, 600, 30, 0.5, 0.5, 18, Color(0.75, 0.82, 0.95))
	_button(bg, "PRACTICE (BOTS)", "practice", 0, -170, -170, 340, 48, 0.5, 0.5)
	_button(bg, "HOST SESSION", "host", 0, -170, -110, 340, 48, 0.5, 0.5)
	_button(bg, "JOIN SESSION", "join", 0, -170, -50, 340, 48, 0.5, 0.5)
	_button(bg, "HOW TO PLAY", "help", 0, -170, 10, 340, 48, 0.5, 0.5)
	name_edit = _input_line(bg, "Your name", "Player", -170, 82, 340, 38)
	url_edit = _input_line(bg, "ws://host:9080", "ws://127.0.0.1:9080", -170, 130, 340, 38)
	port_edit = _input_line(bg, "Port", "9080", -170, 178, 340, 38)
	menu_info = _label(bg, "", -300, 232, 600, 100, 0.5, 0.5, 16, Color(0.70, 0.90, 0.80))
	menu_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _build_hud() -> void:
	hud_group = _make_group()
	var top := _panel(hud_group, -430, -345, 860, 52, 0.5, 0.5)
	phase_label = _label(top, "", 14, 8, 260, 34, 0.0, 0.0, 20, Color(0.10, 0.85, 0.95))
	time_label = _label(top, "", 300, 6, 120, 38, 0.0, 0.0, 26, Color.WHITE)
	score_label = _label(top, "", 440, 8, 400, 34, 0.0, 0.0, 16, Color(0.85, 0.88, 1.0))
	role_label = _label(hud_group, "", -430, -284, 860, 44, 0.5, 0.5, 22, Color.WHITE)
	hide_label = _label(hud_group, "", -430, -246, 860, 38, 0.5, 0.5, 17, Color(0.45, 0.90, 0.25))
	_label(hud_group, "+", -12, -22, 24, 40, 0.5, 0.5, 24, Color(1, 1, 1, 0.55))
	log_label = _label(hud_group, "", -430, 95, 860, 60, 0.5, 0.5, 16, Color(0.90, 0.93, 1.0))
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Quick presets (click = instant full repaint).
	var palette := _panel(hud_group, -300, 306, 600, 50, 0.5, 0.5)
	for i in range(Core.COLORS.size()):
		var b := _button(palette, Core.COLOR_NAMES[i], "paint", i, -282 + i * 113, -14, 104, 30, 0.5, 0.5)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Core.COLORS[i]
		sb.set_corner_radius_all(6)
		b.add_theme_stylebox_override("normal", sb)
		swatches.append(b)

	# Unlimited-colour paint panel, shown while PAINT mode is active.
	paint_panel = _panel(hud_group, -330, 170, 660, 128, 0.5, 0.5, Color(0.03, 0.05, 0.12, 0.95))
	_label(paint_panel, "PAINT MODE  —  glisse sur ton personnage", -305, -48, 610, 24, 0.5, 0.5, 17, Color(0.10, 0.85, 0.95))
	color_picker = ColorPickerButton.new()
	_place(color_picker, -305, -12, 210, 44, 0.5, 0.5)
	color_picker.color = Color.WHITE
	color_picker.color_changed.connect(_on_color_changed)
	paint_panel.add_child(color_picker)

	pipette_button = _button(paint_panel, "Pipette OFF", "pipette", 0, -70, -12, 120, 44, 0.5, 0.5)
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.16, 0.20, 0.32)
	psb.set_corner_radius_all(6)
	pipette_button.add_theme_stylebox_override("normal", psb)

	_label(paint_panel, "Brosse", 72, -48, 100, 22, 0.5, 0.5, 14, Color(0.75, 0.82, 0.95))
	var names := ["Petit", "Moyen", "Grand"]
	for i in range(3):
		var bb := _button(paint_panel, names[i], "brush", i, 72 + i * 78, -12, 72, 44, 0.5, 0.5)
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(0.16, 0.20, 0.32) if i != 1 else Color(0.10, 0.85, 0.95, 0.55)
		bsb.set_corner_radius_all(6)
		bb.add_theme_stylebox_override("normal", bsb)
		bb.pressed.connect(_on_brush_pressed.bind(i))
		brush_buttons.append(bb)
	_label(paint_panel, "Clique-glisse pour peindre  •  Pipette : prélever une couleur  •  P pour quitter", -305, 42, 610, 24, 0.5, 0.5, 14, Color(0.70, 0.80, 0.95))
	paint_panel.visible = false

func _build_result() -> void:
	result_group = _make_group()
	var bg := _panel(result_group, -330, -150, 660, 300, 0.5, 0.5, Color(0.02, 0.03, 0.09, 0.94))
	result_label = _label(bg, "", -290, -120, 580, 230, 0.5, 0.5, 22, Color.WHITE)
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func set_paint_mode(on: bool) -> void:
	paint_panel.visible = on

func set_color(c: Color) -> void:
	color_picker.color = c

func set_pipette(on: bool) -> void:
	pipette_button.text = "Pipette ON" if on else "Pipette OFF"
	var sb: StyleBoxFlat = pipette_button.get_theme_stylebox("normal")
	if sb != null:
		sb.bg_color = Color(0.45, 0.90, 0.25, 0.55) if on else Color(0.16, 0.20, 0.32)

func show_menu() -> void:
	menu_group.visible = true
	hud_group.visible = false
	result_group.visible = false

func show_lobby(text: String) -> void:
	show_menu()
	menu_info.text = text

func show_game() -> void:
	menu_group.visible = false
	hud_group.visible = true
	result_group.visible = false

func show_result(text: String) -> void:
	menu_group.visible = false
	hud_group.visible = true
	result_group.visible = true
	result_label.text = text

func set_menu_info(text: String) -> void:
	menu_info.text = text

func update_hud(info: Dictionary) -> void:
	phase_label.text = str(info.get("phase", ""))
	time_label.text = "%02d" % int(info.get("time", 0))
	role_label.text = str(info.get("role", ""))
	hide_label.text = str(info.get("hide", ""))
	score_label.text = str(info.get("scores", ""))

func log_line(msg: String) -> void:
	_log_lines.append(msg)
	if _log_lines.size() > 4:
		_log_lines.pop_front()
	log_label.text = ""
	for line in _log_lines:
		log_label.text += str(line) + "\n"

func player_name() -> String:
	var n := name_edit.text.strip_edges()
	return n if not n.is_empty() else "Player"

func join_url() -> String:
	var u := url_edit.text.strip_edges()
	return u if not u.is_empty() else "ws://127.0.0.1:9080"

func host_port() -> int:
	return maxi(1, port_edit.text.to_int())
