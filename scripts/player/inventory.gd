class_name Inventory
extends Node

## Инвентарь игрока на 5 слотов. Слот — словарь {path, name, state, count} или пустой словарь.
## Урожай и молоко складываются в стопку до MAX_STACK штук.
## state — запас предмета (вода, семена), см. PickupItem.get_state().
## Храним только путь к сцене предмета: так предмет легко пересоздать
## при выбрасывании и передать по сети.

signal changed

const SIZE := 5
const MAX_STACK := 10
const STACKABLE := [
	"res://scenes/items/carrot.tscn",
	"res://scenes/items/corn_cob.tscn",
	"res://scenes/items/milk_bottle.tscn",
	"res://scenes/items/pumpkin.tscn",
	"res://scenes/items/energy_drink.tscn",
]

const BACKPACK_SIZE := 10

var slots: Array[Dictionary] = []
## Рюкзак (окно инвентаря, I): вещи, которые не в руках
var backpack: Array[Dictionary] = []
var selected := 0


func _init() -> void:
	for i in SIZE:
		slots.append({})
	for i in BACKPACK_SIZE:
		backpack.append({})


## Пояс → рюкзак (в первое свободное место)
func to_backpack(index: int) -> bool:
	if slots[index].is_empty():
		return false
	var free := backpack.find({})
	if free == -1:
		return false
	backpack[free] = slots[index]
	slots[index] = {}
	changed.emit()
	return true


## Рюкзак → выбранный слот пояса (меняются местами)
func from_backpack(index: int) -> void:
	var item := backpack[index]
	backpack[index] = slots[selected]
	slots[selected] = item
	changed.emit()


## Кладёт предмет в текущий слот, а если он занят — в первый свободный.
## Возвращает false, если места нет.
func add(path: String, item_name: String, state := {}) -> bool:
	var stack := _stack_slot(path)
	if stack != -1:
		slots[stack].count = slots[stack].get("count", 1) + 1
		selected = stack
		changed.emit()
		return true
	var index := _first_free_slot()
	if index == -1:
		return false
	slots[index] = {"path": path, "name": item_name, "state": state, "count": 1}
	selected = index
	changed.emit()
	return true


func has_free_slot() -> bool:
	return _first_free_slot() != -1


## Влезет ли ещё один такой предмет: в свободный слот или в стопку
func can_take(path: String) -> bool:
	return has_free_slot() or _stack_slot(path) != -1


## Подпись слота: «Морковь ×3»
static func label(slot: Dictionary) -> String:
	var count: int = slot.get("count", 1)
	return slot.get("name", "—") + (" ×%d" % count if count > 1 else "")


## Взять из выбранного слота один предмет (из стопки — один, остальные остаются)
func take_one() -> Dictionary:
	var slot := slots[selected]
	if slot.get("count", 1) <= 1:
		return take_selected()
	slot.count -= 1
	changed.emit()
	var one := slot.duplicate()
	one.count = 1
	return one


## Обновляет запас и подпись предмета в выбранном слоте.
func update_selected(state: Dictionary, item_name: String) -> void:
	if slots[selected].is_empty():
		return
	slots[selected].state = state
	slots[selected].name = item_name
	changed.emit()


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


func _stack_slot(path: String) -> int:
	if not path in STACKABLE:
		return -1
	for i in SIZE:
		if slots[i].get("path", "") == path and slots[i].get("count", 1) < MAX_STACK:
			return i
	return -1


func _first_free_slot() -> int:
	if slots[selected].is_empty():
		return selected
	for i in SIZE:
		if slots[i].is_empty():
			return i
	return -1
