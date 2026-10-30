class_name Gun
extends PickupItem

## Оружие: рогатка, двустволка, винтовка. Сколько заряжено — в запасе предмета,
## поэтому переживает инвентарь и выбрасывание. Стреляет игрок (см. Player).

@export var weapon := "shotgun"
@export var loaded := 0

@onready var muzzle: Marker3D = $Muzzle


func get_info() -> Dictionary:
	return Weapons.get_info(weapon)


func get_state() -> Dictionary:
	return {"loaded": loaded}


func set_state(state: Dictionary) -> void:
	loaded = state.get("loaded", loaded)


func get_display_name() -> String:
	var magazine: int = get_info().get("magazine", 0)
	if magazine == 0:
		return display_name
	return "%s %d/%d" % [display_name, loaded, magazine]


func get_use_hint() -> String:
	return "ЛКМ — выстрел   ПКМ — прицел   R — перезарядить" if get_info().magazine > 0 else "ЛКМ — выстрел   ПКМ — прицел"


func needs_ammo() -> bool:
	return get_info().magazine > 0
