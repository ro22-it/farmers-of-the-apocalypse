class_name EnergyDrink
extends PickupItem

## Энергетик: ЛКМ — выпить, минуту бег не устаёт.


func use(user: Player) -> void:
	user.drink_energy()


func get_use_hint() -> String:
	return "ЛКМ — выпить (минута без усталости)"
