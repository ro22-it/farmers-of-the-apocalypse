extends Interactable

## Дверь дома: E — открыть или закрыть. Состояние решает хост,
## остальным оно приходит через MultiplayerSynchronizer.

const OPEN_ANGLE := -100.0
const SWING_SPEED := 6.0

@export var is_open := false:
	set(value):
		if value != is_open:
			is_open = value
			_play_sound()

@onready var _hinge: Node3D = get_parent()
var _closed_rotation := 0.0


func _ready() -> void:
	_closed_rotation = _hinge.rotation.y


func _physics_process(delta: float) -> void:
	var target := _closed_rotation + (deg_to_rad(OPEN_ANGLE) if is_open else 0.0)
	_hinge.rotation.y = lerp_angle(_hinge.rotation.y, target, 1.0 - exp(-SWING_SPEED * delta))


func get_hint(_item: PickupItem) -> String:
	return "E — закрыть дверь" if is_open else "E — открыть дверь"


func interact(_player: Node3D, info: Dictionary) -> Dictionary:
	if info.get("tool", "") != "hand":
		return {}
	is_open = not is_open
	return {}


func _play_sound() -> void:
	if not is_inside_tree():
		return
	SoundBank.play_at(get_tree(), "door_open" if is_open else "door_close", global_position)
