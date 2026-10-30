class_name Creature
extends CharacterBody3D

## Основа для существ из леса: здоровье, удары, испуг и ходьба с обходом препятствий.
## Решения принимает только хост. Остальным приходят положение и состояние
## через синхронизатор, а анимацию каждый играет у себя по состоянию.

enum State { APPROACH, CHEW, EAT, FLEE, SCARED }

const KNOCKBACK_SPEED := 6.0
const KNOCKBACK_TIME := 0.25
## Если почти не сдвинулся столько секунд — обходим препятствие сбоку
const STUCK_TIME := 0.4
const DETOUR_TIME := 1.2
## Отбежав от центра фермы дальше этого, существо уходит в лес насовсем
const FOREST_RADIUS := 38.0

@export var display_name := "Существо"
@export var max_hp := 3
@export var speed := 3.2
@export var flee_speed := 5.0

var state: int = State.APPROACH
var hp := 3

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## Куда убегать: место, откуда пришёл
var _home := Vector3.ZERO
var _state_time := 0.0
var _scare_from := Vector3.ZERO
var _knockback := Vector3.ZERO
var _knockback_time := 0.0
var _stuck_time := 0.0
var _detour := Vector3.ZERO
var _detour_time := 0.0
var _anim_time := 0.0


func _ready() -> void:
	add_to_group("creatures")
	hp = max_hp
	_home = global_position


## Удар игрока. Только на хосте. Возвращает true, если существо повержено.
func take_hit(amount: int, from_position: Vector3) -> bool:
	hp -= amount
	var away := global_position - from_position
	away.y = 0.0
	_knockback = away.normalized() * KNOCKBACK_SPEED
	_knockback_time = KNOCKBACK_TIME
	if hp <= 0:
		_on_died()
		queue_free()
		return true
	scare(from_position, 2.0)
	return false


## Убегать от точки столько-то секунд.
func scare(from_position: Vector3, duration: float) -> void:
	if state != State.SCARED:
		state = State.SCARED
	_scare_from = from_position
	_state_time = maxf(_state_time, duration)


## Рассвет: все уходят в лес.
func dawn() -> void:
	state = State.FLEE


## Что делать после смерти (например, выронить добычу).
func _on_died() -> void:
	pass


## Идёт к точке, обходя препятствия. Возвращает пролёт забора, если упёрся в него.
func _walk_to(target: Vector3, move_speed: float, delta: float) -> FenceSegment:
	var to_target := target - global_position
	to_target.y = 0.0
	var direction := to_target.normalized()
	if _detour_time > 0.0:
		_detour_time -= delta
		direction = (direction + _detour * 1.5).normalized()
	return _move(direction, move_speed, delta)


func _walk_away_from(point: Vector3, move_speed: float, delta: float) -> FenceSegment:
	var away := global_position - point
	away.y = 0.0
	return _walk_to(global_position + away.normalized() * 5.0, move_speed, delta)


func _stand(delta: float) -> void:
	_move(Vector3.ZERO, 0.0, delta)


func _move(direction: Vector3, move_speed: float, delta: float) -> FenceSegment:
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	if _knockback_time > 0.0:
		_knockback_time -= delta
		velocity.x += _knockback.x
		velocity.z += _knockback.z
	velocity.y = -0.5 if is_on_floor() else velocity.y - _gravity * delta
	if direction.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(10.0 * delta, 1.0))

	var before := global_position
	move_and_slide()

	var fence: FenceSegment = null
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is FenceSegment:
			fence = collider
	if move_speed > 0.0 and fence == null:
		var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
		_stuck_time = _stuck_time + delta if moved < move_speed * delta * 0.3 else 0.0
		if _stuck_time > STUCK_TIME:
			_stuck_time = 0.0
			_detour = direction.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
			_detour_time = DETOUR_TIME
	return fence


func _is_moving() -> bool:
	return state == State.APPROACH or state == State.FLEE or state == State.SCARED


func _far_from_farm() -> bool:
	return Vector2(global_position.x, global_position.z).length() > FOREST_RADIUS
