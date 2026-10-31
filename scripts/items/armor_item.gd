class_name ArmorItem
extends PickupItem

## Броня: ЛКМ с ней в руке — надеть. Слот один на голову, тело и ноги:
## новая вещь заменяет старую. Защита складывается, каждый удар портит
## всё надетое на единицу прочности (см. Player.take_damage).

const SLOT_NAMES := {"head": "голова", "body": "тело", "legs": "ноги"}

@export_enum("head", "body", "legs") var slot := "head"
## Доля урона, которую снимает вещь
@export var protection := 0.15
@export var durability := 6
## Как выглядит на персонаже (CharacterModel.ARMOR_LOOKS)
@export var look := "pot"


func use(user: Player) -> void:
	user.wear_armor(self)


## Прочность переживает снятие и передачу другому
func get_state() -> Dictionary:
	return {"durability": durability}


func set_state(state: Dictionary) -> void:
	durability = state.get("durability", durability)


func get_use_hint() -> String:
	return "ЛКМ — надеть (%s, защита %d%%, прочность %d)" % [SLOT_NAMES[slot], roundi(protection * 100.0), durability]
