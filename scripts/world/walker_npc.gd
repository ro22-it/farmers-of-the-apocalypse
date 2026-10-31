class_name WalkerNpc
extends Node3D

## Ходячий персонаж без сети: житель деревни или нанятый работник фермы.
## Бродит между случайными точками вокруг центра, иногда машет игрокам.
## Работник (waters_plots) ходит по грядкам, а хост раз в несколько секунд
## поливает всё посаженное рядом — пока куплено улучшение.

const WATER_INTERVAL := 6.0
const WATER_RADIUS := 14.0
const WAVE_DISTANCE := 5.0

@export var class_id := "farmer"
@export var center := Vector3.ZERO
@export var radius := 10.0
@export var speed := 1.4
@export var waters_plots := false

## Поля, которые читает CharacterModel
var downed := false
var seated := false
var held_scene := ""

var _model: CharacterModel
var _target := Vector3.ZERO
var _wait := 0.0
var _water_time := 0.0
var _wave_time := 0.0


func _ready() -> void:
	if waters_plots:
		held_scene = "res://scenes/items/watering_can.tscn"
	_model = CharacterModel.new()
	add_child(_model)
	_model.setup(class_id, self)
	_target = global_position
	_wait = randf_range(0.0, 3.0)


func _physics_process(delta: float) -> void:
	if not _working():
		return
	var flat := _target - global_position
	flat.y = 0.0
	if flat.length() < 0.4:
		_wait -= delta
		if _wait <= 0.0:
			_pick_target()
	else:
		var step := flat.normalized() * speed * delta
		global_position += step if step.length() < flat.length() else flat
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), minf(6.0 * delta, 1.0))
	_wave_time -= delta
	if _wave_time <= 0.0:
		for player: Node3D in get_tree().get_nodes_in_group("players"):
			if player.global_position.distance_to(global_position) < WAVE_DISTANCE:
				_model.play_action("Wave" if not waters_plots else "Interact")
				_wave_time = 12.0
				break
	if waters_plots and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_water_time -= delta
		if _water_time <= 0.0:
			_water_time = WATER_INTERVAL
			_water()


func _pick_target() -> void:
	_wait = randf_range(2.0, 6.0)
	if waters_plots:
		var plots := get_tree().get_nodes_in_group("plots")
		if not plots.is_empty():
			_target = (plots.pick_random() as Node3D).global_position + Vector3(randf_range(-1.0, 1.0), 0.0, 1.2)
			return
	var angle := randf() * TAU
	_target = center + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(1.0, radius)


func _water() -> void:
	for plot: Plot in get_tree().get_nodes_in_group("plots"):
		if plot.enabled and plot.state == Plot.State.PLANTED and plot.global_position.distance_to(global_position) < WATER_RADIUS:
			plot.moisture = maxf(plot.moisture, 1.0)


## Работник трудится, только когда улучшение куплено (родитель — UpgradeToggle)
func _working() -> bool:
	var toggle := get_parent() as UpgradeToggle
	return toggle == null or toggle.active
