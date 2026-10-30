class_name FenceSegment
extends Interactable

## Пролёт забора между двумя столбами (3 м). Существа его грызут,
## игроки чинят молотком. Прочность меняет только хост.
## Сломанный пролёт остаётся видимым для прицела (чтобы его можно было починить),
## но через него проходят все.

## Обычная прочность пролёта и прочность каменного забора (общее улучшение)
const MAX_HP := 3
const STONE_HP := 6
const STONE_COLOR := Color(0.6, 0.6, 0.62)
const SOLID_LAYER := 1
## Слой «объект для прицела» — по нему никто не сталкивается
const INTERACT_LAYER := 8

var hp := MAX_HP:
	set(value):
		hp = value
		if is_node_ready():
			_update_look()
## Сколько прочности у целого пролёта. Синхронизируется для подсказки.
var max_hp := MAX_HP
## Каменный ли забор (общее улучшение). Синхронизируется для вида.
var stone := false:
	set(value):
		stone = value
		if is_node_ready():
			_update_look()

## Только на хосте: прибавка от навыка механика «Двойные жерди»
var _bonus_hp := 0

@onready var _rail_top: Node3D = $RailTop
@onready var _rail_bottom: Node3D = $RailBottom


func _ready() -> void:
	add_to_group("fence")
	_update_look()


func is_broken() -> bool:
	return hp <= 0


func damage(amount: int) -> void:
	var was_broken := is_broken()
	hp = maxi(hp - amount, 0)
	if is_broken() and not was_broken:
		_raise_alarm()


func reset() -> void:
	_bonus_hp = 0
	stone = false
	max_hp = MAX_HP
	hp = MAX_HP


## Каменный забор: прочнее, сразу целый
func make_stone() -> void:
	stone = true
	max_hp = STONE_HP + _bonus_hp
	hp = max_hp


## Починка: механик — сразу целиком (а с навыком ещё и прочнее), остальные — на 1
func repair_by(player: Node, full: bool) -> void:
	if PlayerClasses.has(player, "mechanic_a2"):
		_bonus_hp = 2
		max_hp = (STONE_HP if stone else MAX_HP) + _bonus_hp
	hp = max_hp if full else mini(hp + 1, max_hp)


func get_hint(item: PickupItem) -> String:
	var has_hammer := item != null and item.tool == "hammer"
	if hp >= max_hp:
		return "Забор цел"
	var state := "сломан" if is_broken() else "повреждён (%d/%d)" % [hp, max_hp]
	return "Забор %s — %s" % [state, "ЛКМ: починить" if has_hammer else "нужен молоток"]


func interact(player: Node3D, info: Dictionary) -> Dictionary:
	if info.get("tool", "") != "hammer":
		return {}
	if hp >= max_hp:
		return {"message": "Забор цел"}
	var before := hp
	# Механик чинит сразу целиком, остальные — по одной прочности за удар
	var is_mechanic := PlayerClasses.class_of(player) == "mechanic"
	repair_by(player, is_mechanic)
	if is_mechanic:
		player.add_xp(PlayerClasses.XP_REPAIR_PER_HP * (hp - before))
	return {"message": "Забор починен" if hp >= max_hp else "Забор подлатан (%d/%d)" % [hp, max_hp]}


## Середина пролёта (узел стоит в столбе, пролёт идёт по локальной оси X)
func get_center() -> Vector3:
	return global_position + global_basis.x * 1.5


## Сигнализация механика: все узнают, где сломан забор
func _raise_alarm() -> void:
	for player: Player in get_tree().get_nodes_in_group("players"):
		if PlayerClasses.has(player, "mechanic_a3"):
			var economy := get_tree().get_first_node_in_group("economy") as Economy
			if economy:
				economy.announce.rpc("Сигнализация: сломан забор %s!" % Dog._side(get_center()))
			return


func _update_look() -> void:
	_rail_top.visible = hp >= 2
	# Повреждённая верхняя жердь перекошена
	_rail_top.rotation.z = 0.0 if hp >= max_hp else deg_to_rad(8.0)
	_rail_bottom.visible = hp >= 1
	# Камень — общий серый материал на все пролёты, дерево — материал из сцены
	var material: Material = _stone_material() if stone else null
	for part: MeshInstance3D in [$Post, _rail_top, _rail_bottom]:
		part.material_override = material
	collision_layer = INTERACT_LAYER if is_broken() else SOLID_LAYER


static var _stone := StandardMaterial3D.new()


static func _stone_material() -> StandardMaterial3D:
	_stone.albedo_color = STONE_COLOR
	_stone.roughness = 1.0
	return _stone
