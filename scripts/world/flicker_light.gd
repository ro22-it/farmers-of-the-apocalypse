extends OmniLight3D

## Огонь в печи: свет дрожит, как от живого пламени.

@export var flicker := 0.35
@export var speed := 9.0

var _base := 1.0
var _time := 0.0


func _ready() -> void:
	_base = light_energy
	_time = randf() * 100.0


func _process(delta: float) -> void:
	_time += delta * speed
	var wave := sin(_time) * 0.5 + sin(_time * 2.3 + 1.7) * 0.3 + sin(_time * 5.1) * 0.2
	light_energy = _base * (1.0 + wave * flicker)
