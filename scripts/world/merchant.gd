extends Node3D

## Торговец в лавке: путешественник с рюкзаком, стоит за прилавком
## и машет, когда кто-то подходит.

const WAVE_DISTANCE := 6.0
const WAVE_COOLDOWN := 8.0

var _model: CharacterModel
var _cooldown := 0.0


func _ready() -> void:
	_model = CharacterModel.new()
	add_child(_model)
	_model.setup("hunter")


func _process(delta: float) -> void:
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	for player: Node3D in get_tree().get_nodes_in_group("players"):
		if player.global_position.distance_to(global_position) < WAVE_DISTANCE:
			_model.play_action("Wave")
			_cooldown = WAVE_COOLDOWN
			return
