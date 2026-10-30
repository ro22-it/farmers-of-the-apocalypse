extends OmniLight3D

## Фонарь на сторожевой вышке: горит ночью, Грядочник боится к нему подходить.

const SCARE_RADIUS := 10.0


func _ready() -> void:
	add_to_group("scare_lights")


func _process(_delta: float) -> void:
	visible = _is_on()


## Проверяет Грядочник: точка в круге света на земле
func scares(point: Vector3) -> bool:
	if not _is_on():
		return false
	return Vector2(point.x - global_position.x, point.z - global_position.z).length() <= SCARE_RADIUS


func _is_on() -> bool:
	var toggle := get_parent() as UpgradeToggle
	var day_night := get_tree().get_first_node_in_group("day_night") as DayNight
	return toggle != null and toggle.active and day_night != null and day_night.is_night()
