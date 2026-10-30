class_name ShopCatalog
extends RefCounted

## Товары в лавке торговца. state — запас предмета (например, семян в пакете).

const SEED_BAG := "res://scenes/items/seed_bag.tscn"

const ITEMS := [
	{"id": "seeds_carrot", "name": "Семена моркови ×5", "price": 10, "scene": SEED_BAG, "state": {"crop": "carrot", "count": 5}},
	{"id": "seeds_corn", "name": "Семена кукурузы ×5", "price": 16, "scene": SEED_BAG, "state": {"crop": "corn", "count": 5}},
	{"id": "seeds_pumpkin", "name": "Семена тыквы ×5", "price": 30, "scene": SEED_BAG, "state": {"crop": "pumpkin", "count": 5}},
	{"id": "shovel", "name": "Лопата", "price": 15, "scene": "res://scenes/items/shovel.tscn", "state": {}},
	{"id": "hammer", "name": "Молоток", "price": 15, "scene": "res://scenes/items/hammer.tscn", "state": {}},
	{"id": "watering_can", "name": "Лейка", "price": 20, "scene": "res://scenes/items/watering_can.tscn", "state": {}},
	{"id": "flashlight", "name": "Фонарь", "price": 25, "scene": "res://scenes/items/flashlight.tscn", "state": {}},
	{"id": "pitchfork", "name": "Вилы (урон 2)", "price": 30, "scene": "res://scenes/items/pitchfork.tscn", "state": {}},
]


static func find(id: String) -> Dictionary:
	for entry in ITEMS:
		if entry.id == id:
			return entry
	return {}
