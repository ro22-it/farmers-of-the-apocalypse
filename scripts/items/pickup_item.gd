class_name PickupItem
extends RigidBody3D

## Небольшой предмет: берётся в инвентарь (E) и держится в руке.
## В руке показывается отдельная копия сцены без физики и столкновений.

@export var display_name := "Предмет"
## Подсказка, когда предмет в руке
@export var use_hint := ""
## Сообщение по ЛКМ, пока у предмета нет своего действия
@export var use_message := ""
@export var hand_position := Vector3(0.35, -0.3, -0.6)
@export var hand_rotation_degrees := Vector3.ZERO


## Превращает экземпляр в модель в руке. Вызывать до добавления в дерево.
func make_held_view() -> void:
	freeze = true
	collision_layer = 0
	collision_mask = 0
	position = hand_position
	rotation_degrees = hand_rotation_degrees


func use(user: Player) -> void:
	if use_message != "":
		user.hud.show_message(use_message)


func get_use_hint() -> String:
	return use_hint
