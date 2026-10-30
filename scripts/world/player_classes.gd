class_name PlayerClasses
extends RefCounted

## Справочник классов: внешний вид, описание, способность, навыки, уровни
## и все числовые бонусы. Функции бонусов принимают игрока (или null) и учитывают
## и класс, и взятые навыки. Пустой класс ("") — без бонусов и слабостей.

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

## Дерево навыков: две ветки по три навыка, внутри ветки — строго по порядку
const SKILLS := {
	"farmer": [
		{"name": "Урожайность", "skills": [
			{"id": "farmer_a1", "name": "Щедрые грядки", "desc": "Ещё +1 урожай с грядки"},
			{"id": "farmer_a2", "name": "Заботливый полив", "desc": "Политое вами растёт на 25% быстрее"},
			{"id": "farmer_a3", "name": "Мощная подкормка", "desc": "Подкормка +30% и в 8 м"},
		]},
		{"name": "Боевые растения", "skills": [
			{"id": "farmer_b1", "name": "Колючие грядки", "desc": "Грядочник ест посаженное вами вдвое дольше"},
			{"id": "farmer_b2", "name": "Кусачие грядки", "desc": "Ваши грядки кусают того, кто их ест"},
			{"id": "farmer_b3", "name": "Липкая земля", "desc": "У ваших грядок существа вязнут: −40% скорости"},
		]},
	],
	"mechanic": [
		{"name": "Инженер", "skills": [
			{"id": "mechanic_a1", "name": "Расторопность", "desc": "Быстрый ремонт перезаряжается вдвое быстрее"},
			{"id": "mechanic_a2", "name": "Двойные жерди", "desc": "Починенный вами пролёт прочнее на 2"},
			{"id": "mechanic_a3", "name": "Сигнализация", "desc": "Все узнают, где сломан забор"},
		]},
		{"name": "Водитель", "skills": [
			{"id": "mechanic_b1", "name": "Газ в пол", "desc": "Пикап под вами быстрее на 30%"},
			{"id": "mechanic_b2", "name": "Дальний свет", "desc": "Фары пикапа пугают Грядочников"},
			{"id": "mechanic_b3", "name": "Таран", "desc": "Пикап на скорости сбивает существ"},
		]},
	],
	"hunter": [
		{"name": "Стрелок", "skills": [
			{"id": "hunter_a1", "name": "Твёрдая рука", "desc": "Ещё +1 урон"},
			{"id": "hunter_a2", "name": "Оглушение", "desc": "Удар отбрасывает вдвое дальше и пугает надолго"},
			{"id": "hunter_a3", "name": "Точный удар", "desc": "25% шанс двойного урона"},
		]},
		{"name": "Следопыт", "skills": [
			{"id": "hunter_b1", "name": "Зоркий глаз", "desc": "Видит существ на 75 м"},
			{"id": "hunter_b2", "name": "Долгий след", "desc": "«Выследить» длится 30 с и перезаряжается за 25 с"},
			{"id": "hunter_b3", "name": "Загнать зверя", "desc": "Выслеженные существа медленнее на 35%"},
		]},
	],
	"herder": [
		{"name": "Хозяйство", "skills": [
			{"id": "herder_a1", "name": "Ласковые руки", "desc": "Ещё +1 бутылка молока"},
			{"id": "herder_a2", "name": "Дважды в день", "desc": "Коровы доятся и в полдень"},
			{"id": "herder_a3", "name": "Звонкий свист", "desc": "Свист каждые 8 с и вдвое дальше"},
		]},
		{"name": "Собаковод", "skills": [
			{"id": "herder_b1", "name": "Нюх", "desc": "Собака чует существ на 45 м"},
			{"id": "herder_b2", "name": "Сторож", "desc": "Собака гонит и кусает существ"},
			{"id": "herder_b3", "name": "Злая собака", "desc": "Собака кусает вдвое больнее"},
		]},
	],
	"herbalist": [
		{"name": "Лекарь", "skills": [
			{"id": "herbalist_a1", "name": "Закалка", "desc": "Выносливость 100"},
			{"id": "herbalist_a2", "name": "Аура бодрости", "desc": "Все рядом восстанавливают выносливость вдвое быстрее"},
			{"id": "herbalist_a3", "name": "Бодрящий отвар", "desc": "Дым возвращает союзникам всю выносливость"},
		]},
		{"name": "Алхимик", "skills": [
			{"id": "herbalist_b1", "name": "Густой дым", "desc": "Дым в 10 м и пугает на 10 с"},
			{"id": "herbalist_b2", "name": "Быстрые травы", "desc": "Дым каждые 20 с"},
			{"id": "herbalist_b3", "name": "Торговка", "desc": "У скупки +60% вместо +30%"},
		]},
	],
}

## Сколько всего опыта нужно для уровней 2, 3, 4, 5, 6
const LEVEL_XP := [40, 100, 180, 280, 400]
const MAX_LEVEL := 6

