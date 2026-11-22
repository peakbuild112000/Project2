extends RefCounted
## Authoritative round/role/score rules. Pure logic, no engine dependencies.

const MAX_ROUNDS := 3
const HIDE_SECONDS := 25.0
const SEEK_SECONDS := 100.0
const RESULT_SECONDS := 8.0

var ids: Array = []
var map_index := 0
var round := 1
var phase := "menu" # menu | hiding | seeking | round_end | match_end
var time_left := 0.0
var hunter_id := -1
var scores := {}
var found := {}
var rng := RandomNumberGenerator.new()

func setup(player_ids: Array, map: int) -> void:
	ids = player_ids.duplicate()
	map_index = map
	round = 1
	phase = "menu"
	scores.clear()
	for id in ids:
		scores[id] = 0
	rng.seed = int(Time.get_unix_time_from_system()) + map + ids.size()

func start_round() -> void:
	found.clear()
	for id in ids:
		found[id] = false
	hunter_id = ids[rng.randi() % ids.size()]
	phase = "hiding"
	time_left = HIDE_SECONDS

func update(delta: float) -> String:
	if phase == "menu" or phase == "match_end":
		return ""
	time_left -= delta
	if time_left > 0.0:
		return ""
	if phase == "hiding":
		phase = "seeking"
		time_left = SEEK_SECONDS
		return "seeking"
	if phase == "seeking":
		return finish(false)
	if phase == "round_end":
		if round >= MAX_ROUNDS:
			phase = "match_end"
			return "match_end"
		round += 1
		start_round()
		return "new_round"
	return ""

func finish(seeker_won: bool) -> String:
	phase = "round_end"
	time_left = RESULT_SECONDS
	if seeker_won:
		scores[hunter_id] = int(scores.get(hunter_id, 0)) + 2
	else:
		for id in ids:
			if id != hunter_id and not found.get(id, false):
				scores[id] = int(scores.get(id, 0)) + 1
	return "round_end"

func all_found() -> bool:
	for id in ids:
		if id != hunter_id and not found.get(id, false):
			return false
	return true

## The seeker merely SEEING a hider earns a point. Does not eliminate.
func spot() -> bool:
	if phase != "seeking":
		return false
	scores[hunter_id] = int(scores.get(hunter_id, 0)) + 1
	return true

## The seeker must SHOOT a hider to eliminate them.
func tag(hider_id: int) -> bool:
	if phase != "seeking":
		return false
	if hider_id == hunter_id or found.get(hider_id, false):
		return false
	if all_found():
		return false
	found[hider_id] = true
	scores[hunter_id] = int(scores.get(hunter_id, 0)) + 3
	if all_found():
		finish(true)
	return true

func snapshot() -> Dictionary:
	return {
		"phase": phase,
		"time": maxf(0.0, time_left),
		"round": round,
		"max_rounds": MAX_ROUNDS,
		"hunter": hunter_id,
		"map": map_index,
		"scores": scores.duplicate(),
		"found": found.duplicate(),
	}
