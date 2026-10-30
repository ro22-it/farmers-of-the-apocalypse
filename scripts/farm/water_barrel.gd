extends Interactable

## Бочка с водой: ЛКМ лейкой — наполнить.


func get_hint(item: PickupItem) -> String:
	if item and item.tool == "watering_can":
		return "ЛКМ — наполнить лейку"
	return "Бочка с водой — наполнить лейку"


func interact(_player: Node3D, info: Dictionary) -> Dictionary:
	if info.get("tool", "") == "watering_can":
		return {"refill": true, "message": "Лейка наполнена"}
	return {}
