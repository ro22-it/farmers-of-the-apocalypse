class_name PlayerClasses
extends RefCounted

## Справочник классов: внешний вид, описание, способность и все числовые бонусы.
## Пустой класс ("") — без бонусов и слабостей (используется в тестах).

const ORDER := ["farmer", "mechanic", "hunter", "herder", "herbalist"]

const DATA := {
	"farmer": {
		"name": "Фермер",
		"color": Color(0.3, 0.45, 0.7),
		"hat": "straw",
		"ability": "Подкормка",
		"cooldown": 90.0,
		"description": "+1 урожай с грядки, полив держится дольше, видит, где созрело.\nQ — Подкормка: посаженное рядом подрастает.\nСлабость: оружие бьёт слабее.",
	},
	"mechanic": {
		"name": "Механик",
		"color": Color(0.85, 0.5, 0.15),
		"hat": "hardhat",
		"ability": "Быстрый ремонт",
		"cooldown": 60.0,
		"description": "Чинит забор сразу целиком, инструменты в лавке на 25% дешевле.\nQ — Быстрый ремонт: весь забор рядом как новый.\nСлабость: бегает медленнее.",
	},
	"hunter": {
		"name": "Охотник",
		"color": Color(0.25, 0.4, 0.25),
		"hat": "cap",
		"ability": "Выследить",
		"cooldown": 45.0,
		"description": "Бьёт сильнее, видит существ сквозь туман и знает их слабости.\nQ — Выследить: существа подсвечены для всех.\nСлабость: плохо ухаживает за грядками.",
	},
	"herder": {
		"name": "Скотник",
		"color": Color(0.7, 0.25, 0.2),
		"hat": "cowboy",
		"ability": "Свист",
		"cooldown": 20.0,
		"description": "Коровы слушаются, молока вдвое больше, собака ходит рядом и чует дальше.\nQ — Свист: коровы идут за вами.\nСлабость: переживает за животных (позже).",
	},
	"herbalist": {
		"name": "Травник",
		"color": Color(0.45, 0.3, 0.6),
		"hat": "hood",
		"ability": "Дым",
		"cooldown": 40.0,
		"description": "Рядом со скупкой всё продаётся на 30% дороже.\nQ — Дым: существа рядом в ужасе убегают.\nСлабость: хрупкий, меньше выносливости.",
	},
}

## Радиусы способностей
const FEED_RADIUS := 5.0
const FEED_GROWTH := 0.15
const REPAIR_RADIUS := 8.0
const TRACK_TIME := 15.0
const WHISTLE_RADIUS := 30.0
const WHISTLE_TIME := 25.0
const SMOKE_RADIUS := 7.0
const SMOKE_SCARE_TIME := 6.0
## Травник у скупки
const HERBALIST_SALE_RADIUS := 6.0
const HERBALIST_SALE_BONUS := 1.3
## Охотник видит существ сквозь туман
const HUNTER_SIGHT := 45.0


static func get_info(id: String) -> Dictionary:
	return DATA.get(id, {})


static func display_name(id: String) -> String:
	return get_info(id).get("name", "")


static func weapon_damage(id: String, base: int) -> int:
	match id:
		"farmer":
			return maxi(base - 1, 1)
		"hunter":
			return base + 1
	return base


static func sprint_multiplier(id: String) -> float:
	return 0.85 if id == "mechanic" else 1.0


static func max_stamina(id: String) -> float:
	return 80.0 if id == "herbalist" else 100.0


## Сколько урожая добавить или убрать к обычному
static func harvest_bonus(id: String) -> int:
	match id:
		"farmer":
			return 1
		"hunter":
			return -1
	return 0


## Сколько воды получает грядка от одного полива (1 — обычный полив)
static func water_amount(id: String) -> float:
	match id:
		"farmer":
			return 1.5
		"hunter":
			return 0.5
	return 1.0


## Механику инструменты дешевле, семена — по обычной цене
static func shop_price(id: String, entry: Dictionary) -> int:
	if id == "mechanic" and not str(entry.id).begins_with("seeds"):
		return int(round(entry.price * 0.75))
	return entry.price


static func milk_amount(id: String) -> int:
	return 2 if id == "herder" else 1
