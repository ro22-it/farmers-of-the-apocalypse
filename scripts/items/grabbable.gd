class_name Grabbable
extends RigidBody3D

## Крупный предмет, который тащат физически, как в R.E.P.O.: он висит перед
## игроком и подчиняется физике. Нести можно вдвоём и больше.
## Всё это считает только хост: игроки шлют ему запросы, а клиенты видят
## уже готовое положение предмета.

const PULL_STRENGTH := 12.0
const MAX_PULL_SPEED := 9.0
## Как быстро предмет в руках доворачивается к нужному положению
const ROTATE_STRENGTH := 8.0
const MAX_ROTATE_SPEED := 10.0
## Масса, при которой одному игроку тащить уже тяжело
const HEAVY_MASS := 40.0
## Насколько тяжёлый груз провисает ниже взгляда
const MAX_SAG := 0.8

@export var display_name := "Предмет"
## Сколько монет дают в скупке. 0 — не покупают.
@export var sell_price := 0
## Если предмет отстал от точки удержания дальше этого, хватка срывается
@export var break_distance := 3.0

## Сколько игроков несут предмет. Синхронизируется, чтобы клиенты правильно
## замедлялись под грузом.
var holder_count := 0
## Только на хосте
var holders: Array[Node3D] = []
## Только на хосте: в каком положении держать предмет (его можно вертеть)
var _target_basis := Basis()


func _ready() -> void:
	if not multiplayer.is_server():
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true


func start_grab(holder: Node3D) -> void:
	if holders.is_empty():
		_target_basis = global_basis.orthonormalized()
	if holder not in holders:
		holders.append(holder)
	holder_count = holders.size()
	sleeping = false


## Повернуть предмет в руках вокруг вертикали (колесо мыши)
func rotate_target(degrees: float) -> void:
	_target_basis = Basis(Vector3.UP, deg_to_rad(degrees)) * _target_basis


## Поставить ровно (R): сохранить только поворот вокруг вертикали.
## Так поднимают упавшее пугало.
func make_upright() -> void:
	var forward := _target_basis.z
	forward.y = 0.0
	if forward.length() < 0.1:
		forward = _target_basis.y
		forward.y = 0.0
	_target_basis = Basis.looking_at(-forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD, Vector3.UP)


func stop_grab(holder: Node3D) -> void:
	holders.erase(holder)
	holder_count = holders.size()


## Насколько груз замедляет игрока и бросок: 1 — не мешает.
## Чем больше игроков несут, тем легче каждому.
func get_carry_factor() -> float:
	var mass_per_holder := mass / maxf(holder_count, 1)
	return clampf(1.0 - mass_per_holder / HEAVY_MASS * 0.6, 0.4, 1.0)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	PickupItem.keep_sane(state)
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
	# Доворачиваем к нужному положению, а не просто гасим вращение
	var difference := _target_basis.get_rotation_quaternion() * state.transform.basis.orthonormalized().get_rotation_quaternion().inverse()
	if difference.w < 0.0:
		difference = -difference
	var angle := 2.0 * acos(clampf(difference.w, -1.0, 1.0))
	var axis := Vector3(difference.x, difference.y, difference.z)
	state.angular_velocity = Vector3.ZERO if axis.length() < 0.0001 else (axis.normalized() * angle * ROTATE_STRENGTH).limit_length(MAX_ROTATE_SPEED)
