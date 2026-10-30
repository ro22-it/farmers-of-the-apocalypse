class_name SoundBank
extends RefCounted

## Звуки, сгенерированные кодом: пока нет своих записей, выстрелы и щелчки
## собираются из шума и тонов. Каждый звук создаётся один раз.

const MIX_RATE := 22050

static var _cache := {}


## Проиграть звук в точке мира (для всех, кто рядом)
static func play_at(tree: SceneTree, sound: String, position: Vector3, volume_db := 0.0) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = get_stream(sound)
	player.volume_db = volume_db
	player.max_distance = 120.0
	player.unit_size = 8.0
	tree.current_scene.add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()


static func get_stream(sound: String) -> AudioStreamWAV:
	if not _cache.has(sound):
		_cache[sound] = _make(sound)
	return _cache[sound]


static func _make(sound: String) -> AudioStreamWAV:
	match sound:
		"shotgun":
			return _noise_burst(0.45, 9.0, 0.35, 1.0)
		"rifle":
			return _noise_burst(0.3, 16.0, 0.15, 0.9)
		"twang":
			return _tone(0.18, 420.0, 140.0, 0.6)
		"click":
			return _noise_burst(0.03, 120.0, 0.0, 0.5)
		"reload":
			return _noise_burst(0.06, 60.0, 0.6, 0.6)
		"thud":
			return _tone(0.25, 90.0, 40.0, 0.9)
	return _noise_burst(0.05, 50.0, 0.5, 0.3)


## Шум с затуханием. smooth 0..1 — сглаживание (глуше и «тяжелее»)
static func _noise_burst(length: float, decay: float, smooth: float, volume: float) -> AudioStreamWAV:
	var count := int(length * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(length, decay))
	var previous := 0.0
	for i in count:
		var t := float(i) / MIX_RATE
		var sample := rng.randf_range(-1.0, 1.0)
		previous = lerpf(sample, previous, smooth)
		var value := previous * exp(-t * decay) * volume
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	return _wav(data)


## Тон, скользящий по частоте (щелчок резинки рогатки, глухой удар)
static func _tone(length: float, from_hz: float, to_hz: float, volume: float) -> AudioStreamWAV:
	var count := int(length * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in count:
		var k := float(i) / count
		phase += TAU * lerpf(from_hz, to_hz, k) / MIX_RATE
		var value := sin(phase) * (1.0 - k) * volume
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	return _wav(data)


static func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.data = data
	return stream
