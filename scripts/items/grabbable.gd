class_name Grabbable
extends RigidBody3D

## Крупный предмет, который тащат физически, как в R.E.P.O.: он висит перед
## игроком и подчиняется физике. Нести можно вдвоём и больше.
## Всё это считает только хост: игроки шлют ему запросы, а клиенты видят
## уже готовое положение предмета.

const PULL_STRENGTH := 12.0
const MAX_PULL_SPEED := 9.0
const HELD_ANGULAR_DAMP := 0.85
## Масса, при которой одному игроку тащить уже тяжело
const HEAVY_MASS := 40.0
## Насколько тяжёлый груз провисает ниже взгляда
const MAX_SAG := 0.8

@export var display_name := "Предмет"
## Если предмет отстал от точки удержания дальше этого, хватка срывается
@export var break_distance := 3.0

## Сколько игроков несут предмет. Синхронизируется, чтобы клиенты правильно
## замедлялись под грузом.
var holder_count := 0
## Только на хосте
var holders: Array[Node3D] = []


func _ready() -> void:
	if not multiplayer.is_server():
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true


func start_grab(holder: Node3D) -> void:
	if holder not in holders:
		holders.append(holder)
	holder_count = holders.size()
	sleeping = false


func stop_grab(holder: Node3D) -> void:
	holders.erase(holder)
	holder_count = holders.size()


## Насколько груз замедляет игрока и бросок: 1 — не мешает.
## Чем больше игроков несут, тем легче каждому.
func get_carry_factor() -> float:
	var mass_per_holder := mass / maxf(holder_count, 1)
	return clampf(1.0 - mass_per_holder / HEAVY_MASS * 0.6, 0.4, 1.0)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if holders.is_empty():
		return
	holders = holders.filter(func(h): return is_instance_valid(h) and h.is_inside_tree())
	holder_count = holders.size()
	if holders.is_empty():
		return
	var target := Vector3.ZERO
	for holder in holders:
		target += holder.get_hold_position()
	target /= holders.size()
	target.y -= (1.0 - get_carry_factor()) * MAX_SAG

	var offset := target - state.transform.origin
	if offset.length() > break_distance:
		# Менять столкновения посреди шага физики нельзя, поэтому отложенно
		for holder in holders.duplicate():
			holder.server_force_release.call_deferred()
		return
	state.linear_velocity = (offset * PULL_STRENGTH * get_carry_factor()).limit_length(MAX_PULL_SPEED)
	state.angular_velocity *= HELD_ANGULAR_DAMP
