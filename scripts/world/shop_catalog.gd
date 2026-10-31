class_name ShopCatalog
extends RefCounted

## Товары в лавке торговца. state — запас предмета (например, семян в пакете).

const SEED_BAG := "res://scenes/items/seed_bag.tscn"

const ITEMS := [
	{"id": "seeds_carrot", "name": "Семена моркови ×5", "price": 9, "scene": SEED_BAG, "state": {"crop": "carrot", "count": 5}},
	{"id": "seeds_corn", "name": "Семена кукурузы ×5", "price": 14, "scene": SEED_BAG, "state": {"crop": "corn", "count": 5}},
	{"id": "seeds_pumpkin", "name": "Семена тыквы ×5", "price": 27, "scene": SEED_BAG, "state": {"crop": "pumpkin", "count": 5}},
	{"id": "shovel", "name": "Лопата", "price": 15, "scene": "res://scenes/items/shovel.tscn", "state": {}},
	{"id": "hammer", "name": "Молоток", "price": 15, "scene": "res://scenes/items/hammer.tscn", "state": {}},
	{"id": "watering_can", "name": "Лейка", "price": 20, "scene": "res://scenes/items/watering_can.tscn", "state": {}},
	{"id": "flashlight", "name": "Фонарь", "price": 25, "scene": "res://scenes/items/flashlight.tscn", "state": {}},
	{"id": "pitchfork", "name": "Вилы (урон 2)", "price": 30, "scene": "res://scenes/items/pitchfork.tscn", "state": {}},
	{"id": "trap", "name": "Капкан", "price": 25, "scene": "res://scenes/items/trap.tscn", "state": {}},
	{"id": "slingshot", "name": "Рогатка", "price": 15, "scene": "res://scenes/items/slingshot.tscn", "state": {}},
	{"id": "shotgun", "name": "Двустволка", "price": 60, "scene": "res://scenes/items/shotgun.tscn", "state": {}},
	{"id": "rifle", "name": "Винтовка", "price": 90, "scene": "res://scenes/items/rifle.tscn", "state": {}},
	{"id": "ammo", "name": "Патроны ×15", "price": 12, "scene": "res://scenes/items/ammo_box.tscn", "state": {}},
	{"id": "energy", "name": "Энергетик (минута без усталости)", "price": 10, "scene": "res://scenes/items/energy_drink.tscn", "state": {}},
	{"id": "armor_helmet", "name": "Каска (голова, защита 20%)", "price": 45, "scene": "res://scenes/items/armor_helmet.tscn", "state": {}},
	{"id": "armor_jacket", "name": "Охотничья куртка (тело, защита 30%)", "price": 60, "scene": "res://scenes/items/armor_jacket.tscn", "state": {}},
]

## Верстак: самодельная броня из хлама
const WORKBENCH := [
	{"id": "armor_pot", "name": "Шлем из кастрюли (голова, 12%)", "price": 12, "scene": "res://scenes/items/armor_pot.tscn", "state": {}, "workbench": true},
	{"id": "armor_bucket", "name": "Нагрудник из ведра (тело, 20%)", "price": 18, "scene": "res://scenes/items/armor_bucket.tscn", "state": {}, "workbench": true},
	{"id": "armor_tires", "name": "Наколенники из покрышек (ноги, 10%)", "price": 12, "scene": "res://scenes/items/armor_tires.tscn", "state": {}, "workbench": true},
	{"id": "nailgun", "name": "Гвоздемёт (быстрый, без патронов)", "price": 35, "scene": "res://scenes/items/nailgun.tscn", "state": {}, "workbench": true},
	{"id": "corn_cannon", "name": "Кукурузная пушка (урон 3, отбрасывает)", "price": 45, "scene": "res://scenes/items/corn_cannon.tscn", "state": {}, "workbench": true},
]


static func find(id: String) -> Dictionary:
	for entry in ITEMS + WORKBENCH:
		if entry.id == id:
			return entry
	return {}
