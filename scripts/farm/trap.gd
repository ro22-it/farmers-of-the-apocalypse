class_name Trap
extends Interactable

## Поставленный капкан. Держит любое существо, по нему в это время урон двойной.
## E — взвести снова (если сработал) или забрать обратно в инвентарь.

const HOLD_TIME := 8.0
const ITEM_SCENE := "res://scenes/items/trap.tscn"

## Взведён ли. Синхронизируется для вида и подсказки.
var armed := true:
	set(value):
		armed = value
		if is_node_ready():
			_update_look()

@onready var _jaw_left: Node3D = $JawLeft
@onready var _jaw_right: Node3D = $JawRight


func _ready() -> void:
	$Trigger.body_entered.connect(_on_body_entered)
	_update_look()


func get_hint(_item: PickupItem) -> String:
	return "Капкан взведён — E: забрать" if armed else "Капкан сработал — E: взвести"


func interact(_player: Node3D, info: Dictionary) -> Dictionary:
	if info.get("tool", "") != "hand":
		return {}
	if not armed:
		armed = true
		return {"message": "Капкан взведён"}
	queue_free()
	return {"give": {"scene": ITEM_SCENE, "name": "Капкан", "state": {}}}


func _on_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server() or not armed or not body is Creature:
		return
	armed = false
	body.trap(HOLD_TIME)
	SoundBank.play_at(get_tree(), "thud", global_position)


func _update_look() -> void:
	# Взведённый — челюсти раскрыты, сработавший — сомкнуты
	_jaw_left.rotation.z = deg_to_rad(-70.0 if armed else 0.0)
	_jaw_right.rotation.z = deg_to_rad(70.0 if armed else 0.0)
