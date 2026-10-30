class_name Corpse
extends Grabbable

## Тело побеждённого существа: физический предмет, как в R.E.P.O. —
## его отбрасывает выстрелом, можно пнуть, схватить и швырнуть.
## Через какое-то время исчезает (решает хост).

@export var lifetime := 90.0


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	lifetime -= delta
	if lifetime <= 0.0 and holders.is_empty():
		queue_free()
