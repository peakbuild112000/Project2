extends RefCounted
## Authoritative round / role / elimination rules. Pure logic, no engine dependencies.
## There is no scoring system: the seeker eliminates hiders, nothing else.

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
var found := {}
var rng := RandomNumberGenerator.new()

func setup(player_ids: Array, map: int) -> void:
	ids = player_ids.duplicate()
	map_index = map
	round = 1
	phase = "menu"
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
		return finish()
	if phase == "round_end":
		if round >= MAX_ROUNDS:
			phase = "match_end"
			return "match_end"
		round += 1
		start_round()
		return "new_round"
	return ""

func finish() -> String:
	phase = "round_end"
	time_left = RESULT_SECONDS
	return "round_end"

func all_found() -> bool:
	for id in ids:
		if id != hunter_id and not found.get(id, false):
			return false
	return true

## Instant elimination. Called when the seeker spots or shoots a hider.
func tag(hider_id: int) -> bool:
	if phase != "seeking":
		return false
	if hider_id == hunter_id or found.get(hider_id, false):
		return false
	if all_found():
		return false
	found[hider_id] = true
	if all_found():
		finish()
	return true

func snapshot() -> Dictionary:
	return {
		"phase": phase,
		"time": maxf(0.0, time_left),
		"round": round,
		"max_rounds": MAX_ROUNDS,
		"hunter": hunter_id,
		"map": map_index,
		"found": found.duplicate(),
	}
