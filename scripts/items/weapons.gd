class_name Weapons
extends RefCounted

## Справочник оружия. Углы — в градусах, время — в секундах.
## magazine 0 — патроны не нужны (рогатка).

const DATA := {
	"slingshot": {
		"name": "Рогатка", "damage": 1, "pellets": 1, "spread": 1.5, "range": 30.0,
		"cooldown": 0.7, "magazine": 0, "reload": 0.0, "recoil": 1.5, "impulse": 2.0,
		"knockback": 0.6, "sound": "twang", "tracer": Color(0.8, 0.75, 0.6),
	},
	"shotgun": {
		"name": "Двустволка", "damage": 1, "pellets": 8, "spread": 4.5, "range": 25.0,
		"cooldown": 0.35, "magazine": 2, "reload": 2.0, "recoil": 7.0, "impulse": 4.0,
		"knockback": 2.0, "sound": "shotgun", "tracer": Color(1.0, 0.85, 0.5),
	},
	"rifle": {
		"name": "Винтовка", "damage": 4, "pellets": 1, "spread": 0.4, "range": 70.0,
		"cooldown": 1.0, "magazine": 5, "reload": 2.5, "recoil": 4.0, "impulse": 8.0,
		"knockback": 1.5, "sound": "rifle", "tracer": Color(1.0, 0.95, 0.7),
	},
	# Самодельное с верстака: без патронов, но со своими причудами
	"nailgun": {
		"name": "Гвоздемёт", "damage": 1, "pellets": 1, "spread": 3.0, "range": 22.0,
		"cooldown": 0.28, "magazine": 0, "reload": 0.0, "recoil": 1.2, "impulse": 1.5,
		"knockback": 0.4, "sound": "metal_hit", "tracer": Color(0.75, 0.78, 0.82),
	},
	"corn_cannon": {
		"name": "Кукурузная пушка", "damage": 3, "pellets": 1, "spread": 2.0, "range": 30.0,
		"cooldown": 1.6, "magazine": 0, "reload": 0.0, "recoil": 9.0, "impulse": 14.0,
		"knockback": 4.0, "sound": "thud", "tracer": Color(1.0, 0.85, 0.2),
	},
}

## Во что попадают пули: мир, предметы, существа, животные
const HIT_MASK := 1 | 4 | 16 | 32
## Прицеливание (ПКМ) уменьшает разброс
const AIM_SPREAD := 0.5
const AIM_FOV := 55.0


static func get_info(id: String) -> Dictionary:
	return DATA.get(id, {})
