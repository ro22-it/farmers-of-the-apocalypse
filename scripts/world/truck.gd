class_name Truck
extends VehicleBody3D

## Старый пикап. Водитель управляет, остальные едут в кабине или кузове.
## Физику считает хост: водитель шлёт ему нажатые клавиши, а всем остальным
## положение пикапа приходит через синхронизатор. Перед машины — по +Z.

const MAX_ENGINE_FORCE := 2600.0
const MAX_BRAKE := 30.0
const MAX_STEER := 0.65
## На полной скорости руль поворачивается меньше, иначе пикап опрокидывается
const HIGH_SPEED_STEER := 0.2
const STEER_SPEED := 3.0
const MAX_SPEED := 16.0
## Ручник: задние колёса почти теряют сцепление — пикап уходит в занос
const HANDBRAKE_BRAKE := 4.0
const REAR_GRIP := 2.5
const DRIFT_GRIP := 1.2
const GRIP_RECOVERY := 2.0
const MAX_REVERSE_SPEED := 5.0
## Если водитель молчит дольше этого (вышел, отвалилась сеть) — пикап тормозит
const INPUT_TIMEOUT := 0.3
const SEAT_NAMES := ["за руль", "на пассажирское место", "в кузов", "в кузов"]
const DRIVER_SEAT := 0
## Навыки механика-водителя и мотор (общее улучшение)
const SKILL_BOOST := 1.3
const MOTOR_BOOST := 1.4
const HEADLIGHT_RANGE := 20.0
const HEADLIGHT_HALF_ANGLE := 25.0
const RAM_SPEED := 6.0
const RAM_REACH := 2.8
## Сбить игрока: скорость, с которой он кувыркается, и урон
const RUN_OVER_SPEED := 5.0
const RUN_OVER_REACH := 2.0

## Мотор куплен (общее улучшение). Только на хосте.
var motor_upgraded := false

## Кто где сидит: id игрока или 0, если место свободно
var seats: Array[int] = [0, 0, 0, 0]

var _throttle := 0.0
var _steer_input := 0.0
var _brake_input := 0.0
var _input_age := INF
var _start_transform: Transform3D
var _driven := 0.0
var _last_position := Vector3.ZERO
## Кого и когда сбили: чтобы не бить одного игрока каждый кадр
var _run_over := {}

@onready var _seat_markers: Array[Marker3D] = [$Seats/Driver, $Seats/Passenger, $Seats/BedLeft, $Seats/BedRight]
@onready var _rear_wheels: Array[VehicleWheel3D] = [$WheelRearLeft, $WheelRearRight]

## Мотор: звучит, пока кто-то за рулём, тон растёт со скоростью
var _engine: AudioStreamPlayer3D
var _engine_last := Vector3.ZERO


func _ready() -> void:
	_attach_wheel_models()
	_engine = AudioStreamPlayer3D.new()
	_engine.stream = SoundBank.loop_stream("engine")
	_engine.unit_size = 6.0
	_engine.max_distance = 80.0
	_engine.position = Vector3(0.0, 1.0, 1.8)
	_engine.bus = &"Effects"
	add_child(_engine)
	add_to_group("truck")
	# Фары могут пугать существ (навык механика) — Грядочник проверяет эту группу
	add_to_group("scare_lights")
	_start_transform = global_transform
	if not multiplayer.is_server():
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true


