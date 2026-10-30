extends PickupItem

## Лейка на несколько поливов. Наполняется у бочки с водой.

const CAPACITY := 5

@export var water := CAPACITY


func get_state() -> Dictionary:
	return {"water": water}


func set_state(state: Dictionary) -> void:
	water = state.get("water", water)


func get_display_name() -> String:
	return "%s %d/%d" % [display_name, water, CAPACITY]


func get_interaction(user: Player, target: Interactable) -> Dictionary:
	if target is Plot and water <= 0:
		user.hud.show_message("Лейка пуста — наполните у бочки с водой")
		return {}
	return super(user, target)


func apply_result(result: Dictionary) -> bool:
	if result.get("refill", false):
		water = CAPACITY
	water = maxi(water - result.get("consume", 0), 0)
	return true