## Опыт за дела своего класса
const XP_PLANT := 3
const XP_HARVEST := 10
const XP_REPAIR_PER_HP := 4
const XP_DRIVE_METERS := 25.0
const XP_HIT := 4
const XP_KILL := 15
const XP_MILK := 10
const XP_WHISTLE := 2
const XP_SALE := 3
const XP_SMOKE := 6

## Радиусы и времена способностей (без навыков)
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
## Охотник видит существ сквозь туман
const HUNTER_SIGHT := 45.0
## Аура бодрости травника
const VIGOR_RADIUS := 6.0


static func get_info(id: String) -> Dictionary:
	return DATA.get(id, {})


static func display_name(id: String) -> String:
	return get_info(id).get("name", "")


# --- Уровни и навыки ---

static func level_for(xp: int) -> int:
	var level := 1
	for need in LEVEL_XP:
		if xp >= need:
			level += 1
	return level


## Сколько опыта нужно до следующего уровня (0 — максимум)
static func next_level_xp(xp: int) -> int:
	for need in LEVEL_XP:
		if xp < need:
			return need
	return 0


static func free_points(xp: int, skills: PackedStringArray) -> int:
	return level_for(xp) - 1 - skills.size()


## Можно ли взять навык: он этого класса, ещё не взят, предыдущий в ветке взят, есть очко
static func can_learn(player_class: String, xp: int, skills: PackedStringArray, id: String) -> bool:
	if id in skills or free_points(xp, skills) <= 0:
		return false
	for branch in SKILLS.get(player_class, []):
		var previous := ""
		for skill in branch.skills:
			if skill.id == id:
				return previous == "" or previous in skills
			previous = skill.id
	return false


static func has(player: Node, id: String) -> bool:
	return player != null and player.get("skills") != null and id in player.skills


static func class_of(player: Node) -> String:
	if player == null or player.get("player_class") == null:
		return ""
	return player.player_class


# --- Бонусы ---

static func weapon_damage(player: Node, base: int) -> int:
	match class_of(player):
		"farmer":
			return maxi(base - 1, 1)
		"hunter":
			return base + 1 + (1 if has(player, "hunter_a1") else 0)
	return base


static func sprint_multiplier(player: Node) -> float:
	return 0.85 if class_of(player) == "mechanic" else 1.0


static func max_stamina(player: Node) -> float:
	if class_of(player) == "herbalist" and not has(player, "herbalist_a1"):
		return 80.0
	return 100.0


## Сколько урожая добавить или убрать к обычному
static func harvest_bonus(player: Node) -> int:
	match class_of(player):
		"farmer":
			return 2 if has(player, "farmer_a1") else 1
		"hunter":
			return -1
	return 0


## Сколько воды получает грядка от одного полива (1 — обычный полив)
static func water_amount(player: Node) -> float:
	match class_of(player):
		"farmer":
			return 1.5
		"hunter":
			return 0.5
	return 1.0


## Огнестрел и снаряжение охотника, инструменты механика
const HUNTER_GEAR := ["slingshot", "shotgun", "rifle", "ammo"]
const MECHANIC_GEAR := ["shovel", "hammer", "watering_can", "flashlight", "pitchfork", "trap"]


## Механику инструменты дешевле, охотнику — оружие и патроны
static func shop_price(player_class: String, entry: Dictionary) -> int:
	if (player_class == "mechanic" and entry.id in MECHANIC_GEAR) or (player_class == "hunter" and entry.id in HUNTER_GEAR):
		return int(round(entry.price * 0.75))
	return entry.price


## Охотник стреляет кучнее
static func spread_multiplier(player: Node) -> float:
	return 0.5 if class_of(player) == "hunter" else 1.0


static func milk_amount(player: Node) -> int:
	if class_of(player) != "herder":
		return 1
	return 3 if has(player, "herder_a1") else 2


static func ability_cooldown(player: Node) -> float:
	var base: float = get_info(class_of(player)).get("cooldown", 0.0)
	if has(player, "mechanic_a1"):
		return base * 0.5
	if has(player, "hunter_b2"):
		return 25.0
	if has(player, "herder_a3"):
		return 8.0
	if has(player, "herbalist_b2"):
		return 20.0
	return base


static func feed_growth(player: Node) -> float:
	return 0.3 if has(player, "farmer_a3") else FEED_GROWTH


static func feed_radius(player: Node) -> float:
	return 8.0 if has(player, "farmer_a3") else FEED_RADIUS


static func track_time(player: Node) -> float:
	return 30.0 if has(player, "hunter_b2") else TRACK_TIME


static func whistle_radius(player: Node) -> float:
	return WHISTLE_RADIUS * 2.0 if has(player, "herder_a3") else WHISTLE_RADIUS


static func smoke_radius(player: Node) -> float:
	return 10.0 if has(player, "herbalist_b1") else SMOKE_RADIUS


static func smoke_scare_time(player: Node) -> float:
	return 10.0 if has(player, "herbalist_b1") else SMOKE_SCARE_TIME


static func herbalist_sale_bonus(player: Node) -> float:
	return 1.6 if has(player, "herbalist_b3") else 1.3


static func hunter_sight(player: Node) -> float:
	return 75.0 if has(player, "hunter_b1") else HUNTER_SIGHT
