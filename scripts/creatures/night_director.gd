class_name NightDirector
extends Node

## Ночью выпускает существ из леса, на рассвете отправляет их обратно.
## Работает только на хосте.

const GRYADOCHNIK := preload("res://scenes/creatures/gryadochnik.tscn")
const TARAN := preload("res://scenes/creatures/taran.tscn")
const ROJ := preload("res://scenes/creatures/roj.tscn")
const PUGALSHIK := preload("res://scenes/creatures/pugalshik.tscn")
## Рой — со 2-й ночи, одна стая: 3 + по одному за две ночи, не больше 8
const ROJ_FIRST_NIGHT := 2
const ROJ_MAX := 8
## Пугальщик — с 4-й ночи, с 8-й их двое
const PUGALSHIK_FIRST_NIGHT := 4
const PUGALSHIK_SECOND_NIGHT := 8
## Стая выходит кучкой в таком радиусе
const SWARM_SPREAD := 2.5
## Тараны выходят с этой ночи: 1, потом ещё по одному каждые две ночи
const TARAN_FIRST_NIGHT := 3
## Опушка леса: деревья начинаются примерно с 32 м от центра
const SPAWN_RADIUS := 36.0
## За сколько секунд от начала ночи выходят все существа
const SPAWN_WINDOW := 120.0
## Выходят с юга, востока и запада: на севере дом и сарай загораживают путь
const SPAWN_ANGLE_FROM := -20.0
const SPAWN_ANGLE_TO := 200.0

@export var day_night_path: NodePath
@export var creatures_path: NodePath

## Кто и когда выйдет этой ночью: [секунда ночи, сцена, сколько], по возрастанию времени
var _queue: Array = []

@onready var _day_night: DayNight = get_node(day_night_path)
@onready var _creatures: Node3D = get_node(creatures_path)


func _ready() -> void:
	_day_night.phase_changed.connect(_on_phase_changed)


func _process(_delta: float) -> void:
	if not multiplayer.is_server() or _queue.is_empty() or not _day_night.is_night():
		return
	if _day_night.night_time() >= _queue[0][0]:
		var entry: Array = _queue.pop_front()
		var point := _random_edge_point()
		for i in entry[2]:
			var jitter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * SWARM_SPREAD if i > 0 else Vector3.ZERO
			spawn(entry[1], point + jitter)


func reset() -> void:
	_queue.clear()
	for creature in _creatures.get_children():
		_creatures.remove_child(creature)
		creature.queue_free()


func spawn_gryadochnik(at: Vector3) -> Gryadochnik:
	return spawn(GRYADOCHNIK, at)


func spawn_taran(at: Vector3) -> Taran:
	return spawn(TARAN, at)


func spawn(scene: PackedScene, at: Vector3) -> Creature:
	var creature: Creature = scene.instantiate()
	creature.position = at
	_creatures.add_child(creature, true)
	return creature


func _on_phase_changed(is_night: bool, day: int) -> void:
	if not multiplayer.is_server() or not _day_night.running:
		return
	_queue.clear()
	if is_night:
		for i in day + 1:
			_queue.append([randf_range(5.0, SPAWN_WINDOW), GRYADOCHNIK, 1])
		if day >= TARAN_FIRST_NIGHT:
			for i in 1 + (day - TARAN_FIRST_NIGHT) / 2:
				_queue.append([randf_range(30.0, SPAWN_WINDOW), TARAN, 1])
		if day >= ROJ_FIRST_NIGHT:
			_queue.append([randf_range(40.0, SPAWN_WINDOW), ROJ, mini(3 + (day - ROJ_FIRST_NIGHT) / 2, ROJ_MAX)])
		if day >= PUGALSHIK_FIRST_NIGHT:
			for i in (2 if day >= PUGALSHIK_SECOND_NIGHT else 1):
				_queue.append([randf_range(60.0, SPAWN_WINDOW + 60.0), PUGALSHIK, 1])
		_queue.sort_custom(func(a, b): return a[0] < b[0])
	else:
		for creature: Creature in _creatures.get_children():
			creature.dawn()
		for player: Player in get_tree().get_nodes_in_group("players"):
			if player.downed:
				player.revive(Player.REVIVE_HEALTH)


func _random_edge_point() -> Vector3:
	var angle := deg_to_rad(randf_range(SPAWN_ANGLE_FROM, SPAWN_ANGLE_TO))
	return Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RADIUS + Vector3(0.0, 0.3, 0.0)
