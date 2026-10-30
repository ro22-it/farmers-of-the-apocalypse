class_name Cow
extends CharacterBody3D

## Корова: бродит по двору и раз в день (с рассвета) даёт молоко — E.
## Слушается только Скотника: по его свисту идёт за ним.
## Решения принимает хост, остальным приходят положение и «есть ли молоко».

const WANDER_SPEED := 1.2
const FOLLOW_SPEED := 3.8
const FOLLOW_DISTANCE := 2.5
## Пастбище — юго-восточный угол фермы: в стороне от грядок, ящиков и дороги пикапа
const PASTURE_MIN := Vector2(13.0, 7.0)
const PASTURE_MAX := Vector2(22.0, 21.0)
const MILK_SCENE := "res://scenes/items/milk_bottle.tscn"

@export var display_name := "Корова"

## Можно ли сегодня подоить. Синхронизируется для подсказки.
var milk_ready := true
## Корову можно выключить: так стоит та, что ещё не куплена (общие улучшения)
var enabled := true

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _target := Vector3.ZERO
var _wait := 0.0
var _leader: Node3D = null
var _follow_left := 0.0
var _start: Transform3D
var _anim_time := 0.0
var _last_cycle := 0.0

@onready var _model: Node3D = $Model


func _ready() -> void:
	add_to_group("animals")
	add_to_group("cows")
	_start = transform
	_target = global_position
	var day_night := get_tree().get_first_node_in_group("day_night") as DayNight
	if day_night:
		day_night.phase_changed.connect(_on_phase_changed)


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	if not multiplayer.is_server():
		_animate(delta, true)
		return
	_check_noon()
	var direction := Vector3.ZERO
	var speed := WANDER_SPEED
	if is_instance_valid(_leader) and _follow_left > 0.0:
		_follow_left -= delta
		var to_leader := _leader.global_position - global_position
		to_leader.y = 0.0
		if to_leader.length() > FOLLOW_DISTANCE:
			direction = to_leader.normalized()
			speed = FOLLOW_SPEED
	else:
		_leader = null
		var to_target := _target - global_position
		to_target.y = 0.0
		if to_target.length() > 0.5:
			direction = to_target.normalized()
		else:
			_wait -= delta
			if _wait <= 0.0:
				_pick_target()

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	velocity.y = -0.5 if is_on_floor() else velocity.y - _gravity * delta
	if direction != Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(4.0 * delta, 1.0))
	move_and_slide()
	_animate(delta, direction != Vector3.ZERO)


## Только на хосте: идти за Скотником
func follow(leader: Node3D, duration: float) -> void:
	_leader = leader
	_follow_left = duration


## Только на хосте. Возвращает сообщение для игрока.
func milk(player: Node3D) -> String:
	if not milk_ready:
		return "Молоко будет после рассвета"
	milk_ready = false
	var amount := PlayerClasses.milk_amount(player)
	if PlayerClasses.class_of(player) == "herder":
		player.add_xp(PlayerClasses.XP_MILK * amount)
	for i in amount:
		var bottle: Node3D = load(MILK_SCENE).instantiate()
		bottle.position = global_position + global_basis.x * 0.9 + Vector3(0.0, 0.6 + i * 0.4, 0.0)
		get_tree().current_scene.get_node("Items").add_child(bottle, true)
	return "Надоено бутылок: %d" % amount


func reset() -> void:
	transform = _start
	velocity = Vector3.ZERO
	milk_ready = true
	_leader = null
	_target = global_position


func set_enabled(value: bool) -> void:
	enabled = value
	visible = value
	collision_layer = 32 if value else 0
	if not value:
		_leader = null


## Навык скотника «Дважды в день»: в полдень молоко снова есть
func _check_noon() -> void:
	var day_night := get_tree().get_first_node_in_group("day_night") as DayNight
	if day_night == null:
		return
	var noon := DayNight.DAY_LENGTH / 2.0
	if _last_cycle < noon and day_night.cycle_time >= noon:
		for player: Player in get_tree().get_nodes_in_group("players"):
			if PlayerClasses.has(player, "herder_a2"):
				milk_ready = true
				break
	_last_cycle = day_night.cycle_time


func _on_phase_changed(is_night: bool, _day: int) -> void:
	if multiplayer.is_server() and not is_night:
		milk_ready = true


func _pick_target() -> void:
	_target = Vector3(randf_range(PASTURE_MIN.x, PASTURE_MAX.x), global_position.y, randf_range(PASTURE_MIN.y, PASTURE_MAX.y))
	_wait = randf_range(4.0, 9.0)


func _animate(delta: float, moving: bool) -> void:
	if moving:
		_anim_time += delta * 6.0
		_model.rotation.z = sin(_anim_time) * 0.04
	else:
		_model.rotation.z = 0.0