func _process(delta: float) -> void:
	# Скорость считаем по перемещению — так одинаково у хоста и клиентов
	var speed := global_position.distance_to(_engine_last) / maxf(delta, 0.001)
	_engine_last = global_position
	var running := seats[DRIVER_SEAT] != 0
	if running and not _engine.playing:
		_engine.play()
	elif not running and _engine.playing:
		_engine.stop()
	_engine.pitch_scale = lerpf(_engine.pitch_scale, 0.7 + clampf(speed / MAX_SPEED, 0.0, 1.5) * 0.9, minf(5.0 * delta, 1.0))
	_engine.volume_db = -8.0


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_input_age += delta
	if _input_age > INPUT_TIMEOUT or seats[DRIVER_SEAT] == 0:
		_throttle = 0.0
		_steer_input = 0.0
		_brake_input = 1.0
	var driver := _driver()
	var boost := (SKILL_BOOST if PlayerClasses.has(driver, "mechanic_b1") else 1.0) * (MOTOR_BOOST if motor_upgraded else 1.0)
	var speed := linear_velocity.dot(global_basis.z)
	var steer_limit := lerpf(MAX_STEER, HIGH_SPEED_STEER, clampf(absf(speed) / MAX_SPEED, 0.0, 1.0))
	steering = move_toward(steering, _steer_input * steer_limit, STEER_SPEED * delta)
	var force := _throttle * MAX_ENGINE_FORCE * boost
	if (_throttle > 0.0 and speed > MAX_SPEED * boost) or (_throttle < 0.0 and speed < -MAX_REVERSE_SPEED):
		force = 0.0
	engine_force = force
	# Пробел за рулём — ручник: немного тормозит и срывает задние колёса в занос.
	# Без водителя тот же ввод держит пикап на месте полным тормозом.
	if seats[DRIVER_SEAT] == 0 or _input_age > INPUT_TIMEOUT:
		brake = MAX_BRAKE
	elif (_throttle < 0.0 and speed > 1.0) or (_throttle > 0.0 and speed < -1.0):
		# Газ против хода — это тормоз, а задний ход включится, когда пикап встанет
		engine_force = 0.0
		brake = MAX_BRAKE * 1.6 * absf(_throttle)
	else:
		brake = _brake_input * HANDBRAKE_BRAKE
	for wheel in _rear_wheels:
		var grip := DRIFT_GRIP if _brake_input > 0.5 and seats[DRIVER_SEAT] != 0 else REAR_GRIP
		wheel.wheel_friction_slip = move_toward(wheel.wheel_friction_slip, grip, GRIP_RECOVERY * delta) if grip > wheel.wheel_friction_slip else grip
	_award_driving(driver)
	if absf(speed) > RUN_OVER_SPEED:
		_run_over_players(speed)
	if PlayerClasses.has(driver, "mechanic_b3") and speed > RAM_SPEED:
		_ram(driver)


## Фары пугают существ, если за рулём механик с «Дальним светом». Только на хосте.
func scares(point: Vector3) -> bool:
	if not PlayerClasses.has(_driver(), "mechanic_b2"):
		return false
	var from := global_position + global_basis.z * 2.4 + Vector3.UP
	var to_point := point - from
	return to_point.length() <= HEADLIGHT_RANGE and global_basis.z.angle_to(to_point) <= deg_to_rad(HEADLIGHT_HALF_ANGLE)


func _driver() -> Node:
	var scene := get_tree().current_scene
	if seats[DRIVER_SEAT] == 0 or scene == null:
		return null
	return scene.get_node_or_null("Players/%d" % seats[DRIVER_SEAT])


## Механику за рулём — опыт за каждые 25 м
func _award_driving(driver: Node) -> void:
	var moved := global_position.distance_to(_last_position)
	_last_position = global_position
	if PlayerClasses.class_of(driver) != "mechanic" or moved > 5.0:
		return
	_driven += moved
	if _driven >= PlayerClasses.XP_DRIVE_METERS:
		_driven -= PlayerClasses.XP_DRIVE_METERS
		driver.add_xp(1)


## Сбил игрока — урон и кувырок
func _run_over_players(speed: float) -> void:
	var bumper := global_position + global_basis.z * signf(speed) * 2.3
	var now := Time.get_ticks_msec()
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player.seated or player.downed or now - _run_over.get(player, -10000) < 1500:
			continue
		var feet := player.global_position + Vector3.UP
		if Vector2(feet.x - bumper.x, feet.z - bumper.z).length() < RUN_OVER_REACH:
			_run_over[player] = now
			player.take_damage(8.0 + absf(speed), global_position, true)


## Таран: существа перед бампером на скорости
func _ram(driver: Node) -> void:
	var bumper := global_position + global_basis.z * 2.5
	for creature: Creature in get_tree().get_nodes_in_group("creatures"):
		if creature.global_position.distance_to(bumper) < RAM_REACH:
			creature.take_hit(10, global_position, 3.0)
			driver.add_xp(PlayerClasses.XP_KILL)


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
	motor_upgraded = false
	seats = [0, 0, 0, 0]
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = _start_transform
	set_input(0.0, 0.0, 1.0)


## Колёса модели (Kenney Car Kit) переезжают на физические колёса,
## чтобы крутиться, поворачивать и проседать вместе с подвеской
func _attach_wheel_models() -> void:
	var model: Node3D = $Model
	var pairs := {
		"wheel-front-left": $WheelFrontLeft, "wheel-front-right": $WheelFrontRight,
		"wheel-back-left": $WheelRearLeft, "wheel-back-right": $WheelRearRight,
	}
	for mesh_name: String in pairs:
		var mesh := model.find_child(mesh_name) as MeshInstance3D
		if mesh == null:
			continue
		var wheel: VehicleWheel3D = pairs[mesh_name]
		# Центр колеса в модели смещён вбок от точки привязки сетки
		var center := mesh.get_aabb().get_center()
		mesh.get_parent().remove_child(mesh)
		wheel.add_child(mesh)
		mesh.transform = Transform3D(Basis.from_scale(model.scale), -center * model.scale)
