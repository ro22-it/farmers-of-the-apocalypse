class_name FenceSegment
extends Interactable

## Пролёт забора между двумя столбами (3 м). Существа его грызут,
## игроки чинят молотком. Прочность меняет только хост.
## Сломанный пролёт остаётся видимым для прицела (чтобы его можно было починить),
## но через него проходят все.

const MAX_HP := 3
const SOLID_LAYER := 1
## Слой «объект для прицела» — по нему никто не сталкивается
const INTERACT_LAYER := 8

var hp := MAX_HP:
	set(value):
		hp = value
		if is_node_ready():
			_update_look()

@onready var _rail_top: Node3D = $RailTop
@onready var _rail_bottom: Node3D = $RailBottom


func _ready() -> void:
	add_to_group("fence")
	_update_look()


func is_broken() -> bool:
	return hp <= 0


func damage(amount: int) -> void:
	hp = maxi(hp - amount, 0)


func reset() -> void:
	hp = MAX_HP


func get_hint(item: PickupItem) -> String:
	var has_hammer := item != null and item.tool == "hammer"
	if hp >= MAX_HP:
		return "Забор цел"
	var state := "сломан" if is_broken() else "повреждён (%d/%d)" % [hp, MAX_HP]
	return "Забор %s — %s" % [state, "ЛКМ: починить" if has_hammer else "нужен молоток"]


func interact(_player: Node3D, info: Dictionary) -> Dictionary:
	if info.get("tool", "") != "hammer":
		return {}
	if hp >= MAX_HP:
		return {"message": "Забор цел"}
	hp = MAX_HP
	return {"message": "Забор починен"}


func _update_look() -> void:
	_rail_top.visible = hp >= 2
	# Повреждённая верхняя жердь перекошена
	_rail_top.rotation.z = 0.0 if hp >= MAX_HP else deg_to_rad(8.0)
	_rail_bottom.visible = hp >= 1
	collision_layer = INTERACT_LAYER if is_broken() else SOLID_LAYER
