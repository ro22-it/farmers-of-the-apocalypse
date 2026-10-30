class_name Economy
extends Node

## Общие деньги команды. Меняет только хост, остальным сумма приходит
## через синхронизатор.

const START_MONEY := 30

## Цены продажи и названия по сценам предметов: узнаём один раз, создав экземпляр
static var _prices := {}
static var _names := {}

var money := START_MONEY


func _ready() -> void:
	add_to_group("economy")


func reset() -> void:
	money = START_MONEY


## Только на хосте
func add(amount: int) -> void:
	money += amount


## Только на хосте. Возвращает false, если денег не хватает.
func try_spend(amount: int) -> bool:
	if money < amount:
		return false
	money -= amount
	return true


static func price_of(scene_path: String) -> int:
	_learn(scene_path)
	return _prices[scene_path]


static func name_of(scene_path: String) -> String:
	_learn(scene_path)
	return _names[scene_path]


static func _learn(scene_path: String) -> void:
	if _prices.has(scene_path):
		return
	_prices[scene_path] = 0
	_names[scene_path] = ""
	if scene_path.begins_with(PickupItem.ITEMS_DIR) and ResourceLoader.exists(scene_path):
		var node: Node = load(scene_path).instantiate()
		if node.get("sell_price") != null:
			_prices[scene_path] = node.get("sell_price")
			_names[scene_path] = node.get("display_name")
		node.free()


## Сообщение всем игрокам: «Продано», «Куплено».
@rpc("authority", "call_local", "reliable")
func announce(text: String) -> void:
	get_tree().call_group("local_player", "show_message", text)
