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
const PUSH_FORCE := 80.0
const THROW_SPEED := 10.0
const THROW_LIFT := 0.3
const MIN_HOLD_DISTANCE := 1.4
const MAX_HOLD_DISTANCE := 2.5
const DROP_DISTANCE := 0.8
const DROP_SPEED := 2.5
## Дальше этого от игрока хост не даст взять или схватить предмет
const MAX_REACH := 4.5

@export var max_stamina := 100.0
@export var stamina_drain := 22.0
@export var stamina_regen := 14.0
## После полного истощения бег снова включается только с этого уровня
@export var stamina_recover_threshold := 25.0

var player_name := ""
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

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var _hand: Node3D = $Head/Camera3D/Hand
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _shape: CapsuleShape3D = $CollisionShape3D.shape
@onready var _body: MeshInstance3D = $Body
@onready var _name_tag: Label3D = $NameTag
@onready var inventory: Inventory = $Inventory
@onready var hud: Hud = $Hud


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	_name_tag.text = player_name
	_refresh_hand()
	if not is_multiplayer_authority():
		_camera.current = false
		hud.hide()
		set_process_unhandled_input(false)
		return
	add_to_group("local_player")
	_name_tag.hide()
	# Своё тело игрок не видит, но тень от него остаётся
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_camera.current = true
	_ray.add_exception(self)
	inventory.changed.connect(_on_inventory_changed)
	_on_inventory_changed()
	capture_mouse()


func _exit_tree() -> void:
	if multiplayer.is_server():
		_server_release_grab(false)


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.pressed:
			capture_mouse()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		if Time.get_ticks_msec() < _ignore_mouse_until:
			return
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		_head.rotation.x = clampf(_head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
	elif event.is_action_pressed("primary"):
		_on_primary()
	elif event.is_action_released("primary"):
		release_grab()
	elif event.is_action_pressed("throw"):
		release_grab(true)
	elif event.is_action_pressed("pickup"):
		_try_pickup()
	elif event.is_action_pressed("drop"):
		_drop_selected()
	elif event.is_action_pressed("slot_next"):
		inventory.select_offset(1)
	elif event.is_action_pressed("slot_prev"):
		inventory.select_offset(-1)
	else:
		for i in Inventory.SIZE:
			if event.is_action_pressed("slot_%d" % (i + 1)):
				inventory.select(i)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	# Пока открыта пауза или меню, персонаж стоит
	var controls := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
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

	move_and_slide()
	_push_bodies(delta)
	_update_hud()


## При захвате курсор переносится в центр окна, и система присылает один большой
## рывок мыши. Игнорируем движение в первые мгновения, чтобы камера не дёргалась.
func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_ignore_mouse_until = Time.get_ticks_msec() + MOUSE_CAPTURE_GRACE_MS


## Точка, к которой тянется схваченный предмет. Её спрашивает сам предмет на хосте.
func get_hold_position() -> Vector3:
	return _camera.global_position + _look_direction() * _hold_distance


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
		return SPRINT_SPEED
	stamina = minf(stamina + stamina_regen * delta, max_stamina)
	if _exhausted and stamina >= stamina_recover_threshold:
		_exhausted = false
	return CROUCH_SPEED if _crouching else WALK_SPEED


func _update_crouch(delta: float, controls: bool) -> void:
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
	var target := _get_target()
	if target is Grabbable:
		_start_grab(target)
		return
	var item := _get_held_item()
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
	var target := _get_target()
	# E по объекту фермы — работа рукой: собрать урожай, взять семена
	if target is Interactable:
		_request_interact.rpc_id(1, target.get_path(), {"tool": "hand"})
		return
	if not target is PickupItem:
		return
	if not inventory.has_free_slot():
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
	_request_drop.rpc_id(1, slot.path, drop_position, rotation.y, velocity + _look_direction() * DROP_SPEED, slot.get("state", {}))


func _on_inventory_changed() -> void:
	var slot := inventory.get_selected()
	held_scene = slot.get("path", "")
	held_active = false
	hud.update_inventory(inventory)


func _update_hud() -> void:
	hud.set_stamina(stamina / max_stamina, _exhausted)
	var hint := ""
	if _grabbed:
		hint = "ПКМ — бросить"
	else:
		var target := _get_target()
		if target is Grabbable:
			hint = "ЛКМ — тащить: %s" % target.display_name
		elif target is PickupItem:
			hint = "E — взять: %s" % target.get_display_name()
		elif target is Interactable:
			hint = target.get_hint(_get_held_item())
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
	if not result.has("consume") and not result.has("refill"):
		return
	var item := _get_held_item()
	if item == null:
		return
	if item.apply_result(result):
		inventory.update_selected(item.get_state(), item.get_display_name())
	else:
		inventory.take_selected()


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
