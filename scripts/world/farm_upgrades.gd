class_name FarmUpgrades
extends Node

## Общие улучшения фермы за деньги команды. Покупает только хост, список купленного
## синхронизируется: по нему появляются новые постройки (см. UpgradeToggle).

const CATALOG := [
	{"id": "pump", "name": "Колонка у грядок", "price": 40, "desc": "Вторая бочка с водой прямо у грядок"},
	{"id": "cow", "name": "Ещё корова", "price": 60, "desc": "Третья корова"},
	{"id": "beds", "name": "Новые грядки", "price": 80, "desc": "Две грядки, +6 участков"},
	{"id": "tower", "name": "Сторожевая вышка", "price": 120, "desc": "Вышка с фонарём: ночью Грядочник боится подходить"},
	{"id": "lamps", "name": "Фонари у грядок", "price": 70, "desc": "Шесть фонарей среди грядок: ночью светло работать, Грядочники к ним не подходят"},
	{"id": "worker", "name": "Работник", "price": 140, "desc": "Нанятый работник ходит по грядкам и поливает всё посаженное"},
	{"id": "searchlights", "name": "Прожекторы", "price": 160, "desc": "Четыре прожектора по углам забора: ночью Грядочники и Рой обходят их стороной"},
	{"id": "motor", "name": "Мотор для пикапа", "price": 120, "desc": "Пикап быстрее и тянет сильнее"},
	{"id": "stone", "name": "Каменный забор", "price": 150, "desc": "Прочность пролётов 6 вместо 3"},
]

var bought := PackedStringArray():
	set(value):
		bought = value
		if is_node_ready():
			_apply()


func _ready() -> void:
	add_to_group("farm_upgrades")
	_apply.call_deferred()


static func find(id: String) -> Dictionary:
	for entry in CATALOG:
		if entry.id == id:
			return entry
	return {}


func is_bought(id: String) -> bool:
	return id in bought


func reset() -> void:
	bought = PackedStringArray()


## Только на хосте. Возвращает сообщение для покупателя.
func buy(id: String) -> String:
	var entry := find(id)
	if entry.is_empty():
		return ""
	if is_bought(id):
		return "Уже куплено"
	var economy := get_tree().get_first_node_in_group("economy") as Economy
	if economy == null or not economy.try_spend(entry.price):
		return "Не хватает монет: нужно %d" % entry.price
	var list := bought.duplicate()
	list.append(id)
	bought = list
	# Улучшения, которые меняют уже существующее, применяет хост один раз
	match id:
		"stone":
			for segment: FenceSegment in get_tree().get_nodes_in_group("fence"):
				segment.make_stone()
		"motor":
			var truck := get_tree().get_first_node_in_group("truck") as Truck
			if truck:
				truck.motor_upgraded = true
	return ""


## Показать или спрятать купленные части фермы — у всех одинаково
func _apply() -> void:
	for toggle: UpgradeToggle in get_tree().get_nodes_in_group("upgrade_toggles"):
		toggle.set_active(toggle.upgrade_id in bought)
	get_tree().call_group("local_player", "_refresh_panel")
