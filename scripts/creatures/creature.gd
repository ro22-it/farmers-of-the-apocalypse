class_name Creature
extends CharacterBody3D

## Основа для существ из леса: здоровье, удары, испуг и ходьба с обходом препятствий.
## Решения принимает только хост. Остальным приходят положение и состояние
## через синхронизатор, а анимацию каждый играет у себя по состоянию.

enum State { APPROACH, CHEW, EAT, FLEE, SCARED, TRAPPED, WINDUP, CHARGE, TIRED }

const KNOCKBACK_SPEED := 6.0
const KNOCKBACK_TIME := 0.25
## Если почти не сдвинулся столько секунд — обходим препятствие сбоку
const STUCK_TIME := 0.4
const DETOUR_TIME := 1.2
## Отбежав от центра фермы дальше этого, существо уходит в лес насовсем
const FOREST_RADIUS := 38.0

@export var display_name := "Существо"
## Слабость — её видит охотник в подсказке
@export var weakness := ""
## Тело, которое остаётся после победы (физический предмет)
@export_file("*.tscn") var corpse_scene := ""
@export var max_hp := 3
@export var speed := 3.2
@export var flee_speed := 5.0

var state: int = State.APPROACH
var hp := 3
## Подсвечено способностью охотника «Выследить» — видно всем. Синхронизируется.
var tracked := false

var _track_left := 0.0
var _marker: Label3D

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
	_marker = Label3D.new()
	_marker.text = "!"
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.no_depth_test = true
	_marker.fixed_size = true
	_marker.pixel_size = 0.002
	_marker.font_size = 48
	_marker.outline_size = 12
	_marker.modulate = Color(1.0, 0.3, 0.2)
	_marker.position = Vector3(0.0, 1.3, 0.0)
	add_child(_marker)


## Метка над существом: видна всем, если выслежено, а охотнику — всегда вблизи
func _process(delta: float) -> void:
	if multiplayer.is_server() and _track_left > 0.0:
		_track_left -= delta
		if _track_left <= 0.0:
			tracked = false
	var local := get_tree().get_first_node_in_group("local_player") as Player
	var hunter_sees := local != null and local.player_class == "hunter" \
			and local.global_position.distance_to(global_position) <= PlayerClasses.hunter_sight(local)
	_marker.visible = tracked or hunter_sees


## Только на хосте: подсветить для всех на время
func track(duration: float) -> void:
	tracked = true
	_track_left = duration


## Удар. Только на хосте. Возвращает true, если существо повержено.
## knockback — во сколько раз сильнее отбросить, scare_time — сколько потом бояться.
func take_hit(amount: int, from_position: Vector3, knockback := 1.0, scare_time := 2.0) -> bool:
	if is_queued_for_deletion():
		return false
	# В капкане урон двойной, и существо никуда не денется
	var trapped := state == State.TRAPPED
	if trapped:
		amount *= 2
	hp -= amount
	var away := global_position - from_position
	away.y = 0.0
	_knockback = away.normalized() * KNOCKBACK_SPEED * knockback
	_knockback_time = KNOCKBACK_TIME
	if hp <= 0:
		_on_died()
		_leave_corpse(_knockback)
		queue_free()
		return true
	if trapped:
		_knockback_time = 0.0
		return false
	scare(from_position, scare_time)
	return false


## Только на хосте: на месте победы остаётся тело — оно отлетает от удара
func _leave_corpse(push: Vector3) -> void:
	if corpse_scene == "":
		return
	var items := get_tree().current_scene.get_node_or_null("Items")
	if items == null:
		return
	var corpse: RigidBody3D = load(corpse_scene).instantiate()
	corpse.transform = global_transform
	items.add_child(corpse, true)
	corpse.linear_velocity = push * 0.8 + Vector3.UP * 4.0
	corpse.angular_velocity = Vector3(randf_range(-4.0, 4.0), randf_range(-2.0, 2.0), randf_range(-4.0, 4.0))


## Только на хосте: капкан держит существо
func trap(duration: float) -> void:
	state = State.TRAPPED
	_state_time = duration


func _update_trapped(delta: float) -> void:
	_stand(delta)
	_state_time -= delta
	if _state_time <= 0.0:
		state = _state_after_trap()


## Куда возвращаться после капкана
func _state_after_trap() -> int:
	return State.APPROACH


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
	move_speed *= _speed_factor()
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


## Замедления от навыков: «Загнать зверя» охотника и «Липкая земля» фермера
func _speed_factor() -> float:
	var factor := 1.0
	if tracked:
		for player: Player in get_tree().get_nodes_in_group("players"):
			if PlayerClasses.has(player, "hunter_b3"):
				factor *= 0.65
				break
	for plot: Plot in get_tree().get_nodes_in_group("plots"):
		if plot.sticky and Vector2(plot.global_position.x - global_position.x, plot.global_position.z - global_position.z).length() < 1.6:
			factor *= 0.6
			break
	return factor


func _is_moving() -> bool:
	return state == State.APPROACH or state == State.FLEE or state == State.SCARED


func _far_from_farm() -> bool:
	return Vector2(global_position.x, global_position.z).length() > FOREST_RADIUS
