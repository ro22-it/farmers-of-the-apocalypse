class_name Workbench
extends Interactable

## Верстак у сарая: из хлама собирается самодельная броня — дешевле, чем в лавке,
## но слабее и быстрее ломается. Механику всё вдвое дешевле. Готовое ложится на верстак.

@onready var _spawn_point: Marker3D = $SpawnPoint


func _ready() -> void:
	add_to_group("workbench")


func get_hint(_item: PickupItem) -> String:
	return "E — верстак: собрать броню из хлама"


func interact(_player: Node3D, info: Dictionary) -> Dictionary:
	if info.get("tool", "") != "hand":
		return {}
	return {"open_workbench": true}


func get_spawn_position() -> Vector3:
	return _spawn_point.global_position + Vector3(randf_range(-0.5, 0.5), 0.0, 0.0)
