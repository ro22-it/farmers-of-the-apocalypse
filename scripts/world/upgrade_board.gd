extends Interactable

## Доска у дома: E — список общих улучшений фермы.


func get_hint(_item: PickupItem) -> String:
	return "E — улучшения фермы"


func interact(_player: Node3D, info: Dictionary) -> Dictionary:
	if info.get("tool", "") != "hand":
		return {}
	return {"open_upgrades": true}
