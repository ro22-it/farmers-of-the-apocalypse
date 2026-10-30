extends PickupItem

## Фонарь: ЛКМ включает и выключает свет.
## На этапе 4 свет начнёт отпугивать Грядочника.

@export var is_on := false

@onready var _light: SpotLight3D = $SpotLight3D


func _ready() -> void:
	super()
	_light.visible = is_on


func use(_user: Player) -> void:
	set_active(not is_on)


func get_use_hint() -> String:
	return "ЛКМ — выключить фонарь" if is_on else "ЛКМ — включить фонарь"


func is_active() -> bool:
	return is_on


func set_active(value: bool) -> void:
	is_on = value
	if _light:
		_light.visible = is_on
