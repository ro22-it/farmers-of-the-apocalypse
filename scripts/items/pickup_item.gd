class_name PickupItem
extends RigidBody3D

## Небольшой предмет: берётся в инвентарь (E) и держится в руке.
## В руке показывается отдельная копия сцены без физики и столкновений.
## Физику предметов в мире считает хост, у клиентов они только повторяют его.

## Все сцены предметов лежат здесь. Хост принимает от клиентов только их.
const ITEMS_DIR := "res://scenes/items/"

@export var display_name := "Предмет"
## Чем предмет работает по грядкам и бочке: shovel, seeds, watering_can. Пусто — ничем.
@export var tool := ""
## Урон по существам при ударе (ЛКМ вплотную). 0 — предметом не бьют.
@export var damage := 0
## Сколько монет дают в скупке. 0 — не покупают.
@export var sell_price := 0
## Коробка патронов: при подборе уходит в запас патронов, а не в инвентарь
@export var ammo_amount := 0
## Подсказка, когда предмет в руке
@export var use_hint := ""
## Сообщение по ЛКМ, пока у предмета нет своего действия
@export var use_message := ""
@export var hand_position := Vector3(0.35, -0.3, -0.6)
@export var hand_rotation_degrees := Vector3.ZERO


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	PickupItem.keep_sane(state)


func _ready() -> void:
	if not multiplayer.is_server():
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true


## Превращает экземпляр в модель в руке. Вызывать до добавления в дерево.
func make_held_view() -> void:
	freeze = true
	collision_layer = 0
	collision_mask = 0
	position = hand_position
	rotation_degrees = hand_rotation_degrees
	# Синхронизировать модель в руке не нужно, её создаёт каждый у себя
	for part in ["MultiplayerSynchronizer", "NetSmooth"]:
		var node := get_node_or_null(part)
		if node:
			remove_child(node)
			node.free()


func use(user: Player) -> void:
	if use_message != "":
		user.hud.show_message(use_message)


func get_use_hint() -> String:
	return use_hint


func get_display_name() -> String:
	return display_name


## Запас предмета (вода в лейке, семена в пакете). Хранится в слоте инвентаря
## и переживает выбрасывание.
func get_state() -> Dictionary:
	return {}


func set_state(_state: Dictionary) -> void:
	pass


## Что отправить хосту при ЛКМ по объекту фермы. Пустой словарь — не отправлять
## (например, лейка пуста; сообщение игрок уже увидел).
func get_interaction(_user: Player, _target: Interactable) -> Dictionary:
	return {"tool": tool} if tool != "" else {}


## Применяет ответ хоста (списать заряды, наполнить).
## Возвращает false, если предмет израсходован и его надо убрать из рук.
func apply_result(_result: Dictionary) -> bool:
	return true


## Включённое состояние (например, фонарь). Его видят и другие игроки.
func is_active() -> bool:
	return false


func set_active(_value: bool) -> void:
	pass

## Страховка физики: ничего не летает быстрее этого, а выпавшее за мир возвращается
const MAX_ITEM_SPEED := 30.0
const FALL_LIMIT := -30.0
const RESCUE_POINT := Vector3(0.0, 3.0, 0.0)


static func keep_sane(state: PhysicsDirectBodyState3D) -> void:
	if state.linear_velocity.length() > MAX_ITEM_SPEED:
		state.linear_velocity = state.linear_velocity.limit_length(MAX_ITEM_SPEED)
	if state.transform.origin.y < FALL_LIMIT:
		state.transform.origin = RESCUE_POINT
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
