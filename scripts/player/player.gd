class_name Player
extends CharacterBody3D

## Игрок от первого лица: движение, взгляд, хватка крупных предметов и инвентарь.
## Ввод обрабатывает только владелец персонажа (авторитет). На этапе 2 остальные
## копии игрока будут просто повторять его состояние по сети.

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

@export var max_stamina := 100.0
@export var stamina_drain := 22.0
@export var stamina_regen := 14.0
## После полного истощения бег снова включается только с этого уровня
@export var stamina_recover_threshold := 25.0

var stamina := max_stamina
var _exhausted := false
var _crouching := false
var _height := STAND_HEIGHT
var _grabbed: Grabbable = null
var _hold_distance := 2.0
var _ignore_mouse_until := 0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var _hand: Node3D = $Head/Camera3D/Hand
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _shape: CapsuleShape3D = $CollisionShape3D.shape
@onready var _body: MeshInstance3D = $Body
@onready var inventory: Inventory = $Inventory
@onready var hud: Hud = $Hud


func _ready() -> void:
	if not is_multiplayer_authority():
		_camera.current = false
		hud.hide()
		set_process_unhandled_input(false)
		return
	# Своё тело игрок не видит, но тень от него остаётся
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_camera.current = true
	_ray.add_exception(self)
	inventory.changed.connect(_on_inventory_changed)
	_on_inventory_changed()
	_capture_mouse()


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.pressed:
			_capture_mouse()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		if Time.get_ticks_msec() < _ignore_mouse_until:
			return
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		_head.rotation.x = clampf(_head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_update_crouch(delta)
	if Input.is_action_just_pressed("jump") and is_on_floor() and not _crouching:
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := _update_stamina(delta, input_dir)
	if _grabbed:
		speed *= _grabbed.get_carry_factor()
	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	var weight := minf(accel * delta, 1.0)
	velocity.x = lerpf(velocity.x, direction.x * speed, weight)
	velocity.z = lerpf(velocity.z, direction.z * speed, weight)

	move_and_slide()
	_push_bodies(delta)
	_update_hud()


## При захвате курсор переносится в центр окна, и система присылает один большой
## рывок мыши. Игнорируем движение в первые мгновения, чтобы камера не дёргалась.
func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_ignore_mouse_until = Time.get_ticks_msec() + MOUSE_CAPTURE_GRACE_MS


## Точка, к которой тянется схваченный предмет. Её спрашивает сам предмет.
func get_hold_position() -> Vector3:
	return _camera.global_position + _look_direction() * _hold_distance


func release_grab(throw := false) -> void:
	if _grabbed == null:
		return
	var body := _grabbed
	_grabbed = null
	if not is_instance_valid(body):
		return
	remove_collision_exception_with(body)
	body.stop_grab(self)
	if throw:
		# Небольшой подъём, чтобы бросок шёл дугой, а не в землю
		var throw_dir := (_look_direction() + Vector3.UP * THROW_LIFT).normalized()
		body.linear_velocity = throw_dir * THROW_SPEED * body.get_carry_factor()


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


func _update_crouch(delta: float) -> void:
	var wants_crouch := Input.is_action_pressed("crouch")
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


## CharacterBody3D сам не толкает физические тела, поэтому толкаем вручную.
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
		body.apply_impulse(push_dir.normalized() * PUSH_FORCE * delta, collision.get_position() - body.global_position)


func _on_primary() -> void:
	var target := _get_target()
	if target is Grabbable:
		_start_grab(target)
		return
	var item := _get_held_item()
	if item:
		item.use(self)


func _start_grab(body: Grabbable) -> void:
	release_grab()
	_grabbed = body
	_hold_distance = clampf(_camera.global_position.distance_to(body.global_position), MIN_HOLD_DISTANCE, MAX_HOLD_DISTANCE)
	# Иначе можно встать на свой же груз и улететь
	add_collision_exception_with(body)
	body.start_grab(self)


func _try_pickup() -> void:
	var target := _get_target()
	if not target is PickupItem:
		return
	var item: PickupItem = target
	if not inventory.add(item.scene_file_path, item.display_name):
		hud.show_message("Инвентарь полон")
		return
	item.queue_free()


func _drop_selected() -> void:
	var slot := inventory.take_selected()
	if slot.is_empty():
		return
	var item: PickupItem = load(slot.path).instantiate()
	_items_root().add_child(item)
	# Не роняем предмет сквозь стену, если она ближе обычного
	var distance := DROP_DISTANCE
	if _ray.is_colliding():
		distance = minf(distance, _camera.global_position.distance_to(_ray.get_collision_point()) - 0.3)
	item.global_position = _camera.global_position + _look_direction() * maxf(distance, 0.1)
	item.global_rotation = Vector3(0.0, rotation.y, 0.0)
	item.linear_velocity = velocity + _look_direction() * DROP_SPEED


func _on_inventory_changed() -> void:
	for child in _hand.get_children():
		child.queue_free()
	var slot := inventory.get_selected()
	if not slot.is_empty():
		var view: PickupItem = load(slot.path).instantiate()
		view.make_held_view()
		_hand.add_child(view)
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
			hint = "E — взять: %s" % target.display_name
		else:
			var item := _get_held_item()
			if item:
				hint = item.get_use_hint()
	hud.set_hint(hint)


func _get_target() -> Object:
	_ray.force_raycast_update()
	return _ray.get_collider() if _ray.is_colliding() else null


func _get_held_item() -> PickupItem:
	for child in _hand.get_children():
		if not child.is_queued_for_deletion():
			return child as PickupItem
	return null


func _look_direction() -> Vector3:
	return -_camera.global_basis.z


## Брошенные предметы кладём в общий узел Items: на этапе 2 его будет
## синхронизировать MultiplayerSpawner.
func _items_root() -> Node:
	var scene := get_tree().current_scene
	var items := scene.get_node_or_null("Items")
	return items if items else scene
