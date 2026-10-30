class_name Dog
extends CharacterBody3D

## Собака: живёт у крыльца дома, а если есть Скотник — ходит за ним.
## Чует существ и лает: всем приходит, с какой стороны фермы опасность.
## Со Скотником чует вдвое дальше.

const SPEED := 6.0
const HOME := Vector3(-12.0, 0.0, -6.5)
const KEEP_DISTANCE := 2.0
const SMELL_RADIUS := 15.0
const HERDER_SMELL_RADIUS := 30.0
## Об одном и том же существе лает не чаще этого
const BARK_COOLDOWN := 15.0
const CHECK_INTERVAL := 1.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _barked := {}
var _check := 0.0
var _start: Transform3D
var _anim_time := 0.0

@onready var _model: Node3D = $Model


func _ready() -> void:
	add_to_group("animals")
	_start = transform


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	var herder := _find_herder()
	var target := HOME
	if herder:
		# Держится чуть позади и сбоку
		target = herder.global_position + herder.global_basis.z * 1.5 + herder.global_basis.x * 1.0
	var to_target := target - global_position
	to_target.y = 0.0
	var direction := to_target.normalized() if to_target.length() > KEEP_DISTANCE else Vector3.ZERO
	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED
	velocity.y = -0.5 if is_on_floor() else velocity.y - _gravity * delta
	if direction != Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(8.0 * delta, 1.0))
		_anim_time += delta * 14.0
		_model.position.y = absf(sin(_anim_time)) * 0.06
	move_and_slide()

	_check -= delta
	if _check <= 0.0:
		_check = CHECK_INTERVAL
		_sniff(HERDER_SMELL_RADIUS if herder else SMELL_RADIUS)


func reset() -> void:
	transform = _start
	velocity = Vector3.ZERO
	_barked.clear()


func _find_herder() -> Node3D:
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player.player_class == "herder" and not player.seated:
			return player
	return null


func _sniff(radius: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for creature: Creature in get_tree().get_nodes_in_group("creatures"):
		if creature.global_position.distance_to(global_position) > radius:
			continue
		var id := creature.get_instance_id()
		if _barked.has(id) and now - _barked[id] < BARK_COOLDOWN:
			continue
		_barked[id] = now
		var economy := get_tree().get_first_node_in_group("economy") as Economy
		if economy:
			economy.announce.rpc("Собака лает: %s %s!" % [creature.display_name, _side(creature.global_position)])
		return


## С какой стороны фермы точка
static func _side(point: Vector3) -> String:
	if absf(point.x) > absf(point.z):
		return "у восточного забора" if point.x > 0.0 else "у западного забора"
	return "у южного забора" if point.z > 0.0 else "у северного забора"
