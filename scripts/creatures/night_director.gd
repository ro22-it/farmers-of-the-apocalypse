class_name NightDirector
extends Node

## Ночью выпускает существ из леса, на рассвете отправляет их обратно.
## Работает только на хосте. Пока существо одно — Грядочник.

const GRYADOCHNIK := preload("res://scenes/creatures/gryadochnik.tscn")
## Опушка леса: деревья начинаются примерно с 32 м от центра
const SPAWN_RADIUS := 36.0
## За сколько секунд от начала ночи выходят все существа
const SPAWN_WINDOW := 120.0
## Выходят с юга, востока и запада: на севере дом и сарай загораживают путь
const SPAWN_ANGLE_FROM := -20.0
const SPAWN_ANGLE_TO := 200.0

@export var day_night_path: NodePath
@export var creatures_path: NodePath

## Секунды ночи, когда выйдет следующее существо
var _queue: Array[float] = []

@onready var _day_night: DayNight = get_node(day_night_path)
@onready var _creatures: Node3D = get_node(creatures_path)


func _ready() -> void:
	_day_night.phase_changed.connect(_on_phase_changed)


func _process(_delta: float) -> void:
	if not multiplayer.is_server() or _queue.is_empty() or not _day_night.is_night():
		return
	if _day_night.night_time() >= _queue[0]:
		_queue.pop_front()
		spawn_gryadochnik(_random_edge_point())


func reset() -> void:
	_queue.clear()
	for creature in _creatures.get_children():
		_creatures.remove_child(creature)
		creature.queue_free()


func spawn_gryadochnik(at: Vector3) -> Gryadochnik:
	var creature: Gryadochnik = GRYADOCHNIK.instantiate()
	creature.position = at
	_creatures.add_child(creature, true)
	return creature


func _on_phase_changed(is_night: bool, day: int) -> void:
	if not multiplayer.is_server() or not _day_night.running:
		return
	_queue.clear()
	if is_night:
		for i in day + 1:
			_queue.append(randf_range(5.0, SPAWN_WINDOW))
		_queue.sort()
	else:
		for creature: Creature in _creatures.get_children():
			creature.dawn()


func _random_edge_point() -> Vector3:
	var angle := deg_to_rad(randf_range(SPAWN_ANGLE_FROM, SPAWN_ANGLE_TO))
	return Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RADIUS + Vector3(0.0, 0.3, 0.0)
