class_name Player
extends CharacterBody3D

## Игрок от первого лица: движение, взгляд, хватка крупных предметов и инвентарь.
##
## Как это работает в сети:
## - персонаж принадлежит своему игроку (узел назван по его id). Движение и взгляд
##   считает владелец, остальным их рассылает MultiplayerSynchronizer;
## - всё, что меняет предметы (схватить, бросить, взять, выбросить, толкнуть),
##   владелец просит у хоста через RPC, а хост делает и рассылает результат.
##   Хост — тоже игрок, для него эти запросы просто выполняются у себя.

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.5
const CROUCH_SPEED := 2.2
const JUMP_VELOCITY := 4.8
const GROUND_ACCEL := 12.0
const AIR_ACCEL := 2.5
const MOUSE_SENSITIVITY := 0.0025
const MOUSE_CAPTURE_GRACE_MS := 150
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const CROUCH_LERP := 10.0
const EYE_OFFSET := 0.15
## Препятствия ниже этого игрок перешагивает сам (бортики, крыльцо, кочки)
const STEP_HEIGHT := 0.35
const PUSH_FORCE := 80.0
const THROW_SPEED := 10.0
const THROW_LIFT := 0.3
const MIN_HOLD_DISTANCE := 1.4
const MAX_HOLD_DISTANCE := 2.5
const DROP_DISTANCE := 0.8
const DROP_SPEED := 2.5
## Дальше этого от игрока хост не даст взять или схватить предмет
const MAX_REACH := 4.5
## Удар вплотную по существу
const MELEE_RANGE := 2.2
const FLASHLIGHT_SCENE := "res://scenes/items/flashlight.tscn"
## Луч фонаря: дальность и половина угла раскрытия
const FLASHLIGHT_RANGE := 14.0
const FLASHLIGHT_HALF_ANGLE := 22.0
## След способности: радиус, цвет, сколько секунд тает
const ABILITY_EFFECTS := {
	"farmer": [5.0, Color(0.4, 0.9, 0.3, 0.3), 1.0],
	"mechanic": [8.0, Color(1.0, 0.7, 0.2, 0.25), 1.0],
	"hunter": [12.0, Color(1.0, 0.3, 0.2, 0.15), 1.0],
	"herder": [6.0, Color(0.95, 0.85, 0.5, 0.2), 0.6],
	"herbalist": [7.0, Color(0.75, 0.75, 0.75, 0.55), 4.0],
}
## Здоровье: восстанавливается само, если какое-то время не получать урон
const MAX_HEALTH := 100.0
const REGEN_DELAY := 8.0
const REGEN_RATE := 3.0
const REVIVE_HEALTH := 30.0
const HERBALIST_REVIVE_HEALTH := 60.0
const HERBALIST_DAMAGE_TAKEN := 1.25
const HURT_PUSH := 7.0
const DOWNED_EYE_HEIGHT := 0.35
const BASE_FOV := 80.0
const TUMBLE_TIME := 2.0
const TUMBLE_PUSH := 1.4
const TUMBLE_LIFT := 5.0
## Камера от третьего лица в пикапе
const THIRD_PERSON_DISTANCE := 7.5
const THIRD_PERSON_HEIGHT := 3.0
const THIRD_PERSON_FOLLOW := 6.0
## Шаг поворота предмета в руках колесом
const GRAB_ROTATE_STEP := 20.0
## Удар товарища оружием — шутка: немного урона и кувырок
const PRANK_DAMAGE := 5.0
const STEP_LENGTH := 2.0
## Высота глаз сидя (в машине)
const SEATED_EYE_HEIGHT := 1.0
## Дальше этого от прилавка купить нельзя
const SHOP_REACH := 6.0

@export var max_stamina := 100.0
@export var stamina_drain := 22.0
@export var stamina_regen := 14.0
## После полного истощения бег снова включается только с этого уровня
@export var stamina_recover_threshold := 25.0

var player_name := ""
## Класс игрока (см. PlayerClasses). Задаётся при появлении у всех одинаково.
var player_class := ""
## Здоровье, «без сознания», запас патронов, опыт и навыки. Меняет только хост,
## синхронизируются для всех через ServerSync.
var health := MAX_HEALTH
var downed := false:
	set(value):
		downed = value
		if is_node_ready():
			_apply_downed()
var ammo := 0
var xp := 0:
	set(value):
		xp = value
		if is_node_ready() and is_multiplayer_authority():
			_refresh_panel()
var skills := PackedStringArray():
	set(value):
		skills = value
		if is_node_ready():
			max_stamina = PlayerClasses.max_stamina(self)
			if is_multiplayer_authority():
				_refresh_panel()
## Что игрок держит в руке (путь к сцене) и включён ли предмет.
## Синхронизируются, чтобы другие видели предмет и свет фонаря.
var held_scene := "":
	set(value):
		if value == held_scene:
			return
		held_scene = value
		if is_node_ready():
			_refresh_hand()
var held_active := false:
	set(value):
		held_active = value
		if is_node_ready():
			var item := _get_held_item()
			if item:
				item.set_active(value)
## Сидит ли в пикапе. Синхронизируется: сидящий ни с чем не сталкивается,
## иначе пикап упирался бы в собственных пассажиров.
var seated := false:
	set(value):
		seated = value
		if is_node_ready():
			_apply_seated()

## Перезарядка способности: у владельца — для подсказки, у хоста — настоящая
var _ability_ready_msec := 0
var _server_ability_ready_msec := 0

## Только на хосте: когда последний раз получал урон
var _last_hit_msec := 0
## Стрельба (у владельца): прицел, темп, перезарядка, отдача
var _aiming := false
var _next_shot_msec := 0
var _reload_done_msec := 0
var _reload_slot := -1
var _hand_kick := 0.0
var _shake := 0.0
## Только на хосте: не чаще, чем позволяет оружие
var _server_next_shot_msec := 0

## Только на хосте: инвентарь, о котором сообщил владелец (для сохранения)
var reported_inventory: Array = []

## Кувырок: физическая капсула, за которой следует персонаж (только у владельца)
var _tumble: RigidBody3D = null
var _tumble_left := 0.0

## Вид от третьего лица в пикапе — по желанию (V), основной вид из кабины
var third_person := false
## Кто тащит игрока в лес (Кукурузник). Решает хост, следует сам владелец.
var _dragged_by: Node3D = null

## Шаги: сколько осталось до следующего
var _step_left := 0.0
var _last_step_position := Vector3.ZERO

## Только для автотестов: без окна мышь не захватить, а без захвата клавиши не слушаются
var test_controls := false

var stamina := max_stamina
var _exhausted := false
var _crouching := false
var _height := STAND_HEIGHT
var _grabbed: Grabbable = null
var _hold_distance := 2.0
var _ignore_mouse_until := 0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## Только на хосте: что этот игрок сейчас держит
var _server_grabbed: Grabbable = null
## Пикап и место, где сидит владелец (только у владельца)
var _truck: Truck = null
var _seat_index := -1

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var _hand: Node3D = $Head/Camera3D/Hand
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _shape: CapsuleShape3D = $CollisionShape3D.shape
@onready var _body: MeshInstance3D = $Body
var _model: CharacterModel
@onready var _name_tag: Label3D = $NameTag
@onready var inventory: Inventory = $Inventory
@onready var hud: Hud = $Hud


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())
	# Опыт и навыки меняет хост, поэтому их синхронизатор принадлежит хосту
	$ServerSync.set_multiplayer_authority(1)


