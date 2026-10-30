class_name ShopCounter
extends Interactable

## Прилавок лавки: E открывает список товаров. Купленное появляется на прилавке.

@onready var _spawn_point: Marker3D = $SpawnPoint


func _ready() -> void:
	add_to_group("shop_counter")


func get_hint(_item: PickupItem) -> String:
	return "E — открыть лавку"


func interact(_player: Node3D, info: Dictionary) -> Dictionary:
	if info.get("tool", "") != "hand":
		return {}
	return {"open_shop": true}


## Куда положить покупку. Немного разбрасываем, чтобы вещи не появлялись друг в друге.
func get_spawn_position() -> Vector3:
	return _spawn_point.global_position + Vector3(randf_range(-1.2, 1.2), 0.0, randf_range(-0.1, 0.1))
