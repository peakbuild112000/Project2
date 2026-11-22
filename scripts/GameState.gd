extends Node
## Persistent profile/settings and lightweight local match state.
## Autoloaded as `GameState`.

signal settings_changed()

# Index 4 is the clean, unpainted look every player starts with. The first
# four colors are the paints that match the props in the arena.
const PALETTE := [
	Color(0.10, 0.90, 1.00), # 0 CYAN
	Color(1.00, 0.25, 0.62), # 1 PINK
	Color(1.00, 0.78, 0.15), # 2 GOLD
	Color(0.42, 1.00, 0.35), # 3 LIME
	Color(0.94, 0.94, 0.96), # 4 WHITE (unpainted)
]
const COLOR_NAMES := ["CYAN", "PINK", "GOLD", "LIME", "WHITE"]
const WHITE: int = 4
const MAP_NAMES := ["NEON ALLEY", "SUNSET CANYON", "FROZEN VAULT"]
const SAVE_PATH := "user://chroma_chameleon.cfg"

var player_name: String = "CHAMELEON"
var sound_enabled: bool = true
var music_enabled: bool = true
var sensitivity: float = 1.0
var best_hunter_score: int = 0
var best_hider_score: int = 0
var matches_played: int = 0

var local_id: int = 1
var role: String = "hider"
var hunter_id: int = 1
var map_index: int = 0
var round: int = 1
var total_rounds: int = 3
var score: int = 0
var alive: bool = true

var players: Dictionary = {}
var phase: String = "menu"
var time_left: float = 0.0
var session_password: String = ""


func _ready() -> void:
	load_save()


func load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	player_name = str(cfg.get_value("profile", "name", "CHAMELEON"))
	sound_enabled = bool(cfg.get_value("settings", "sound", true))
	music_enabled = bool(cfg.get_value("settings", "music", true))
	sensitivity = float(cfg.get_value("settings", "sensitivity", 1.0))
	best_hunter_score = int(cfg.get_value("records", "hunter", 0))
	best_hider_score = int(cfg.get_value("records", "hider", 0))
	matches_played = int(cfg.get_value("records", "matches", 0))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "name", player_name)
	cfg.set_value("settings", "sound", sound_enabled)
	cfg.set_value("settings", "music", music_enabled)
	cfg.set_value("settings", "sensitivity", sensitivity)
	cfg.set_value("records", "hunter", best_hunter_score)
	cfg.set_value("records", "hider", best_hider_score)
	cfg.set_value("records", "matches", matches_played)
	cfg.save(SAVE_PATH)
	settings_changed.emit()


func record_result(final_score: int, was_hunter: bool) -> void:
	matches_played += 1
	if was_hunter and final_score > best_hunter_score:
		best_hunter_score = final_score
	elif not was_hunter and final_score > best_hider_score:
		best_hider_score = final_score
	save_settings()


func color_for(index: int) -> Color:
	return PALETTE[wrapi(index, 0, PALETTE.size())]


func color_name(index: int) -> String:
	return COLOR_NAMES[wrapi(index, 0, COLOR_NAMES.size())]


func map_name(index: int) -> String:
	return MAP_NAMES[wrapi(index, 0, MAP_NAMES.size())]
