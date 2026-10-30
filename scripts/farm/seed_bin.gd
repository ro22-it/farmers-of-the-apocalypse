extends Interactable

## Ящик с семенами одной культуры: E — взять пакет.
## Пока бесплатно и без конца. На этапе 5 семена будут продаваться в лавке.

const SEED_BAG := "res://scenes/items/seed_bag.tscn"
const BAG_SIZE := 5

@export var crop := "carrot"


func _ready() -> void:
	var info := Crops.get_info(crop)
	$Label.text = info.get("seeds_name", "Семена")
	var material := StandardMaterial3D.new()
	material.albedo_color = info.get("color", Color.WHITE)
	$Top.material_override = material


func get_hint(_item: PickupItem) -> String:
	return "E — взять: %s" % Crops.get_info(crop).get("seeds_name", "Семена")


func interact(_player: Node3D, info: Dictionary) -> Dictionary:
	if info.get("tool", "") != "hand":
		return {}
	var state := {"crop": crop, "count": BAG_SIZE}
	return {"give": {"scene": SEED_BAG, "name": SeedBag.make_name(crop, BAG_SIZE), "state": state}}
