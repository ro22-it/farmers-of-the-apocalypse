class_name Taran
extends Creature

## Таран: огромный лось из коряг. Ломает пролёт забора с одного удара,
## а заметив игрока, роет землю и бросается на него. После разбега устаёт.
## Боль не пугает его — слабость только капкан.

const RAM_INTERVAL := 1.2
const RAM_DAMAGE := 3
const SIGHT := 12.0
const WINDUP_TIME := 0.8
const CHARGE_SPEED := 9.0
const CHARGE_TIME := 1.5
const TIRED_TIME := 2.0
const HIT_DAMAGE := 30.0
const HIT_RADIUS := 1.8
## Бродит внутри фермы, пока не заметит игрока
const FARM_HALF := 20.0

var _goal := Vector3.ZERO
var _charge_dir := Vector3.FORWARD
var _hit_players: Array[Player] = []
var _fence: FenceSegment = null

@onready var _model: Node3D = $Model
@onready var _head: Node3D = $Model/Head


func _ready() -> void:
	super()
	_pick_goal()


func _physics_process(delta: float) -> void:
	_animate(delta)
	if not multiplayer.is_server():
		return
	match state:
		State.APPROACH, State.SCARED:
			_wander(delta)
		State.CHEW:
			_ram_fence(delta)
		State.WINDUP:
			_stand(delta)
			_face(_charge_dir, delta)
			_state_time -= delta
			if _state_time <= 0.0:
				state = State.CHARGE
				_state_time = CHARGE_TIME
				_hit_players.clear()
		State.CHARGE:
			_charge(delta)
		State.TIRED:
			_stand(delta)
			_state_time -= delta
			if _state_time <= 0.0:
				state = State.APPROACH
		State.TRAPPED:
			_update_trapped(delta)
		State.FLEE:
			var fence := _walk_to(_home, flee_speed, delta)
			if fence:
				fence.damage(RAM_DAMAGE)
			if _far_from_farm() or global_position.distance_to(_home) < 1.5:
				queue_free()


## Боль Тарана не пугает
func scare(_from_position: Vector3, _duration: float) -> void:
	pass


func _wander(delta: float) -> void:
	var prey := _find_player()
	if prey:
		_charge_dir = _flat(prey.global_position - global_position)
		state = State.WINDUP
		_state_time = WINDUP_TIME
		return
	var fence := _walk_to(_goal, speed, delta)
	if fence:
		_fence = fence
		state = State.CHEW
		_state_time = 0.3
	elif _flat(_goal - global_position) == Vector3.ZERO or Vector2(_goal.x - global_position.x, _goal.z - global_position.z).length() < 2.0:
		_pick_goal()


func _ram_fence(delta: float) -> void:
	_stand(delta)
	if not is_instance_valid(_fence) or _fence.is_broken():
		_fence = null
		state = State.APPROACH
		return
	_state_time -= delta
	if _state_time <= 0.0:
		_state_time = RAM_INTERVAL
		_fence.damage(RAM_DAMAGE)
		SoundBank.play_at(get_tree(), "thud", global_position)


func _charge(delta: float) -> void:
	var before := global_position
	var fence := _move(_charge_dir, CHARGE_SPEED, delta)
	if fence:
		fence.damage(RAM_DAMAGE)
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player in _hit_players or player.downed or player.seated:
			continue
		if player.global_position.distance_to(global_position) < HIT_RADIUS:
			_hit_players.append(player)
			player.take_damage(HIT_DAMAGE, global_position)
	_state_time -= delta
	# Врезался во что-то или выдохся — устаёт
	var stuck := global_position.distance_to(before) < CHARGE_SPEED * delta * 0.2
	if _state_time <= 0.0 or stuck:
		state = State.TIRED
		_state_time = TIRED_TIME


func _find_player() -> Player:
	var best: Player = null
	var best_distance := SIGHT
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player.downed or player.seated:
			continue
		var distance := player.global_position.distance_to(global_position)
		if distance < best_distance:
			best = player
			best_distance = distance
	return best


func _pick_goal() -> void:
	_goal = Vector3(randf_range(-FARM_HALF, FARM_HALF), 0.0, randf_range(-FARM_HALF, FARM_HALF))


func _face(direction: Vector3, delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(10.0 * delta, 1.0))


static func _flat(vector: Vector3) -> Vector3:
	vector.y = 0.0
	return vector.normalized()


func _animate(delta: float) -> void:
	_anim_time += delta
	match state:
		State.WINDUP:
			# Роет землю: голова вниз, качается
			_head.rotation.x = -0.5 + sin(_anim_time * 25.0) * 0.08
			_model.rotation.x = 0.0
		State.CHARGE:
			_head.rotation.x = -0.6
			_model.rotation.x = -0.12
			_model.position.y = absf(sin(_anim_time * 18.0)) * 0.12
		State.TIRED, State.TRAPPED:
			_head.rotation.x = -0.35
			_model.rotation.x = 0.0
			_model.position.y = 0.0
		_:
			_head.rotation.x = 0.0
			_model.rotation.x = 0.0
			_model.position.y = absf(sin(_anim_time * 6.0)) * 0.06 if _is_moving() else 0.0
