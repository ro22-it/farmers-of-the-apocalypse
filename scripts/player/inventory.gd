class_name Inventory
extends Node

## Инвентарь игрока на 4 слота. Слот — словарь {path, name} или пустой словарь.
## Храним только путь к сцене предмета: так предмет легко пересоздать
## при выбрасывании и передать по сети.

signal changed

const SIZE := 4

var slots: Array[Dictionary] = []
var selected := 0


func _init() -> void:
	for i in SIZE:
		slots.append({})


## Кладёт предмет в текущий слот, а если он занят — в первый свободный.
## Возвращает false, если места нет.
func add(path: String, item_name: String) -> bool:
	var index := _first_free_slot()
	if index == -1:
		return false
	slots[index] = {"path": path, "name": item_name}
	selected = index
	changed.emit()
	return true


func has_free_slot() -> bool:
	return _first_free_slot() != -1


func get_selected() -> Dictionary:
	return slots[selected]


func take_selected() -> Dictionary:
	var slot := slots[selected]
	if not slot.is_empty():
		slots[selected] = {}
		changed.emit()
	return slot


func select(index: int) -> void:
	index = clampi(index, 0, SIZE - 1)
	if index == selected:
		return
	selected = index
	changed.emit()


func select_offset(offset: int) -> void:
	select(posmod(selected + offset, SIZE))


func _first_free_slot() -> int:
	if slots[selected].is_empty():
		return selected
	for i in SIZE:
		if slots[i].is_empty():
			return i
	return -1
