class_name Crops
extends RefCounted

## Справочник культур. Время роста — в секундах реального времени,
## пока нет смены дня и ночи (этап 4). Для сравнения: день длится 8 минут.

const DATA := {
	"carrot": {
		"name": "Морковь",
		"seeds_name": "Семена моркови",
		"grow_time": 120.0,
		"produce": "res://scenes/items/carrot.tscn",
		"amount": 2,
		"color": Color(0.95, 0.5, 0.15),
	},
	"corn": {
		"name": "Кукуруза",
		"seeds_name": "Семена кукурузы",
		"grow_time": 240.0,
		"produce": "res://scenes/items/corn_cob.tscn",
		"amount": 2,
		"color": Color(0.95, 0.82, 0.3),
	},
	"pumpkin": {
		"name": "Тыква",
		"seeds_name": "Семена тыквы",
		"grow_time": 360.0,
		"produce": "res://scenes/items/pumpkin.tscn",
		"amount": 1,
		"color": Color(0.93, 0.5, 0.12),
	},
}


static func get_info(crop: String) -> Dictionary:
	return DATA.get(crop, {})
