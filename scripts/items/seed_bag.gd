class_name SeedBag
extends PickupItem

## Пакет семян одной культуры. Пустой пакет пропадает из рук.

@export var crop := "carrot"
@export var count := 5

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	super()
	_apply_look()


static func make_name(seed_crop: String, seed_count: int) -> String:
	return "%s ×%d" % [Crops.get_info(seed_crop).get("seeds_name", "Семена"), seed_count]


func get_display_name() -> String:
	return make_name(crop, count)


func get_state() -> Dictionary:
	return {"crop": crop, "count": count}


func set_state(state: Dictionary) -> void:
	crop = state.get("crop", crop)
	count = state.get("count", count)
	if is_node_ready():
		_apply_look()


func get_interaction(_user: Player, _target: Interactable) -> Dictionary:
	return {"tool": tool, "crop": crop}


func apply_result(result: Dictionary) -> bool:
	count -= result.get("consume", 0)
	return count > 0


## Цвет пакета по культуре, чтобы различать их на глаз
func _apply_look() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Crops.get_info(crop).get("color", Color.WHITE)
	_mesh.material_override = material