func _ready() -> void:
	add_to_group("players")
	var class_name_text := PlayerClasses.display_name(player_class)
	_name_tag.text = "%s\n%s" % [player_name, class_name_text] if class_name_text != "" else player_name
	max_stamina = PlayerClasses.max_stamina(self)
	stamina = max_stamina
	_apply_class_look()
	_refresh_hand()
	_apply_seated()
	_apply_downed()
	if not is_multiplayer_authority():
		_camera.current = false
		hud.hide()
		set_process_unhandled_input(false)
		return
	add_to_group("local_player")
	_name_tag.hide()
	# Своё тело игрок не видит, но тень от него остаётся
	_model.set_shadow_only(true)
	_camera.current = true
	_ray.add_exception(self)
	inventory.changed.connect(_on_inventory_changed)
	_on_inventory_changed()
	hud.panel_action.connect(_on_panel_action)
	# Network — автозагрузка; через дерево, чтобы скрипт собирался и в автотестах
	var network := get_node_or_null("/root/Network")
	if network and network.tutorial_enabled:
		add_child(Tutorial.new(self))
	capture_mouse()


func _exit_tree() -> void:
	if multiplayer.is_server():
		_server_release_grab(false)
		var truck := get_tree().get_first_node_in_group("truck") as Truck
		if truck:
			truck.free_seat(get_multiplayer_authority())


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.pressed:
			capture_mouse()
			get_viewport().set_input_as_handled()
		return
	# Без сознания можно только оглядываться
	if downed and not event is InputEventMouseMotion:
		return

	if event is InputEventMouseMotion:
		if Time.get_ticks_msec() < _ignore_mouse_until:
			return
		var sensitivity: float = MOUSE_SENSITIVITY * _setting("mouse_sensitivity", 1.0)
		rotate_y(-event.relative.x * sensitivity)
		_head.rotate_x(-event.relative.y * sensitivity * (-1.0 if _setting("invert_y", false) else 1.0))
		_head.rotation.x = clampf(_head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
	elif event.is_action_pressed("primary"):
		_on_primary()
	elif event.is_action_released("primary"):
		release_grab()
	elif event.is_action_pressed("throw"):
		if _grabbed:
			release_grab(true)
		elif _get_held_item() is Gun:
			_aiming = true
	elif event.is_action_released("throw"):
		_aiming = false
	elif event.is_action_pressed("reload"):
		if _grabbed:
			_request_upright.rpc_id(1)
		else:
			_try_reload()
	elif event.is_action_pressed("pickup"):
		_try_pickup()
	elif event.is_action_pressed("drop"):
		_drop_selected()
	elif event.is_action_pressed("ability"):
		_try_ability()
	elif event.is_action_pressed("skills"):
		_open_skills()
	elif event.is_action_pressed("camera_toggle") and _truck:
		third_person = not third_person
	elif event.is_action_pressed("debug_skip_phase"):
		_request_skip_phase.rpc_id(1)
	elif event.is_action_pressed("slot_next"):
		if _grabbed:
			_request_rotate_grab.rpc_id(1, -GRAB_ROTATE_STEP)
		else:
			inventory.select_offset(1)
	elif event.is_action_pressed("slot_prev"):
		if _grabbed:
			_request_rotate_grab.rpc_id(1, GRAB_ROTATE_STEP)
		else:
			inventory.select_offset(-1)
	else:
		for i in Inventory.SIZE:
			if event.is_action_pressed("slot_%d" % (i + 1)):
				inventory.select(i)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	# Пока открыта пауза или меню, персонаж стоит
	var controls := (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or test_controls) and not downed
	if _tumble:
		_update_tumble(delta)
		_update_hud()
		return
	if _truck:
		_ride(controls)
		_update_hud()
		return
	if is_instance_valid(_dragged_by):
		_follow_dragger()
		_update_hud()
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_update_crouch(delta, controls)
	if controls and Input.is_action_just_pressed("jump") and is_on_floor() and not _crouching:
		velocity.y = JUMP_VELOCITY

	var input_dir := Vector2.ZERO
	if controls:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := _update_stamina(delta, input_dir)
	if _grabbed:
		if is_instance_valid(_grabbed):
			speed *= _grabbed.get_carry_factor()
		else:
			_grabbed = null
	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	var weight := minf(accel * delta, 1.0)
	velocity.x = lerpf(velocity.x, direction.x * speed, weight)
	velocity.z = lerpf(velocity.z, direction.z * speed, weight)

	_step_up(delta)
	move_and_slide()
	_push_bodies(delta)
	_update_hud()


func _process(delta: float) -> void:
	_footsteps()
	# Здоровье восстанавливает хост
	if multiplayer.is_server() and not downed and health < MAX_HEALTH \
			and Time.get_ticks_msec() - _last_hit_msec > REGEN_DELAY * 1000.0:
		health = minf(health + REGEN_RATE * delta, MAX_HEALTH)
	if is_multiplayer_authority():
		_update_weapon_feel(delta)
		# В едущем пикапе место обновляем и при отрисовке, иначе пассажир дрожит
		if is_instance_valid(_truck):
			global_position = _truck.get_seat_position(_seat_index)
			_update_truck_camera()


## Шаги слышны всем: считаем пройденное по земле у каждой копии игрока
func _footsteps() -> void:
	var moved := Vector2(global_position.x - _last_step_position.x, global_position.z - _last_step_position.z).length()
	var climbed := absf(global_position.y - _last_step_position.y)
	_last_step_position = global_position
	if seated or downed or _tumble != null or moved > 1.0 or climbed > 0.08:
		return
	_step_left -= moved
	if _step_left <= 0.0:
		_step_left = STEP_LENGTH
		SoundBank.play_at(get_tree(), "step", global_position, -16.0 if is_multiplayer_authority() else -10.0)


## Только на хосте. Урон игроку от существ.
func take_damage(amount: float, from_position: Vector3, tumble := false) -> void:
	if downed or not multiplayer.is_server():
		return
	if player_class == "herbalist":
		amount *= HERBALIST_DAMAGE_TAKEN
	health = maxf(health - amount, 0.0)
	_last_hit_msec = Time.get_ticks_msec()
	SoundBank.everyone(get_tree(), "punch", global_position + Vector3.UP)
	var away := global_position - from_position
	away.y = 0.0
	_hurt.rpc_id(get_multiplayer_authority(), away.normalized() * HURT_PUSH, tumble)
	if health > 0.0:
		return
	downed = true
	_server_release_grab(false)
	var economy := get_tree().get_first_node_in_group("economy") as Economy
	if economy == null:
		return
	var all_down := true
	for player: Player in get_tree().get_nodes_in_group("players"):
		all_down = all_down and player.downed
	if all_down:
		economy.announce.rpc("Все без сознания!")
	else:
		economy.announce.rpc("%s без сознания! Подойдите и нажмите E" % player_name)


## Только на хосте: поднять на ноги
func revive(amount: float) -> void:
	downed = false
	health = amount
	_last_hit_msec = Time.get_ticks_msec()


## При захвате курсор переносится в центр окна, и система присылает один большой
## рывок мыши. Игнорируем движение в первые мгновения, чтобы камера не дёргалась.
func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_ignore_mouse_until = Time.get_ticks_msec() + MOUSE_CAPTURE_GRACE_MS


## Точка, к которой тянется схваченный предмет. Её спрашивает сам предмет на хосте.
func get_hold_position() -> Vector3:
	return _camera.global_position + _look_direction() * _hold_distance


## Светит ли этот игрок включённым фонарём на точку (с учётом стен).
## Вызывает хост для каждой копии игрока: взгляд и фонарь синхронизированы.
func is_shining_at(point: Vector3) -> bool:
	if not held_active or held_scene != FLASHLIGHT_SCENE:
		return false
	var origin := _camera.global_position
	var to_point := point - origin
	if to_point.length() > FLASHLIGHT_RANGE:
		return false
	if _look_direction().angle_to(to_point) > deg_to_rad(FLASHLIGHT_HALF_ANGLE):
		return false
	var query := PhysicsRayQueryParameters3D.create(origin, point, 1)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func show_message(text: String) -> void:
	hud.show_message(text)


## Смена дня и ночи (вызывает DayNight у своего игрока)
func on_phase_changed(is_night: bool, day: int) -> void:
	if is_night:
		var day_night := get_tree().get_first_node_in_group("day_night") as DayNight
		var weather := Weather.announce_text(day_night.weather) if day_night else ""
		hud.show_message("Ночь %d. %s" % [day, weather if weather != "" else "Из леса кто-то выходит…"])
	else:
		hud.show_message("Рассвет. День %d" % day)


func release_grab(throw := false) -> void:
	if _grabbed == null:
		return
	var body := _grabbed
	_grabbed = null
	if is_instance_valid(body):
		remove_collision_exception_with(body)
	_request_release.rpc_id(1, throw)


# --- Действия владельца ---

## Возвращает скорость с учётом бега и тратит или восстанавливает выносливость.
func _update_stamina(delta: float, input_dir: Vector2) -> float:
	var wants_sprint := Input.is_action_pressed("sprint") and input_dir.y < -0.1 and not _crouching
	if wants_sprint and not _exhausted:
		stamina = maxf(stamina - stamina_drain * delta, 0.0)
		if stamina == 0.0:
			_exhausted = true
		return SPRINT_SPEED * PlayerClasses.sprint_multiplier(self)
	stamina = minf(stamina + stamina_regen * delta * _vigor_multiplier(), max_stamina)
	if _exhausted and stamina >= stamina_recover_threshold:
		_exhausted = false
	return CROUCH_SPEED if _crouching else WALK_SPEED


func _update_crouch(delta: float, controls: bool) -> void:
	if downed:
		return
	var wants_crouch := controls and Input.is_action_pressed("crouch")
	# Под низким потолком встать не получится
	if not wants_crouch and _crouching and _blocked_above():
		wants_crouch = true
	_crouching = wants_crouch
	var target := CROUCH_HEIGHT if _crouching else STAND_HEIGHT
	_height = lerpf(_height, target, minf(CROUCH_LERP * delta, 1.0))
	_shape.height = _height
	_collision.position.y = _height / 2.0
	_body.scale.y = _height / STAND_HEIGHT
	_body.position.y = _height / 2.0
	_head.position.y = _height - EYE_OFFSET


## Ступенька, как в Source и Unity: если впереди низкое препятствие, пробуем
## подняться на STEP_HEIGHT, шагнуть и опуститься на его верх. Если там стена
## или не пол (слишком круто) — ничего не делаем, дальше обычный move_and_slide.
func _step_up(delta: float) -> void:
	if not is_on_floor():
		return
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.length() < 0.001:
		return
	var start := global_transform
	if not test_move(start, motion):
		return
	var up := Vector3.UP * STEP_HEIGHT
	if test_move(start, up):
		return
	var raised := start.translated(up)
	# Шагаем чуть дальше, чтобы встать на край, а не повиснуть на нём
	var step := motion.normalized() * maxf(motion.length(), 0.1)
	if test_move(raised, step):
		return
	var landing := KinematicCollision3D.new()
	if not test_move(raised.translated(step), -up, landing):
		return
	if landing.get_normal().y < cos(floor_max_angle):
		return
	var height := STEP_HEIGHT - landing.get_travel().length()
	if height <= 0.01:
		return
	global_position.y += height


func _blocked_above() -> bool:
	return test_move(global_transform, Vector3.UP * (STAND_HEIGHT - _height))


## CharacterBody3D сам не толкает физические тела, поэтому толкаем вручную —
## точнее, просим хоста: у клиентов предметы неподвижны и только повторяют хост.
func _push_bodies(delta: float) -> void:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var body := collision.get_collider() as RigidBody3D
		if body == null or body == _grabbed:
			continue
		var push_dir := -collision.get_normal()
		push_dir.y = 0.0
		if push_dir.is_zero_approx():
			continue
		var impulse := push_dir.normalized() * PUSH_FORCE * delta
		_request_push.rpc_id(1, body.get_path(), impulse, collision.get_position() - body.global_position)


func _on_primary() -> void:
	# С оружием в руке ЛКМ — всегда выстрел
	var held := _get_held_item()
	if held is Gun:
		_try_shoot(held)
		return
	var target := _get_target()
	if target is Grabbable:
		_start_grab(target)
		return
	var item := _get_held_item()
	if target is Player and item and item.damage > 0 and not target.downed:
		if _camera.global_position.distance_to(target.global_position) <= MELEE_RANGE + 0.5:
			_request_prank.rpc_id(1, target.get_path())
			_swing_effect.rpc("Sword_Slash")
		return
	if target is Creature and (item == null or item.damage == 0):
		if _camera.global_position.distance_to(target.global_position) <= MELEE_RANGE:
			_request_hit.rpc_id(1, target.get_path(), 0)
			_swing_effect.rpc("Kick_Right")
		return
	if target is Creature and item and item.damage > 0:
		if _camera.global_position.distance_to(target.global_position) <= MELEE_RANGE:
			_request_hit.rpc_id(1, target.get_path(), item.damage)
			_swing_effect.rpc("Sword_Slash")
		else:
			hud.show_message("Слишком далеко — подойдите вплотную")
		return
	if item and item.tool == "trap":
		_try_place_trap()
		return
	if target is Interactable and item:
		var info := item.get_interaction(self, target)
		if not info.is_empty():
			_request_interact.rpc_id(1, target.get_path(), info)
			return
	if item:
		item.use(self)
		held_active = item.is_active()


func _start_grab(body: Grabbable) -> void:
	release_grab()
	_grabbed = body
	_hold_distance = clampf(_camera.global_position.distance_to(body.global_position), MIN_HOLD_DISTANCE, MAX_HOLD_DISTANCE)
	# Иначе можно встать на свой же груз и улететь
	add_collision_exception_with(body)
	_request_grab.rpc_id(1, body.get_path(), _hold_distance)


func _try_pickup() -> void:
	if _truck:
		_leave_truck()
		return
	var target := _get_target()
	if target is Truck:
		_request_seat.rpc_id(1, target.get_path())
		return
	if target is Cow:
		_request_milk.rpc_id(1, target.get_path())
		return
	if target is Player and target.downed:
		_request_revive.rpc_id(1, target.get_path())
		return
	# E по объекту фермы — работа рукой: собрать урожай, взять семена
	if target is Interactable:
		_request_interact.rpc_id(1, target.get_path(), {"tool": "hand"})
		return
	if not target is PickupItem:
		return
	if target.ammo_amount == 0 and not inventory.has_free_slot():
		hud.show_message("Инвентарь полон")
		return
	_request_pickup.rpc_id(1, target.get_path())


func _drop_selected() -> void:
	var slot := inventory.take_selected()
	if slot.is_empty():
		return
	# Не роняем предмет сквозь стену, если она ближе обычного
	var distance := DROP_DISTANCE
	if _ray.is_colliding():
		distance = minf(distance, _camera.global_position.distance_to(_ray.get_collision_point()) - 0.3)
	var drop_position := _camera.global_position + _look_direction() * maxf(distance, 0.1)
	SoundBank.play_at(get_tree(), "drop", drop_position, -8.0)
	_request_drop.rpc_id(1, slot.path, drop_position, rotation.y, velocity + _look_direction() * DROP_SPEED, slot.get("state", {}))


func _on_inventory_changed() -> void:
	var slot := inventory.get_selected()
	held_scene = slot.get("path", "")
	held_active = false
	hud.update_inventory(inventory)
	# Хост сохраняет инвентарь, но знает его только со слов владельца
	_report_inventory.rpc_id(1, inventory.slots)


func _update_hud() -> void:
	hud.set_stamina(stamina / max_stamina, _exhausted)
	var day_night := get_tree().get_first_node_in_group("day_night") as DayNight
	if day_night:
		hud.set_clock(day_night.get_clock_text())
	var economy := get_tree().get_first_node_in_group("economy") as Economy
	if economy:
		hud.set_money(economy.money)
	hud.set_health(health / MAX_HEALTH, downed)
	var gun := _get_held_item() as Gun
	if gun and gun.needs_ammo():
		hud.set_ammo("%s: %d/%d   запас патронов: %d" % [gun.display_name, gun.loaded, gun.get_info().magazine, ammo])
	elif gun:
		hud.set_ammo(gun.display_name)
	else:
		hud.set_ammo("")
	var info := PlayerClasses.get_info(player_class)
	if not info.is_empty():
		var left := (_ability_ready_msec - Time.get_ticks_msec()) / 1000.0
		var text := "Q — %s: %s" % [info.ability, "готово" if left <= 0.0 else "через %d с" % ceili(left)]
		var next := PlayerClasses.next_level_xp(xp)
		text += "\nУровень %d · опыт %s" % [PlayerClasses.level_for(xp), "%d/%d" % [xp, next] if next > 0 else "максимум"]
		var points := PlayerClasses.free_points(xp, skills)
		if points > 0:
			text += "   K — навыки (+%d)" % points
		hud.set_ability(text)
	var hint := ""
	if _truck:
		hint = "W — газ   S — тормоз и назад   A/D — руль   Пробел — ручник   V — камера   E — выйти" if _seat_index == Truck.DRIVER_SEAT else "E — выйти"
	elif _grabbed:
		hint = "ПКМ — бросить   Колесо — повернуть   R — поставить ровно"
	else:
		var target := _get_target()
		if target is Grabbable:
			hint = "ЛКМ — тащить: %s" % target.display_name
		elif target is PickupItem:
			hint = "E — взять: %s" % target.get_display_name()
		elif target is Interactable:
			hint = target.get_hint(_get_held_item())
		elif target is Truck:
			var truck: Truck = target
			if truck.free_seats_count() == 0:
				hint = "Пикап: мест нет"
			else:
				hint = "E — сесть %s" % Truck.SEAT_NAMES[truck.seats.find(0)]
		elif target is Creature:
			var weapon := _get_held_item()
			if weapon and weapon.damage > 0:
				hint = "%s — ЛКМ: ударить" % target.display_name
			else:
				hint = "%s — ЛКМ: пнуть. Посветите фонарём или возьмите лопату" % target.display_name
			# Охотник знает слабости существ
			if player_class == "hunter" and target.weakness != "":
				hint += "\nСлабость: %s" % target.weakness
		elif target is Player and target.downed:
			hint = "E — поднять: %s" % target.player_name
		elif target is Cow:
			hint = "E — подоить" if target.milk_ready else "Корова: молоко будет после рассвета"
			if player_class == "herder":
				hint += "   Q — свистнуть"
		else:
			var item := _get_held_item()
			if item:
				hint = item.get_use_hint()
	hud.set_hint(hint)


# --- Запросы к хосту ---

@rpc("any_peer", "call_local", "reliable")
func _request_grab(path: NodePath, distance: float) -> void:
	if not _from_owner():
		return
	var body := get_node_or_null(path) as Grabbable
	if body == null or not _in_reach(body):
		_grab_lost.rpc_id(get_multiplayer_authority())
		return
	_server_release_grab(false)
	_hold_distance = clampf(distance, MIN_HOLD_DISTANCE, MAX_HOLD_DISTANCE)
	_server_grabbed = body
	add_collision_exception_with(body)
	body.start_grab(self)


@rpc("any_peer", "call_local", "reliable")
func _request_release(throw: bool) -> void:
	if _from_owner():
		_server_release_grab(throw)


@rpc("any_peer", "call_local", "unreliable")
func _request_push(path: NodePath, impulse: Vector3, offset: Vector3) -> void:
	if not _from_owner():
		return
	var body := get_node_or_null(path) as RigidBody3D
	if body and _in_reach(body):
		body.apply_impulse(impulse.limit_length(PUSH_FORCE / 30.0), offset)


@rpc("any_peer", "call_local", "reliable")
func _request_pickup(path: NodePath) -> void:
	if not _from_owner():
		return
	var item := get_node_or_null(path) as PickupItem
	# Двое схватили один предмет одновременно — достаётся первому
	if item == null or item.is_queued_for_deletion() or not _in_reach(item):
		return
	# Коробка патронов уходит в запас, а не в инвентарь
	if item.ammo_amount > 0:
		ammo += item.ammo_amount
		item.queue_free()
		_interact_result.rpc_id(get_multiplayer_authority(), {"message": "+%d патронов (всего %d)" % [item.ammo_amount, ammo]})
		return
	var scene := item.scene_file_path
	var item_name := item.get_display_name()
	var state := item.get_state()
	item.queue_free()
	_give_item.rpc_id(get_multiplayer_authority(), scene, item_name, state)


@rpc("any_peer", "call_local", "reliable")
func _request_drop(scene: String, drop_position: Vector3, yaw: float, drop_velocity: Vector3, state: Dictionary) -> void:
	if not _from_owner() or not scene.begins_with(PickupItem.ITEMS_DIR):
		return
	if drop_position.distance_to(global_position) > MAX_REACH:
		drop_position = _camera.global_position
	var item: PickupItem = load(scene).instantiate()
	item.position = drop_position
	item.rotation = Vector3(0.0, yaw, 0.0)
	item.set_state(state)
	_items_root().add_child(item, true)
	item.linear_velocity = drop_velocity.limit_length(THROW_SPEED)


@rpc("any_peer", "call_local", "reliable")
func _request_interact(path: NodePath, info: Dictionary) -> void:
	if not _from_owner():
		return
	var target := get_node_or_null(path) as Interactable
	if target == null or not _in_reach(target):
		return
	var result := target.interact(self, info)
	if result.is_empty():
		return
	var give: Dictionary = result.get("give", {})
	if not give.is_empty():
		_give_item.rpc_id(get_multiplayer_authority(), give.scene, give.name, give.state)
		result.erase("give")
	_interact_result.rpc_id(get_multiplayer_authority(), result)


@rpc("any_peer", "call_local", "reliable")
func _request_hit(path: NodePath, amount: int) -> void:
	if not _from_owner():
		return
	var creature := get_node_or_null(path) as Creature
	if creature == null or creature.global_position.distance_to(_camera.global_position) > MELEE_RANGE + 1.0:
		return
	# Урон считает хост по классу и навыкам
	# 0 — пинок пустой рукой: без урона, только отбросить
	var damage := 0 if amount <= 0 else PlayerClasses.weapon_damage(self, clampi(amount, 0, 3))
	if PlayerClasses.has(self, "hunter_a3") and randf() < 0.25:
		damage *= 2
	var stun := PlayerClasses.has(self, "hunter_a2")
	if player_class == "hunter":
		add_xp(PlayerClasses.XP_HIT)
	if creature.take_hit(damage, global_position, 2.0 if stun else 1.0, 5.0 if stun else 2.0):
		if player_class == "hunter":
			add_xp(PlayerClasses.XP_KILL)
		_interact_result.rpc_id(get_multiplayer_authority(), {"message": "%s повержен!" % creature.display_name})


@rpc("any_peer", "call_local", "reliable")
func _request_buy(id: String) -> void:
	if not _from_owner():
		return
	var entry := ShopCatalog.find(id)
	var counter := get_tree().get_first_node_in_group("shop_counter") as ShopCounter
	var economy := get_tree().get_first_node_in_group("economy") as Economy
	if entry.is_empty() or counter == null or economy == null:
		return
	if counter.global_position.distance_to(global_position) > SHOP_REACH:
		_interact_result.rpc_id(get_multiplayer_authority(), {"message": "Подойдите к прилавку"})
		return
	var price := PlayerClasses.shop_price(player_class, entry)
	if not economy.try_spend(price):
		_interact_result.rpc_id(get_multiplayer_authority(), {"message": "Не хватает монет: нужно %d" % price})
		return
	var item: PickupItem = load(entry.scene).instantiate()
	item.position = counter.get_spawn_position()
	item.set_state(entry.state)
	_items_root().add_child(item, true)
	economy.announce.rpc("%s купил: %s (−%d)" % [player_name, entry.name, price])
	SoundBank.everyone(get_tree(), "coins", counter.global_position + Vector3.UP)


@rpc("any_peer", "call_local", "reliable")
func _request_upgrade(id: String) -> void:
	if not _from_owner():
		return
	var upgrades := get_tree().get_first_node_in_group("farm_upgrades") as FarmUpgrades
	if upgrades == null:
		return
	var message := upgrades.buy(id)
	if message != "":
		_interact_result.rpc_id(get_multiplayer_authority(), {"message": message})
		return
	var economy := get_tree().get_first_node_in_group("economy") as Economy
	economy.announce.rpc("%s купил для фермы: %s" % [player_name, FarmUpgrades.find(id).name])


@rpc("any_peer", "call_local", "reliable")
func _request_seat(path: NodePath) -> void:
	if not _from_owner():
		return
	var truck := get_node_or_null(path) as Truck
	if truck == null or truck.global_position.distance_to(global_position) > MAX_REACH + 2.0:
		return
	var index := truck.take_seat(get_multiplayer_authority())
	if index == -1:
		_interact_result.rpc_id(get_multiplayer_authority(), {"message": "Мест нет"})
		return
	_seated.rpc_id(get_multiplayer_authority(), path, index)


@rpc("any_peer", "call_local", "reliable")
func _request_unseat() -> void:
	if not _from_owner():
		return
	var truck := get_tree().get_first_node_in_group("truck") as Truck
	if truck:
		truck.free_seat(get_multiplayer_authority())


@rpc("any_peer", "call_local", "unreliable_ordered")
func _drive(throttle: float, steer: float, brake_amount: float) -> void:
	if not _from_owner():
		return
	var truck := get_tree().get_first_node_in_group("truck") as Truck
	if truck and truck.seats[Truck.DRIVER_SEAT] == get_multiplayer_authority():
		truck.set_input(throttle, steer, brake_amount)


@rpc("any_peer", "call_local", "reliable")
func _request_revive(path: NodePath) -> void:
	if not _from_owner() or downed:
		return
	var other := get_node_or_null(path) as Player
	if other == null or not other.downed or other.global_position.distance_to(global_position) > MAX_REACH:
		return
	other.revive(HERBALIST_REVIVE_HEALTH if player_class == "herbalist" else REVIVE_HEALTH)
	var economy := get_tree().get_first_node_in_group("economy") as Economy
	if economy:
		economy.announce.rpc("%s поднял: %s" % [player_name, other.player_name])


@rpc("any_peer", "call_local", "reliable")
func _request_milk(path: NodePath) -> void:
	if not _from_owner():
		return
	var cow := get_node_or_null(path) as Cow
	if cow and _in_reach(cow):
		_interact_result.rpc_id(get_multiplayer_authority(), {"message": cow.milk(self)})


@rpc("any_peer", "call_local", "reliable")
func _request_ability() -> void:
	if not _from_owner():
		return
	var info := PlayerClasses.get_info(player_class)
	if info.is_empty() or Time.get_ticks_msec() < _server_ability_ready_msec:
		return
	var message := _perform_ability()
	var cooldown := PlayerClasses.ability_cooldown(self)
	_server_ability_ready_msec = Time.get_ticks_msec() + int(cooldown * 1000.0)
	_ability_used.rpc_id(get_multiplayer_authority(), cooldown, message)
	_ability_effect.rpc(player_class, global_position)


## Только на хосте: что делает способность класса. Возвращает сообщение игроку.
func _perform_ability() -> String:
	var count := 0
	match player_class:
		"farmer":
			for plot: Plot in get_tree().get_nodes_in_group("plots"):
				if plot.enabled and plot.state == Plot.State.PLANTED and not plot.is_ripe() and _flat_distance(plot.global_position) <= PlayerClasses.feed_radius(self):
					plot.growth = minf(plot.growth + PlayerClasses.feed_growth(self), 1.0)
					count += 1
			return "Подкормка: грядок %d" % count
		"mechanic":
			for segment: FenceSegment in get_tree().get_nodes_in_group("fence"):
				if segment.hp < segment.max_hp and _flat_distance(segment.get_center()) <= PlayerClasses.REPAIR_RADIUS:
					add_xp(PlayerClasses.XP_REPAIR_PER_HP * (segment.max_hp - segment.hp))
					segment.repair_by(self, true)
					count += 1
			return "Быстрый ремонт: пролётов %d" % count
		"hunter":
			for creature: Creature in get_tree().get_nodes_in_group("creatures"):
				creature.track(PlayerClasses.track_time(self))
				count += 1
			return "Выслежено существ: %d" % count
		"herder":
			for cow: Cow in get_tree().get_nodes_in_group("cows"):
				if cow.enabled and _flat_distance(cow.global_position) <= PlayerClasses.whistle_radius(self):
					cow.follow(self, PlayerClasses.WHISTLE_TIME)
					count += 1
			add_xp(PlayerClasses.XP_WHISTLE * count)
			return "Свист: за вами идут коровы (%d)" % count
		"herbalist":
			for creature: Creature in get_tree().get_nodes_in_group("creatures"):
				if _flat_distance(creature.global_position) <= PlayerClasses.smoke_radius(self):
					creature.scare(global_position, PlayerClasses.smoke_scare_time(self))
					count += 1
			add_xp(PlayerClasses.XP_SMOKE * count)
			# Бодрящий отвар: союзникам рядом — вся выносливость
			if PlayerClasses.has(self, "herbalist_a3"):
				for ally: Player in get_tree().get_nodes_in_group("players"):
					if _flat_distance(ally.global_position) <= PlayerClasses.smoke_radius(self):
						ally._restore_stamina.rpc_id(ally.get_multiplayer_authority())
			return "Дым: разбежалось существ %d" % count
	return ""


@rpc("any_peer", "call_local", "reliable")
func _request_rotate_grab(degrees: float) -> void:
	if _from_owner() and is_instance_valid(_server_grabbed):
		_server_grabbed.rotate_target(clampf(degrees, -45.0, 45.0))


@rpc("any_peer", "call_local", "reliable")
func _request_upright() -> void:
	if _from_owner() and is_instance_valid(_server_grabbed):
		_server_grabbed.make_upright()


@rpc("any_peer", "call_local", "reliable")
func _request_prank(path: NodePath) -> void:
	if not _from_owner() or downed:
		return
	var other := get_node_or_null(path) as Player
	if other == null or other == self or other.global_position.distance_to(global_position) > MELEE_RANGE + 1.5:
		return
	other.take_damage(PRANK_DAMAGE, global_position, true)


@rpc("any_peer", "call_local", "reliable")
func _report_inventory(slots: Array) -> void:
	if _from_owner():
		reported_inventory = slots.duplicate(true)


## Вернувшийся игрок получает свой инвентарь
@rpc("any_peer", "call_local", "reliable")
func _restore_inventory(slots: Array) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	for i in mini(slots.size(), Inventory.SIZE):
		inventory.slots[i] = slots[i]
	inventory.changed.emit()


## Только на хосте: опыт за дела своего класса
func add_xp(amount: int) -> void:
	if amount <= 0 or not multiplayer.is_server():
		return
	var old_level := PlayerClasses.level_for(xp)
	xp += amount
	var new_level := PlayerClasses.level_for(xp)
	if new_level > old_level:
		_level_up.rpc_id(get_multiplayer_authority(), new_level)


@rpc("any_peer", "call_local", "reliable")
func _request_learn(id: String) -> void:
	if not _from_owner() or not PlayerClasses.can_learn(player_class, xp, skills, id):
		return
	var learned := skills.duplicate()
	learned.append(id)
	skills = learned


## Отладка: перемотать к ближайшему закату или рассвету
@rpc("any_peer", "call_local", "reliable")
func _request_skip_phase() -> void:
	if not _from_owner():
		return
	var day_night := get_tree().get_first_node_in_group("day_night") as DayNight
	if day_night:
		day_night.skip_to_next_phase()


## Хватка сорвалась на хосте (предмет застрял или отстал) — сообщаем владельцу.
func server_force_release() -> void:
	_server_release_grab(false)
	_grab_lost.rpc_id(get_multiplayer_authority())


func _server_release_grab(throw: bool) -> void:
	var body := _server_grabbed
	_server_grabbed = null
	if not is_instance_valid(body):
		return
	remove_collision_exception_with(body)
	body.stop_grab(self)
	if throw:
		# Небольшой подъём, чтобы бросок шёл дугой, а не в землю
		var throw_dir := (_look_direction() + Vector3.UP * THROW_LIFT).normalized()
		body.linear_velocity = throw_dir * THROW_SPEED * body.get_carry_factor()


# --- Ответы хоста владельцу ---

@rpc("any_peer", "call_local", "reliable")
func _grab_lost() -> void:
	if multiplayer.get_remote_sender_id() != 1 or _grabbed == null:
		return
	if is_instance_valid(_grabbed):
		remove_collision_exception_with(_grabbed)
	_grabbed = null


@rpc("any_peer", "call_local", "reliable")
func _give_item(scene: String, item_name: String, state: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	SoundBank.play_at(get_tree(), "pickup", _camera.global_position, -8.0)
	if not inventory.add(scene, item_name, state):
		hud.show_message("Инвентарь полон")
		# Предмет не пропадает: хост кладёт его рядом
		_request_drop.rpc_id(1, scene, _camera.global_position, rotation.y, Vector3.ZERO, state)


## Ответ хоста на работу по ферме: сообщение и изменение запаса предмета в руке.
@rpc("any_peer", "call_local", "reliable")
func _interact_result(result: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	var message: String = result.get("message", "")
	if message != "":
		hud.show_message(message)
	if result.get("open_shop", false):
		hud.open_shop(ShopCatalog.ITEMS, player_class)
		return
	if result.get("open_upgrades", false):
		_open_upgrades()
		return
	if result.get("remove_held", false):
		inventory.take_selected()
		return
	if not result.has("consume") and not result.has("refill"):
		return
	var item := _get_held_item()
	if item == null:
		return
	if item.apply_result(result):
		inventory.update_selected(item.get_state(), item.get_display_name())
	else:
		inventory.take_selected()


@rpc("any_peer", "call_local", "reliable")
func _seated(path: NodePath, index: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	release_grab()
	_truck = get_node_or_null(path) as Truck
	_seat_index = index
	seated = true
	# Смотрим туда же, куда пикап (у пикапа перед — +Z, у игрока — −Z)
	rotation.y = _truck.global_rotation.y + PI
	_head.rotation.x = 0.0
	SoundBank.play_at(get_tree(), "car_door_close", global_position, -6.0)


# --- Капкан ---

const TRAP_SET_SCENE := "res://scenes/items/trap_set.tscn"


func _try_place_trap() -> void:
	_ray.force_raycast_update()
	if not _ray.is_colliding() or _ray.get_collision_normal().y < 0.7:
		hud.show_message("Наведите на землю рядом")
		return
	_request_place_trap.rpc_id(1, _ray.get_collision_point())


@rpc("any_peer", "call_local", "reliable")
func _request_place_trap(point: Vector3) -> void:
	if not _from_owner() or point.distance_to(global_position) > MAX_REACH or held_scene != "res://scenes/items/trap.tscn":
		return
	var trap: Node3D = load(TRAP_SET_SCENE).instantiate()
	trap.position = point
	_items_root().add_child(trap, true)
	_interact_result.rpc_id(get_multiplayer_authority(), {"remove_held": true, "message": "Капкан поставлен"})


# --- Стрельба ---

func _try_shoot(gun: Gun) -> void:
	var now := Time.get_ticks_msec()
	if now < _next_shot_msec or now < _reload_done_msec:
		return
	var info := gun.get_info()
	if gun.needs_ammo() and gun.loaded <= 0:
		SoundBank.play_at(get_tree(), "click", _camera.global_position, -6.0)
		hud.show_message("Пусто — R: перезарядить" if ammo > 0 else "Нет патронов — купите в лавке")
		_next_shot_msec = now + 300
		return
	if gun.needs_ammo():
		gun.loaded -= 1
		inventory.update_selected(gun.get_state(), gun.get_display_name())
	_next_shot_msec = now + int(info.cooldown * 1000.0)
	var spread := (Weapons.AIM_SPREAD if _aiming else 1.0) * PlayerClasses.spread_multiplier(self)
	_request_shoot.rpc_id(1, gun.weapon, _camera.global_position, _look_direction(), spread)
	# Отдача: ствол уводит вверх и чуть вбок, ружьё откатывается, камеру трясёт
	var recoil := deg_to_rad(info.recoil) * (0.6 if _aiming else 1.0)
	_head.rotation.x = clampf(_head.rotation.x + recoil, deg_to_rad(-89.0), deg_to_rad(89.0))
	rotate_y(randf_range(-recoil, recoil) * 0.3)
	_hand_kick = 1.0
	_shake = recoil * 3.0


func _try_reload() -> void:
	var gun := _get_held_item() as Gun
	if gun == null or not gun.needs_ammo():
		return
	var need: int = gun.get_info().magazine - gun.loaded
	var now := Time.get_ticks_msec()
	if need <= 0 or now < _reload_done_msec:
		return
	if ammo <= 0:
		hud.show_message("Нет патронов — купите в лавке")
		return
	var reload_time: float = gun.get_info().reload
	_reload_done_msec = now + int(reload_time * 1000.0)
	_reload_slot = inventory.selected
	SoundBank.play_at(get_tree(), "reload", _camera.global_position, -4.0)
	await get_tree().create_timer(reload_time).timeout
	if is_inside_tree():
		_request_ammo.rpc_id(1, need)


## Отдача, прицел и тряска — только у владельца, каждый кадр
func _update_weapon_feel(delta: float) -> void:
	var item := _get_held_item()
	var aiming := _aiming and item is Gun and not _grabbed
	_camera.fov = lerpf(_camera.fov, Weapons.AIM_FOV if aiming else _setting("fov", BASE_FOV), minf(10.0 * delta, 1.0))
	_hand_kick = move_toward(_hand_kick, 0.0, delta * 6.0)
	_shake = move_toward(_shake, 0.0, delta * 0.6)
	_camera.h_offset = randf_range(-_shake, _shake) * 0.05
	_camera.v_offset = randf_range(-_shake, _shake) * 0.05
	if item == null:
		return
	var base := item.hand_position
	if aiming:
		base = Vector3(0.0, -0.13, -0.4)
	var reloading := Time.get_ticks_msec() < _reload_done_msec
	item.position = item.position.lerp(base + Vector3(0.0, -0.1 if reloading else 0.0, _hand_kick * 0.1), minf(20.0 * delta, 1.0))
	item.rotation_degrees = item.hand_rotation_degrees + Vector3(_hand_kick * 10.0 + (-30.0 if reloading else 0.0), 0.0, 0.0)


func _muzzle_position() -> Vector3:
	var gun := _get_held_item() as Gun
	return gun.muzzle.global_position if gun else _camera.global_position


static func _spread(direction: Vector3, angle: float) -> Vector3:
	if angle <= 0.0:
		return direction
	var side := direction.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(direction).normalized()
	var radius := sqrt(randf()) * tan(angle)
	var turn := randf() * TAU
	return (direction + (side * cos(turn) + up * sin(turn)) * radius).normalized()


## Только на хосте: выстрел. Попадания считает хост, эффекты видят все.
@rpc("any_peer", "call_local", "reliable")
func _request_shoot(weapon: String, origin: Vector3, direction: Vector3, spread: float) -> void:
	if not _from_owner() or downed:
		return
	var info := Weapons.get_info(weapon)
	var now := Time.get_ticks_msec()
	if info.is_empty() or now < _server_next_shot_msec:
		return
	_server_next_shot_msec = now + int(info.cooldown * 800.0)
	if origin.distance_to(_camera.global_position) > 2.0:
		origin = _camera.global_position
	direction = direction.normalized()
	spread = clampf(spread, 0.2, 1.0)
	var space := get_world_3d().direct_space_state
	# Урон класса — только у однозарядного выстрела, иначе дробь стала бы слишком сильной
	var per_hit: int = info.damage if info.pellets > 1 else PlayerClasses.weapon_damage(self, info.damage)
	var damage_by := {}
	var hits := []
	for i in info.pellets:
		var ray := _spread(direction, deg_to_rad(info.spread) * spread)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + ray * info.range, Weapons.HIT_MASK)
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			hits.append([origin + ray * info.range, 0])
			continue
		var kind := 1
		if hit.collider is Creature:
			damage_by[hit.collider] = damage_by.get(hit.collider, 0) + per_hit
			kind = 2
		elif hit.collider is RigidBody3D:
			hit.collider.apply_impulse(ray * info.impulse, hit.position - hit.collider.global_position)
		hits.append([hit.position, kind])
	for creature: Creature in damage_by:
		if not is_instance_valid(creature):
			continue
		if player_class == "hunter":
			add_xp(PlayerClasses.XP_HIT)
		if creature.take_hit(damage_by[creature], origin, info.knockback, 3.0):
			if player_class == "hunter":
				add_xp(PlayerClasses.XP_KILL)
			_interact_result.rpc_id(get_multiplayer_authority(), {"message": "%s повержен!" % creature.display_name})
	_shot_effect.rpc(weapon, hits)


## Хост: Кукурузник схватил (path) или отпустил (пустой путь)
@rpc("any_peer", "call_local", "reliable")
func _set_dragged(path: NodePath) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_dragged_by = get_node_or_null(path) as Node3D if not path.is_empty() else null
	if _dragged_by:
		release_grab()
		hud.show_message("Вас тащат в лес! Товарищи — бейте его!")


## Вися в лапах, игрок едет за Кукурузником и может только оглядываться
func _follow_dragger() -> void:
	velocity = Vector3.ZERO
	global_position = _dragged_by.global_position + _dragged_by.global_basis.z * 0.9 + Vector3.UP * 0.3


func is_dragged() -> bool:
	return is_instance_valid(_dragged_by)


## Взмах лопатой или пинок: видят все
@rpc("any_peer", "call_local", "unreliable")
func _swing_effect(anim_name: String) -> void:
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	_model.play_action(anim_name)


@rpc("any_peer", "call_local", "reliable")
func _shot_effect(weapon: String, hits: Array) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	var info := Weapons.get_info(weapon)
	var muzzle := _muzzle_position()
	_model.play_action("Gun_Shoot")
	Effects.muzzle_flash(get_tree(), muzzle)
	SoundBank.play_at(get_tree(), info.sound, muzzle)
	for hit in hits:
		Effects.tracer(get_tree(), muzzle, hit[0], info.tracer)
		if hit[1] == 2:
			Effects.impact(get_tree(), hit[0], Color(0.75, 0.25, 0.15, 0.8))
		elif hit[1] == 1:
			Effects.impact(get_tree(), hit[0], Color(0.6, 0.55, 0.45, 0.7))


## Только на хосте: выдать патроны из запаса на перезарядку
@rpc("any_peer", "call_local", "reliable")
func _request_ammo(need: int) -> void:
	if not _from_owner():
		return
	var given := mini(clampi(need, 0, 10), ammo)
	ammo -= given
	_ammo_given.rpc_id(get_multiplayer_authority(), given)


@rpc("any_peer", "call_local", "reliable")
func _ammo_given(amount: int) -> void:
	if multiplayer.get_remote_sender_id() != 1 or _reload_slot < 0:
		return
	var slot: Dictionary = inventory.slots[_reload_slot]
	if slot.is_empty():
		return
	var state: Dictionary = slot.get("state", {}).duplicate()
	state.loaded = state.get("loaded", 0) + amount
	slot.state = state
	if _reload_slot == inventory.selected:
		var gun := _get_held_item() as Gun
		if gun:
			gun.set_state(state)
			inventory.update_selected(state, gun.get_display_name())


## Удар по владельцу: отбросить и показать красную вспышку
@rpc("any_peer", "call_local", "reliable")
func _hurt(push: Vector3, tumble: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	hud.flash_damage()
	if tumble:
		start_tumble(push * TUMBLE_PUSH + Vector3.UP * TUMBLE_LIFT)
	else:
		velocity += push + Vector3.UP * 3.0


# --- Кувырок (рэгдолл): сбили пикапом, боднул Таран, огрели лопатой ---

## Только у владельца: тело превращается в физическую капсулу, летит и кувыркается,
## а персонаж и камера следуют за ней. Остальные видят это через синхронизацию.
func start_tumble(impulse: Vector3) -> void:
	if _tumble or seated:
		return
	release_grab()
	var body := RigidBody3D.new()
	body.mass = 70.0
	body.collision_layer = 0
	body.collision_mask = 1 | 4
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = STAND_HEIGHT
	shape.shape = capsule
	body.add_child(shape)
	get_tree().current_scene.add_child(body)
	body.global_position = global_position + Vector3.UP * STAND_HEIGHT / 2.0
	body.global_rotation = Vector3(0.0, rotation.y, 0.0)
	body.linear_velocity = velocity + impulse
	body.angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-3.0, 3.0), randf_range(-6.0, 6.0))
	_tumble = body
	_tumble_left = TUMBLE_TIME
	_collision.disabled = true


func _update_tumble(delta: float) -> void:
	velocity = Vector3.ZERO
	global_position = _tumble.global_position - Vector3.UP * STAND_HEIGHT / 2.0
	_body.global_transform = _tumble.global_transform
	_tumble_left -= delta
	var settled := _tumble_left <= 0.0 and _tumble.linear_velocity.length() < 1.5
	if settled or _tumble_left < -TUMBLE_TIME:
		_end_tumble()


func _end_tumble() -> void:
	var landing := _tumble.global_position
	_tumble.queue_free()
	_tumble = null
	# Встаём точно на поверхность под местом падения
	var query := PhysicsRayQueryParameters3D.create(landing + Vector3.UP, landing + Vector3.DOWN * 4.0, 1)
	var ground := get_world_3d().direct_space_state.intersect_ray(query)
	var floor_y: float = ground.position.y if not ground.is_empty() else landing.y - 0.35
	global_position = Vector3(landing.x, floor_y + 0.02, landing.z)
	_collision.disabled = seated
	_body.rotation = Vector3.ZERO
	_body.position.y = _height / 2.0


@rpc("any_peer", "call_local", "reliable")
func _level_up(level: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	hud.show_message("Уровень %d! K — выбрать навык" % level)


@rpc("any_peer", "call_local", "reliable")
func _restore_stamina() -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	stamina = max_stamina
	_exhausted = false


@rpc("any_peer", "call_local", "reliable")
func _ability_used(cooldown: float, message: String) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_ability_ready_msec = Time.get_ticks_msec() + int(cooldown * 1000.0)
	if message != "":
		hud.show_message(message)


## Видимый всем след способности: прозрачная сфера, которая расходится и тает
@rpc("any_peer", "call_local", "reliable")
func _ability_effect(kind: String, at: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	var radius: float = ABILITY_EFFECTS.get(kind, [3.0, Color.WHITE, 1.0])[0]
	var color: Color = ABILITY_EFFECTS.get(kind, [3.0, Color.WHITE, 1.0])[1]
	var linger: float = ABILITY_EFFECTS.get(kind, [3.0, Color.WHITE, 1.0])[2]
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	var effect := MeshInstance3D.new()
	effect.mesh = sphere
	effect.material_override = material
	effect.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(effect)
	effect.global_position = at + Vector3.UP * 0.5
	effect.scale = Vector3.ONE * 0.2
	var tween := effect.create_tween()
	tween.tween_property(effect, "scale", Vector3.ONE * radius, 0.6)
	tween.tween_property(material, "albedo_color:a", 0.0, linger)
	tween.tween_callback(effect.queue_free)


# --- Класс ---

func _try_ability() -> void:
	if PlayerClasses.get_info(player_class).is_empty():
		return
	var left := (_ability_ready_msec - Time.get_ticks_msec()) / 1000.0
	if left > 0.0:
		hud.show_message("Ещё не готово: %d с" % ceili(left))
		return
	_request_ability.rpc_id(1)


## Модель персонажа по классу. Тело-капсула остаётся только у тестов без модели.
func _apply_class_look() -> void:
	_model = CharacterModel.new()
	_model.name = "Model"
	_body.add_child(_model)
	_model.position.y = -STAND_HEIGHT / 2.0
	_model.setup(player_class, self)
	_body.mesh = null


## Аура бодрости травника: рядом с ним все восстанавливаются вдвое быстрее
func _vigor_multiplier() -> float:
	for herbalist: Player in get_tree().get_nodes_in_group("players"):
		if PlayerClasses.has(herbalist, "herbalist_a2") and herbalist.global_position.distance_to(global_position) <= PlayerClasses.VIGOR_RADIUS:
			return 2.0
	return 1.0


# --- Окна: лавка, улучшения, навыки ---

## Экран итогов забега (вызывает RunDirector у всех)
func show_end_screen(title: String, subtitle: String, rows: Array) -> void:
	hud.open_panel("end", title, subtitle, rows)


func _on_panel_action(kind: String, id: String) -> void:
	match kind:
		"end":
			hud.close_panel()
			get_tree().current_scene.call("_leave")
		"shop":
			_request_buy.rpc_id(1, id)
		"upgrade":
			_request_upgrade.rpc_id(1, id)
		"skill":
			_request_learn.rpc_id(1, id)


## Перерисовать открытое окно, когда изменились навыки, опыт или улучшения
func _refresh_panel() -> void:
	match hud.panel_kind():
		"skill":
			_open_skills()
		"upgrade":
			_open_upgrades()


func _open_skills() -> void:
	var branches: Array = PlayerClasses.SKILLS.get(player_class, [])
	if branches.is_empty():
		return
	var rows := []
	for branch in branches:
		rows.append({"header": true, "text": branch.name})
		for skill in branch.skills:
			var button := "Взято"
			var disabled := true
			if not skill.id in skills:
				disabled = not PlayerClasses.can_learn(player_class, xp, skills, skill.id)
				button = "Взять" if not disabled else "Закрыто"
			rows.append({"text": "%s — %s" % [skill.name, skill.desc], "button": button, "id": skill.id, "disabled": disabled})
	var subtitle := "%s, уровень %d · свободных очков: %d" % [PlayerClasses.display_name(player_class), PlayerClasses.level_for(xp), PlayerClasses.free_points(xp, skills)]
	hud.open_panel("skill", "Навыки", subtitle, rows)


func _open_upgrades() -> void:
	var upgrades := get_tree().get_first_node_in_group("farm_upgrades") as FarmUpgrades
	if upgrades == null:
		return
	var rows := []
	for entry in FarmUpgrades.CATALOG:
		var done := upgrades.is_bought(entry.id)
		rows.append({"text": "%s — %s" % [entry.name, entry.desc], "button": "Куплено" if done else "Купить за %d" % entry.price, "id": entry.id, "disabled": done})
	hud.open_panel("upgrade", "Улучшения фермы", hud._money_line(), rows)


## Значение из автозагрузки Settings (через дерево — чтобы собиралось и в автотестах)
func _setting(key: String, fallback: Variant) -> Variant:
	var settings := get_node_or_null("/root/Settings")
	return settings.get(key) if settings else fallback


func _flat_distance(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


# --- Пикап ---

## Сидим на месте: позиция берётся у пикапа, водитель шлёт хосту клавиши.
func _ride(controls: bool) -> void:
	if not is_instance_valid(_truck):
		_truck = null
		seated = false
		return
	velocity = Vector3.ZERO
	global_position = _truck.get_seat_position(_seat_index)
	_update_truck_camera()
	if _seat_index != Truck.DRIVER_SEAT:
		return
	var throttle := 0.0
	var steer := 0.0
	var brake_amount := 0.0
	if controls:
		throttle = Input.get_axis("move_back", "move_forward")
		steer = Input.get_axis("move_right", "move_left")
		brake_amount = 1.0 if Input.is_action_pressed("jump") else 0.0
	_drive.rpc_id(1, throttle, steer, brake_amount)


## Вид от третьего лица в пикапе (V): камера сзади и сверху, плавно догоняет машину
func _update_truck_camera() -> void:
	# Сзади себя видно целиком, из кабины — только тень
	_model.set_shadow_only(not third_person)
	if not third_person:
		_camera.transform = Transform3D.IDENTITY
		return
	var focus := _truck.global_position + Vector3.UP * 1.3
	var behind := focus - _truck.global_basis.z * THIRD_PERSON_DISTANCE + Vector3.UP * THIRD_PERSON_HEIGHT
	var weight := minf(THIRD_PERSON_FOLLOW * get_physics_process_delta_time(), 1.0)
	_camera.global_position = _camera.global_position.lerp(behind, weight)
	_camera.look_at(focus, Vector3.UP)


func _leave_truck() -> void:
	SoundBank.play_at(get_tree(), "car_door_open", global_position, -6.0)
	_camera.transform = Transform3D.IDENTITY
	_model.set_shadow_only(true)
	global_position = _truck.get_exit_position(_seat_index)
	velocity = Vector3.ZERO
	_truck = null
	_seat_index = -1
	seated = false
	_request_unseat.rpc_id(1)


## Без сознания: тело лежит, глаза у земли
func _apply_downed() -> void:
	_body.rotation.x = deg_to_rad(90.0) if downed else 0.0
	if downed:
		_body.position.y = 0.35
		_head.position.y = DOWNED_EYE_HEIGHT
		if is_multiplayer_authority():
			release_grab()


## Сидя: не сталкиваемся ни с чем, глаза ниже, тело короче
func _apply_seated() -> void:
	_collision.disabled = seated
	if seated:
		# Ноги уходят под сиденье, тело не сплющиваем
		_body.scale.y = 1.0
		_body.position.y = 0.55
		_head.position.y = SEATED_EYE_HEIGHT


# --- Вспомогательное ---

func _from_owner() -> bool:
	return multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority()


func _in_reach(node: Node3D) -> bool:
	return node.global_position.distance_to(_camera.global_position) <= MAX_REACH


func _refresh_hand() -> void:
	for child in _hand.get_children():
		_hand.remove_child(child)
		child.queue_free()
	if held_scene == "" or not held_scene.begins_with(PickupItem.ITEMS_DIR):
		return
	var view: PickupItem = load(held_scene).instantiate()
	view.make_held_view()
	# Запас знает только владелец: остальным он не нужен
	if is_multiplayer_authority():
		view.set_state(inventory.get_selected().get("state", {}))
	_hand.add_child(view)
	view.set_active(held_active)


func _get_target() -> Object:
	_ray.force_raycast_update()
	return _ray.get_collider() if _ray.is_colliding() else null


func _get_held_item() -> PickupItem:
	return _hand.get_child(0) as PickupItem if _hand.get_child_count() > 0 else null


func _look_direction() -> Vector3:
	return -_camera.global_basis.z


## Брошенные предметы кладём в общий узел Items: его синхронизирует спавнер.
func _items_root() -> Node:
	var scene := get_tree().current_scene
	var items := scene.get_node_or_null("Items")
	return items if items else scene
