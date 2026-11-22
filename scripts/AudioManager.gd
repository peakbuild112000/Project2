extends Node
## Tiny procedural-audio dispatcher. All sounds are generated WAV files
## created by tools/generate_audio.py, so the project ships no external assets.

const AUDIO_DIR := "res://assets/audio/"
const SFX_NAMES := [
	"switch", "collect", "perfect", "hit", "fever",
	"start", "gameover", "tongue", "click", "jump",
]

var _sfx: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _cursor: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for name in SFX_NAMES:
		var stream: AudioStream = load(AUDIO_DIR + "sfx_" + name + ".wav")
		if stream != null:
			_sfx[name] = stream

	for i in 10:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_players.append(player)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Master"
	var music: AudioStream = load(AUDIO_DIR + "music_loop.wav")
	if music != null:
		if music is AudioStreamWAV:
			music.loop_mode = AudioStreamWAV.LOOP_FORWARD
		_music_player.stream = music
	_music_player.volume_db = -13.0
	add_child(_music_player)


func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not GameState.sound_enabled or _players.is_empty():
		return
	var stream: AudioStream = _sfx.get(name)
	if stream == null:
		return
	var player: AudioStreamPlayer = _players[_cursor]
	_cursor = (_cursor + 1) % _players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func play_music() -> void:
	if _music_player == null:
		return
	if not GameState.music_enabled:
		_music_player.stop()
		return
	if _music_player.stream != null and not _music_player.playing:
		_music_player.play()


func stop_music() -> void:
	if _music_player != null:
		_music_player.stop()


func toggle_sound() -> void:
	GameState.sound_enabled = not GameState.sound_enabled
	GameState.save_settings()
	if GameState.sound_enabled:
		play("click")


func toggle_music() -> void:
	GameState.music_enabled = not GameState.music_enabled
	GameState.save_settings()
	if GameState.music_enabled:
		play_music()
	else:
		stop_music()
