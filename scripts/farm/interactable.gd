class_name Interactable
extends StaticBody3D

## Объект на ферме, с которым работают инструментом (ЛКМ) или рукой (E):
## участок грядки, бочка с водой, ящик семян.
## Решение принимает хост в interact(). Клиенты по синхронизированному
## состоянию только показывают подсказку.


## Подсказка у прицела. item — что в руке, может быть null.
func get_hint(_item: PickupItem) -> String:
	return ""


## Только на хосте. info: {"tool": "shovel" | "seeds" | "watering_can" | "hand", "crop": ...}
## Возвращает ответ игроку:
##   "message" — текст на экран,
##   "consume" — сколько зарядов списать с предмета в руке,
##   "refill" — наполнить предмет,
##   "give" — {scene, name, state}: выдать предмет в инвентарь.
## Пустой словарь — ничего не произошло.
func interact(_player: Node3D, _info: Dictionary) -> Dictionary:
	return {}


## Куда хост кладёт созданные предметы: их рассылает спавнер.
func _items_root() -> Node:
	var scene := get_tree().current_scene
	var items := scene.get_node_or_null("Items")
	return items if items else scene
