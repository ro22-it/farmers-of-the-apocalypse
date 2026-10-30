class_name SoundBank
extends RefCounted

## Все звуки игры. Записи — из бесплатных наборов CC0 (assets/audio, авторы в
## assets/CREDITS.md); у каждого события несколько вариантов и небольшой разброс
## высоты, чтобы шаги и удары не звучали одинаково. Чего нет в записях
## (хлопок выстрела, тетива рогатки, щелчок пустого ружья), собирается кодом.

const MIX_RATE := 22050
const DIR := "res://assets/audio/"

## Событие → варианты файлов
const FILES := {
	"step": ["step_1.ogg", "step_2.ogg", "step_3.ogg", "step_4.ogg", "step_5.ogg"],
	"growl": ["growl_1.ogg", "growl_2.ogg", "growl_3.ogg"],
	"goblin_hurt": ["goblin_hurt_1.ogg", "goblin_hurt_2.ogg", "goblin_hurt_3.ogg"],
	"goblin_death": ["goblin_death_1.ogg", "goblin_death_2.ogg"],
	"goblin_laugh": ["goblin_laugh_1.ogg", "goblin_laugh_2.ogg"],
	"giant_roar": ["giant_roar.ogg"],
	"giant_effort": ["giant_effort.ogg"],
	"giant_hurt": ["giant_hurt_1.ogg", "giant_hurt_2.ogg"],
	"giant_death": ["giant_death.ogg"],
	"punch": ["punch_1.ogg", "punch_2.ogg", "punch_3.ogg"],
	"bones": ["bones_1.ogg", "bones_2.ogg"],
	"squish": ["squish_1.ogg", "squish_2.ogg"],
	"shell": ["shell_1.ogg", "shell_2.ogg"],
	"car_door_open": ["car_door_open.ogg"],
	"car_door_close": ["car_door_close.ogg"],
	"door_open": ["door_open_1.ogg", "door_open_2.ogg"],
	"door_close": ["door_close_1.ogg", "door_close_2.ogg"],
	"bark": ["bark_1.ogg", "bark_2.ogg"],
	"metal_hit": ["metal_hit_1.ogg", "metal_hit_2.ogg"],
	"metal_drop": ["metal_drop.ogg"],
	"chop": ["chop.ogg"],
	"trap": ["metal_latch.ogg"],
	"click_metal": ["metal_click.ogg"],
	"coins": ["coins_1.ogg", "coins_2.ogg"],
	"pickup": ["pickup_1.ogg", "pickup_2.ogg"],
	"drop": ["drop.ogg"],
	"creak": ["creak_1.ogg", "creak_2.ogg"],
	"boom_strong": ["boom_strong.wav"],
	"boom_medium": ["boom_medium.wav"],
	"whoosh": ["whoosh.wav"],
	"splash": ["splash.wav"],
	"thud_deep": ["thud_deep.wav"],
	"ui_click": ["ui_click.ogg"],
	"ui_notify": ["ui_notify.ogg"],
	"spooky": ["spooky_1.ogg", "spooky_2.ogg", "spooky_3.ogg", "spooky_4.ogg", "spooky_5.ogg", "spooky_6.ogg", "spooky_7.ogg", "spooky_8.ogg"],
	"night_drone": ["night_drone.ogg"],
	"amb_day": ["amb_day.ogg"],
	"amb_night": ["amb_night.ogg"],
	"engine": ["engine_low.ogg"],
	"dawn_birds": ["dawn_birds.ogg"],
}
## Составные звуки: несколько слоёв одновременно
const LAYERS := {
	"shotgun": ["boom_strong", "shotgun_crack"],
	"rifle": ["boom_medium", "rifle_crack"],
	"twang": ["twang_tone", "whoosh"],
	"reload": ["click_metal", "shell"],
	"thud": ["thud_deep", "chop"],
	"fence_break": ["chop", "creak"],
	"creature_death": ["bones", "squish"],
}

static var _cache := {}


## Проиграть звук в точке мира у себя
static func play_at(tree: SceneTree, sound: String, position: Vector3, volume_db := 0.0) -> void:
	if tree.current_scene == null:
		return
	if LAYERS.has(sound):
		for layer in LAYERS[sound]:
			play_at(tree, layer, position, volume_db)
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = get_stream(sound)
	player.volume_db = volume_db
	player.pitch_scale = randf_range(0.92, 1.08)
	player.max_distance = 120.0
	player.unit_size = 8.0
	player.bus = &"Effects"
	tree.current_scene.add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()


## Проиграть звук для всех игроков. Вызывает хост: звук разошлётся через узел Sfx
static func everyone(tree: SceneTree, sound: String, position: Vector3, volume_db := 0.0) -> void:
	var sfx := tree.root.get_node_or_null("Sfx")
	if sfx:
		sfx.everyone(sound, position, volume_db)
	else:
		play_at(tree, sound, position, volume_db)


## Звук интерфейса: без положения в мире
static func play_ui(tree: SceneTree, sound: String, volume_db := -6.0) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = get_stream(sound)
	player.volume_db = volume_db
	player.bus = &"Effects"
	tree.root.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Зацикленная запись (фон, мотор)
static func loop_stream(sound: String) -> AudioStream:
	var stream: AudioStream = load(DIR + FILES[sound][0]).duplicate()
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	return stream


static func get_stream(sound: String) -> AudioStream:
	if FILES.has(sound):
		var variants: Array = FILES[sound]
		return load(DIR + variants[randi() % variants.size()])
	if not _cache.has(sound):
		_cache[sound] = _make(sound)
	return _cache[sound]


static func _make(sound: String) -> AudioStreamWAV:
	match sound:
		"shotgun_crack":
			return _noise_burst(0.45, 9.0, 0.35, 1.0)
		"rifle_crack":
			return _noise_burst(0.3, 16.0, 0.15, 0.9)
		"twang_tone":
			return _tone(0.18, 420.0, 140.0, 0.6)
		"click":
			return _noise_burst(0.03, 120.0, 0.0, 0.5)
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
