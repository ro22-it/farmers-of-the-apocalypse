class_name DayNight
extends Node

## Смена дня и ночи: время, свет, небо и туман.
## Время ведёт хост и раз в секунду рассылает его. Между обновлениями каждый
## двигает время сам, поэтому свет меняется плавно и без рывков.

signal phase_changed(is_night: bool, day: int)

const DAY_LENGTH := 480.0
const NIGHT_LENGTH := 300.0
const CYCLE := DAY_LENGTH + NIGHT_LENGTH
## Игра начинается утром, а не в момент рассвета
const START_TIME := 40.0
## Сколько секунд длятся рассвет и закат
const TWILIGHT := 45.0
const DAY_START_HOUR := 6.0
const DAY_HOURS := 14.0
const NIGHT_HOURS := 10.0

const SKY_TOP := [Color(0.42, 0.58, 0.78), Color(0.02, 0.03, 0.08)]
const SKY_HORIZON := [Color(0.82, 0.8, 0.72), Color(0.06, 0.07, 0.12)]
const FOG := [Color(0.78, 0.8, 0.76), Color(0.05, 0.06, 0.1)]
const FOG_DENSITY := [0.012, 0.03]
const AMBIENT := [0.8, 0.22]
const SUN_COLOR := Color(1.0, 0.94, 0.84)
const SUNSET_COLOR := Color(1.0, 0.55, 0.3)
const MOON_ENERGY := 0.22

@export var sun_path: NodePath
@export var moon_path: NodePath
@export var environment_path: NodePath

var day := 1
var cycle_time := START_TIME
## Идёт ли время. В меню не идёт, чтобы фон не превращался в ночь
var running := false

var _was_night := false

@onready var _sun: DirectionalLight3D = get_node(sun_path)
@onready var _moon: DirectionalLight3D = get_node(moon_path)
@onready var _environment: Environment = (get_node(environment_path) as WorldEnvironment).environment
@onready var _sky: ProceduralSkyMaterial = _environment.sky.sky_material


func _ready() -> void:
	add_to_group("day_night")
	add_to_group("graphics_quality")
	_sun.add_to_group("shadow_lights")
	_moon.add_to_group("shadow_lights")
	var settings := get_node_or_null("/root/Settings")
	if settings:
		settings.apply()
	_was_night = is_night()
	_apply_lighting()


func _process(delta: float) -> void:
	if running:
		cycle_time += delta
		if cycle_time >= CYCLE:
			cycle_time -= CYCLE
			# Номер дня у клиентов потом подтвердит хост
			day += 1
	if is_night() != _was_night:
		_was_night = is_night()
		phase_changed.emit(_was_night, day)
		get_tree().call_group("local_player", "on_phase_changed", _was_night, day)
	_apply_lighting()


func reset() -> void:
	day = 1
	cycle_time = START_TIME
	_was_night = false


## Отладка: за несколько секунд до ближайшего заката или рассвета
func skip_to_next_phase() -> void:
	cycle_time = (CYCLE if is_night() else DAY_LENGTH) - 3.0


## Эффекты экрана и дальность теней по качеству графики (вызывает Settings)
func apply_quality(level: int) -> void:
	_environment.ssao_enabled = level >= 2
	_environment.glow_enabled = level >= 1
	_sun.directional_shadow_max_distance = [40.0, 60.0, 80.0][clampi(level, 0, 2)]
	_moon.directional_shadow_max_distance = [30.0, 45.0, 60.0][clampi(level, 0, 2)]


func is_night() -> bool:
	return cycle_time >= DAY_LENGTH


## Сколько секунд прошло с начала текущей ночи
func night_time() -> float:
	return cycle_time - DAY_LENGTH if is_night() else 0.0


## 1 — полный день, 0 — ночь, между ними — рассвет и закат
func daylight() -> float:
	if is_night():
		return 0.0
	return minf(clampf(cycle_time / TWILIGHT, 0.0, 1.0), clampf((DAY_LENGTH - cycle_time) / TWILIGHT, 0.0, 1.0))


func get_clock_text() -> String:
	var hours: float
	if is_night():
		hours = DAY_START_HOUR + DAY_HOURS + night_time() / NIGHT_LENGTH * NIGHT_HOURS
	else:
		hours = DAY_START_HOUR + cycle_time / DAY_LENGTH * DAY_HOURS
	hours = fmod(hours, 24.0)
	var minutes := int(fmod(hours, 1.0) * 60.0) / 10 * 10
	return "%s %d · %02d:%02d" % ["Ночь" if is_night() else "День", day, int(hours), minutes]


func _apply_lighting() -> void:
	var light := daylight()
	var night := 1.0 - light
	# Солнце идёт с востока на запад, у горизонта краснеет
	var progress := clampf(cycle_time / DAY_LENGTH, 0.0, 1.0)
	_sun.rotation = Vector3(-deg_to_rad(lerpf(8.0, 172.0, progress)), deg_to_rad(-35.0), 0.0)
	var low_sun := 1.0 - sin(progress * PI)
	_sun.light_color = SUN_COLOR.lerp(SUNSET_COLOR, low_sun * low_sun)
	_sun.light_energy = 1.1 * light
	_sun.visible = light > 0.0
	_moon.light_energy = MOON_ENERGY * night
	_moon.visible = night > 0.0

	_sky.sky_top_color = SKY_TOP[0].lerp(SKY_TOP[1], night)
	_sky.sky_horizon_color = SKY_HORIZON[0].lerp(SKY_HORIZON[1], night)
	_sky.ground_horizon_color = _sky.sky_horizon_color
	_environment.fog_light_color = FOG[0].lerp(FOG[1], night)
	_environment.fog_density = lerpf(FOG_DENSITY[0], FOG_DENSITY[1], night)
	_environment.ambient_light_energy = lerpf(AMBIENT[0], AMBIENT[1], night)
