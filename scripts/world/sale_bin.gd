extends Interactable

## Ящик скупки на рынке: бросьте урожай внутрь или подойдите с ним в руке и нажмите E.
## Продаёт только хост, деньги общие.

@onready var _hopper: Area3D = $Hopper


func _ready() -> void:
	_hopper.body_entered.connect(_on_body_entered)


func get_hint(item: PickupItem) -> String:
	if item and Economy.price_of(item.scene_file_path) > 0:
		return "E — продать: %s за %d" % [item.display_name, Economy.price_of(item.scene_file_path)]
	return "Скупка урожая — бросьте урожай в ящик"


func interact(player: Node3D, info: Dictionary) -> Dictionary:
	if info.get("tool", "") != "hand":
		return {}
	var held: String = player.get("held_scene")
	var price := Economy.price_of(held)
	if price <= 0:
		return {"message": "Возьмите урожай в руку или бросьте его в ящик"}
	_sell(Economy.name_of(held), price)
	return {"remove_held": true}


func _on_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server() or body.is_queued_for_deletion():
		return
	var price := Economy.price_of(body.scene_file_path)
	if price <= 0:
		return
	_sell(body.get("display_name"), price)
	body.queue_free()


func _sell(item_name: String, price: int) -> void:
	var economy := get_tree().get_first_node_in_group("economy") as Economy
	economy.add(price)
	economy.announce.rpc("Продано: %s +%d" % [item_name, price])
