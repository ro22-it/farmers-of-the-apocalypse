extends Node

## Фон: днём лес с птицами, ночью ночной лес и время от времени жуткие звуки
## из чащи вокруг игрока. У каждого игрока свой — по сети не передаётся.

const DAY_VOLUME := -12.0
const NIGHT_VOLUME := -8.0
## Как далеко в лесу звучат ночные звуки и как часто
const SPOOKY_DISTANCE := Vector2(25.0, 45.0)
const SPOOKY_INTERVAL := Vector2(6.0, 15.0)

var _day: AudioStreamPlayer
var _night: AudioStreamPlayer
var _next_spooky := 8.0


func _ready() -> void:
	_day = _make_loop("amb_day")
	_night = _make_loop("amb_night")
	var day_night := _day_night()
	if day_night:
		day_night.phase_changed.connect(_on_phase_changed)


func _process(delta: float) -> void:
	var day_night := _day_night()
	if day_night == null:
		return
	var light := day_night.daylight()
	_day.volume_db = linear_to_db(maxf(light, 0.001)) + DAY_VOLUME
	_night.volume_db = linear_to_db(maxf(1.0 - light, 0.001)) + NIGHT_VOLUME
	if not day_night.is_night():
		return
	_next_spooky -= delta
	if _next_spooky > 0.0:
		return
	_next_spooky = randf_range(SPOOKY_INTERVAL.x, SPOOKY_INTERVAL.y)
	var listener := get_tree().get_first_node_in_group("local_player") as Node3D
	if listener == null:
		return
	var angle := randf() * TAU
	var where := listener.global_position + Vector3(cos(angle), 0.5, sin(angle)) * randf_range(SPOOKY_DISTANCE.x, SPOOKY_DISTANCE.y)
	SoundBank.play_at(get_tree(), "spooky", where, randf_range(-4.0, 2.0))


func _on_phase_changed(is_night: bool, _day_number: int) -> void:
	SoundBank.play_ui(get_tree(), "night_drone" if is_night else "dawn_birds", -4.0)
	_next_spooky = 4.0


func _make_loop(sound: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = SoundBank.loop_stream(sound)
	player.volume_db = -80.0
	player.bus = &"Ambience"
	add_child(player)
	player.play()
	return player


func _day_night() -> DayNight:
	return get_tree().get_first_node_in_group("day_night") as DayNight
