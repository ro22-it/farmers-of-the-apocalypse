class_name Weather
extends Node

## Погода ночи: туман, ливень, полнолуние. Какую — решает хост (DayNight.weather),
## а дождь, гром и звук каждый рисует у себя. Ливень сам поливает грядки,
## в полнолуние Грядочников и волчат больше (NightDirector).

## Шансы погоды, кроме полнолуния (оно по расписанию)
const CHANCES := {"clear": 5, "fog": 2, "rain": 2}
const FULL_MOON_NIGHTS := [7, 14]
const FOG_FACTOR := {"fog": 3.2, "rain": 1.8}
const FOG_COLOR := Color(0.3, 0.32, 0.34)
const MOON_FACTOR := {"full_moon": 2.8, "rain": 0.3, "fog": 0.6}
const NAMES := {"fog": "Туман", "rain": "Ливень", "full_moon": "Полнолуние"}
## Ливень держит грядки политыми
const RAIN_WATER_INTERVAL := 2.0
const RAIN_AREA := 30.0
const THUNDER_INTERVAL := Vector2(18.0, 40.0)

var _day_night: DayNight
var _rain: GPUParticles3D
var _rain_sound: AudioStreamPlayer
var _water_time := 0.0
var _thunder_time := 10.0
var _flash := 0.0


func _init(day_night: DayNight) -> void:
	_day_night = day_night


## Погода на ночь day (только хост). Первая ночь всегда ясная.
static func pick(day: int) -> String:
	if day in FULL_MOON_NIGHTS:
		return "full_moon"
	if day <= 1:
		return "clear"
	var total := 0
	for key in CHANCES:
		total += CHANCES[key]
	var roll := randi() % total
	for key in CHANCES:
		roll -= CHANCES[key]
		if roll < 0:
			return key
	return "clear"


static func announce_text(weather: String) -> String:
	match weather:
		"fog":
			return "Туман. Держитесь вместе — дальше десяти шагов ничего не видно"
		"rain":
			return "Ливень. Грядки польёт само, но тварей не слышно"
		"full_moon":
			return "Полнолуние. Светло, но из леса выйдет больше тварей"
	return ""


func _ready() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 1600
	_rain.lifetime = 1.2
	_rain.visibility_aabb = AABB(Vector3(-RAIN_AREA, -20.0, -RAIN_AREA), Vector3(RAIN_AREA * 2.0, 40.0, RAIN_AREA * 2.0))
	_rain.emitting = false
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(RAIN_AREA / 2.0, 0.5, RAIN_AREA / 2.0)
	process.direction = Vector3(0.1, -1.0, 0.0)
	process.spread = 3.0
	process.initial_velocity_min = 18.0
	process.initial_velocity_max = 22.0
	process.gravity = Vector3(0.0, -9.8, 0.0)
	_rain.process_material = process
	var drop := QuadMesh.new()
	drop.size = Vector2(0.02, 0.5)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.7, 0.75, 0.85, 0.35)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	drop.material = material
	_rain.draw_pass_1 = drop
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)

	_rain_sound = AudioStreamPlayer.new()
	_rain_sound.stream = SoundBank.loop_stream("rain")
	_rain_sound.bus = &"Ambience"
	_rain_sound.volume_db = -80.0
	add_child(_rain_sound)


func _process(delta: float) -> void:
	var raining := _day_night.weather == "rain" and _day_night.is_night()
	# Капли сыплются вокруг камеры, чтобы не заливать дождём всю карту
	var camera := get_viewport().get_camera_3d()
	if camera:
		_rain.global_position = camera.global_position + Vector3.UP * 12.0
	_rain.emitting = raining
	var target_db := -6.0 if raining else -80.0
	_rain_sound.volume_db = move_toward(_rain_sound.volume_db, target_db, delta * 30.0)
	if _rain_sound.volume_db > -79.0 and not _rain_sound.playing:
		_rain_sound.play()
	elif _rain_sound.volume_db <= -79.0 and _rain_sound.playing:
		_rain_sound.stop()
	if raining:
		_update_thunder(delta)
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			_water_plots(delta)


## Гром со вспышкой: у каждого свой, это только атмосфера
func _update_thunder(delta: float) -> void:
	_thunder_time -= delta
	if _thunder_time <= 0.0:
		_thunder_time = randf_range(THUNDER_INTERVAL.x, THUNDER_INTERVAL.y)
		_flash = 0.25
		var camera := get_viewport().get_camera_3d()
		if camera:
			SoundBank.play_at(get_tree(), "thunder", camera.global_position + Vector3(randf_range(-40, 40), 30.0, randf_range(-40, 40)), -4.0)
	if _flash > 0.0:
		_flash -= delta
		var environment := get_viewport().world_3d.environment if get_viewport().world_3d else null
		if environment:
			environment.ambient_light_energy += 2.5 * maxf(_flash, 0.0) / 0.25


func _water_plots(delta: float) -> void:
	_water_time -= delta
	if _water_time > 0.0:
		return
	_water_time = RAIN_WATER_INTERVAL
	for plot: Plot in get_tree().get_nodes_in_group("plots"):
		if plot.enabled and plot.state != Plot.State.UNTILLED:
			plot.moisture = maxf(plot.moisture, 1.0)
