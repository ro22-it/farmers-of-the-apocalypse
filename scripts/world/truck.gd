class_name Truck
extends VehicleBody3D

## Старый пикап. Водитель управляет, остальные едут в кабине или кузове.
## Физику считает хост: водитель шлёт ему нажатые клавиши, а всем остальным
## положение пикапа приходит через синхронизатор. Перед машины — по +Z.

const MAX_ENGINE_FORCE := 1800.0
const MAX_BRAKE := 30.0
const MAX_STEER := 0.5
## На полной скорости руль поворачивается меньше, иначе пикап опрокидывается
const HIGH_SPEED_STEER := 0.12
const STEER_SPEED := 2.5
const MAX_SPEED := 14.0
const MAX_REVERSE_SPEED := 5.0
## Если водитель молчит дольше этого (вышел, отвалилась сеть) — пикап тормозит
const INPUT_TIMEOUT := 0.3
const SEAT_NAMES := ["за руль", "на пассажирское место", "в кузов", "в кузов"]
const DRIVER_SEAT := 0

## Кто где сидит: id игрока или 0, если место свободно
var seats: Array[int] = [0, 0, 0, 0]

var _throttle := 0.0
var _steer_input := 0.0
var _brake_input := 0.0
var _input_age := INF
var _start_transform: Transform3D

@onready var _seat_markers: Array[Marker3D] = [$Seats/Driver, $Seats/Passenger, $Seats/BedLeft, $Seats/BedRight]


func _ready() -> void:
	add_to_group("truck")
	_start_transform = global_transform
	if not multiplayer.is_server():
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_input_age += delta
	if _input_age > INPUT_TIMEOUT or seats[DRIVER_SEAT] == 0:
		_throttle = 0.0
		_steer_input = 0.0
		_brake_input = 1.0
	var speed := linear_velocity.dot(global_basis.z)
	var steer_limit := lerpf(MAX_STEER, HIGH_SPEED_STEER, clampf(absf(speed) / MAX_SPEED, 0.0, 1.0))
	steering = move_toward(steering, _steer_input * steer_limit, STEER_SPEED * delta)
	var force := _throttle * MAX_ENGINE_FORCE
	if (_throttle > 0.0 and speed > MAX_SPEED) or (_throttle < 0.0 and speed < -MAX_REVERSE_SPEED):
		force = 0.0
	engine_force = force
	brake = _brake_input * MAX_BRAKE


## Только на хосте. Ввод водителя: газ и задний ход -1..1, руль -1..1 (плюс — влево), тормоз 0..1.
func set_input(throttle: float, steer: float, brake_amount: float) -> void:
	_throttle = clampf(throttle, -1.0, 1.0)
	_steer_input = clampf(steer, -1.0, 1.0)
	_brake_input = clampf(brake_amount, 0.0, 1.0)
	_input_age = 0.0


## Только на хосте. Сажает игрока на первое свободное место (водительское — первым).
## Возвращает номер места или -1, если мест нет.
func take_seat(player_id: int) -> int:
	if player_id in seats:
		return seats.find(player_id)
	var index := seats.find(0)
	if index != -1:
		seats[index] = player_id
		# Массив меняем целиком, иначе синхронизатор не заметит изменения
		seats = seats.duplicate()
	return index


func free_seat(player_id: int) -> void:
	var index := seats.find(player_id)
	if index != -1:
		seats[index] = 0
		seats = seats.duplicate()


func get_seat_position(index: int) -> Vector3:
	return _seat_markers[index].global_position


## Куда встать, выйдя из машины: водитель и пассажир — сбоку, из кузова — сзади
func get_exit_position(index: int) -> Vector3:
	var side := global_basis.x * (1.8 if index == 0 else -1.8)
	var offset := side if index < 2 else -global_basis.z * 3.4
	return Vector3(global_position.x + offset.x, global_position.y + 0.3, global_position.z + offset.z)


func free_seats_count() -> int:
	return seats.count(0)


## Только на хосте: вернуть пикап к воротам, всех высадить
func reset() -> void:
	seats = [0, 0, 0, 0]
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = _start_transform
	set_input(0.0, 0.0, 1.0)
