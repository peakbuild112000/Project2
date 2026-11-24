extends Node
## Original, generated-only helpers: palette, maps, procedural textures and sounds.
## No external art or audio files are used anywhere in this project.

## Prop palette only. Hider suits start white and can use any colour from the
## picker; there are no fixed paint presets any more.
const COLORS = [
	Color(0.10, 0.85, 0.95), # 0 cyan
	Color(0.95, 0.25, 0.65), # 1 pink
	Color(0.98, 0.78, 0.15), # 2 gold
	Color(0.45, 0.90, 0.25), # 3 lime
	Color(0.93, 0.93, 0.93), # 4 white
]

const MAPS = [
	{
		"name": "Neon Alley",
		"floor": Color(0.045, 0.055, 0.11),
		"wall": Color(0.09, 0.11, 0.22),
		"accent": Color(0.10, 0.85, 0.95),
		"props": [0, 1, 3],
		"crates": 44, "cylinders": 10, "platforms": 7,
		"lockers": 16, "spheres": 6, "panels": 20,
	},
	{
		"name": "Sunset Foundry",
		"floor": Color(0.30, 0.14, 0.08),
		"wall": Color(0.42, 0.20, 0.11),
		"accent": Color(0.98, 0.66, 0.15),
		"props": [2, 3, 0],
		"crates": 30, "cylinders": 24, "platforms": 14,
		"lockers": 8, "spheres": 10, "panels": 8,
	},
	{
		"name": "Glacier Depot",
		"floor": Color(0.48, 0.62, 0.74),
		"wall": Color(0.58, 0.72, 0.84),
		"accent": Color(0.10, 0.85, 0.95),
		"props": [0, 4, 1],
		"crates": 52, "cylinders": 12, "platforms": 8,
		"lockers": 18, "spheres": 8, "panels": 10,
	},
	{
		"name": "Overhead Studio",
		"floor": Color(0.72, 0.75, 0.80),
		"wall": Color(0.84, 0.86, 0.90),
		"accent": Color(1.0, 1.0, 1.0),
		"props": [4, 2, 0],
		"crates": 20, "cylinders": 8, "platforms": 12,
		"lockers": 4, "spheres": 6, "panels": 28,
		"ceiling_lights": true,
	},
]

const SAMPLE_RATE := 22050
var _sound_cache := {}
var _texture_cache := {}

func _ready() -> void:
	pass

# ---------------------------------------------------------------- audio ----

func sfx(kind: String) -> AudioStreamWAV:
	if _sound_cache.has(kind):
		return _sound_cache[kind]
	var stream: AudioStreamWAV
	match kind:
		"click": stream = _tone(680.0, 0.07, "square", 0.16)
		"paint": stream = _sweep(280.0, 880.0, 0.18, 0.20)
		"flash": stream = _sweep(950.0, 240.0, 0.13, 0.16)
		"tag": stream = _tone(190.0, 0.22, "saw", 0.26)
		"found": stream = _arp([523.0, 659.0, 784.0], 0.10, 0.20)
		"win": stream = _arp([523.0, 659.0, 784.0, 1047.0], 0.13, 0.22)
		"lose": stream = _arp([392.0, 330.0, 262.0], 0.17, 0.22)
		"step": stream = _noise(0.05, 0.07)
		_ : stream = _tone(440.0, 0.10, "sine", 0.18)
	_sound_cache[kind] = stream
	return stream

func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clamp(samples[i], -1.0, 1.0) * 30000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream

func _tone(freq: float, dur: float, kind: String, vol: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var n: int = int(SAMPLE_RATE * dur)
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var v := 0.0
		match kind:
			"square": v = sign(sin(TAU * freq * t))
			"saw": v = 2.0 * fmod(freq * t, 1.0) - 1.0
			"triangle": v = 2.0 * absf(2.0 * fmod(freq * t, 1.0) - 1.0) - 1.0
			_ : v = sin(TAU * freq * t)
		var env := 1.0 - float(i) / float(n)
		out.append(v * vol * env)
	return _to_stream(out)

func _sweep(f0: float, f1: float, dur: float, vol: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var n: int = int(SAMPLE_RATE * dur)
	var phase := 0.0
	for i in range(n):
		var k := float(i) / float(n)
		var freq := f0 + (f1 - f0) * k
		phase += TAU * freq / float(SAMPLE_RATE)
		out.append(sin(phase) * vol * (1.0 - k))
	return _to_stream(out)

func _arp(freqs: Array, step: float, vol: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for f in freqs:
		var n: int = int(SAMPLE_RATE * step)
		for i in range(n):
			var t := float(i) / float(SAMPLE_RATE)
			var env := 1.0 - float(i) / float(n)
			out.append(sin(TAU * float(f) * t) * vol * env)
	return _to_stream(out)

func _noise(dur: float, vol: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var n: int = int(SAMPLE_RATE * dur)
	for i in range(n):
		out.append((rng.randf() * 2.0 - 1.0) * vol * (1.0 - float(i) / float(n)))
	return _to_stream(out)

# -------------------------------------------------------------- textures ----

func texture(seed: int, base: Color, accent: Color) -> ImageTexture:
	var key := "%d_%s_%s" % [seed, base.to_html(false), accent.to_html(false)]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for y in range(128):
		for x in range(128):
			var n := rng.randf()
			var c := base.lerp(accent, n * 0.22)
			if (x + y) % 32 < 2:
				c = c.lerp(accent, 0.45)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_texture_cache[key] = tex
	return tex

func material(color: Color, tex: Texture = null, alpha: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.roughness = 0.82
	mat.metallic = 0.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if tex != null:
		mat.albedo_texture = tex
	return mat
