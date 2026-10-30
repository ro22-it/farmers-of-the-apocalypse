class_name SaveSystem
extends Node

## Сохранение забега и прогресс игроков. Работает только у хоста.
## - Мир: день и время, деньги, улучшения, грядки, забор, коровы, пикап, предметы.
## - Игроки: прогресс по имени (класс, опыт, навыки, инвентарь, здоровье, патроны,
##   место). Вылетевший и вернувшийся с тем же именем получает всё обратно.
## Сохраняется на рассвете, раз в пару минут и при выходе хоста.

const VERSION := 1
const AUTOSAVE_INTERVAL := 120.0
## Без окна (автотесты) пишем в отдельный файл, чтобы не трогать сохранение игрока
const PLAYER_SAVE := "user://save.dat"
const TEST_SAVE := "user://test_save.dat"

var save_path := TEST_SAVE if DisplayServer.get_name() == "headless" else PLAYER_SAVE

## Прогресс игроков по имени — живёт и без файла, для переподключения
var _profiles := {}
## Прочитанное из файла, ждёт применения к миру
var _pending := {}
var _autosave_left := AUTOSAVE_INTERVAL

@onready var _main: Node = get_parent()


func _process(delta: float) -> void:
	if not _hosting():
		return
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		_autosave_left = AUTOSAVE_INTERVAL
		save()


static func has_save() -> bool:
	return FileAccess.file_exists(PLAYER_SAVE)


## Краткое описание сохранения для кнопки «Продолжить»
static func info() -> String:
	var data := _read_file(PLAYER_SAVE)
	if data.is_empty():
		return ""
	return "День %d, %d монет" % [data.get("day", 1), data.get("money", 0)]


func clear_profiles() -> void:
	_profiles.clear()


## Прочитать файл: прогресс игроков доступен сразу, мир применяется потом
func read() -> bool:
	_pending = _read_file(save_path)
	if _pending.is_empty():
		return false
	_profiles = _pending.get("profiles", {})
	return true


func save() -> bool:
	if not multiplayer.is_server():
		return false
	for player: Player in get_tree().get_nodes_in_group("players"):
		remember(player)
	var data := _world_data()
	data.profiles = _profiles
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_var(data)
	return true


func delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


# --- Игроки ---

func remember(player: Player) -> void:
	_profiles[player.player_name] = {
		"class": player.player_class,
		"xp": player.xp,
		"skills": player.skills,
		"health": player.health if not player.downed else Player.REVIVE_HEALTH,
		"ammo": player.ammo,
		"inventory": player.reported_inventory,
		"position": player.global_position,
	}


func profile_for(player_name: String) -> Dictionary:
	return _profiles.get(player_name, {})


## Вернуть игроку его прогресс. Инвентарь у владельца, поэтому шлём чуть позже —
## когда его персонаж точно появится у него.
func apply_profile(player: Player, profile: Dictionary) -> void:
	player.xp = profile.get("xp", 0)
	player.skills = profile.get("skills", PackedStringArray())
	player.health = profile.get("health", Player.MAX_HEALTH)
	player.ammo = profile.get("ammo", 0)
	var inventory: Array = profile.get("inventory", [])
	if inventory.is_empty():
		return
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(player) and player.is_inside_tree():
		player._restore_inventory.rpc_id(player.get_multiplayer_authority(), inventory)


# --- Мир ---

func _world_data() -> Dictionary:
	var day_night: DayNight = _main.get_node("DayNight")
	var truck: Truck = _main.get_node("Truck")
	var data := {
		"version": VERSION,
		"day": day_night.day,
		"cycle_time": day_night.cycle_time,
		"money": (_main.get_node("Economy") as Economy).money,
		"upgrades": (_main.get_node("FarmUpgrades") as FarmUpgrades).bought,
		"truck": {"transform": truck.global_transform, "motor": truck.motor_upgraded},
		"plots": {},
		"fence": {},
		"cows": {},
		"items": [],
	}
	for plot: Plot in get_tree().get_nodes_in_group("plots"):
		data.plots[_key(plot)] = {"state": plot.state, "crop": plot.crop, "growth": plot.growth, "moisture": plot.moisture,
			"boost": plot.growth_boost, "thorny": plot.thorny, "biting": plot.biting, "sticky": plot.sticky}
	for segment: FenceSegment in get_tree().get_nodes_in_group("fence"):
		data.fence[_key(segment)] = {"hp": segment.hp, "max_hp": segment.max_hp, "stone": segment.stone, "bonus": segment._bonus_hp}
	for cow: Cow in get_tree().get_nodes_in_group("cows"):
		data.cows[_key(cow)] = {"transform": cow.global_transform, "milk": cow.milk_ready}
	for item in _main.get_node("Items").get_children():
		if item is Corpse or item.is_queued_for_deletion():
			continue
		var entry := {"scene": item.scene_file_path, "transform": item.global_transform}
		if item.has_method("get_state"):
			entry.state = item.get_state()
		if item is Trap:
			entry.armed = item.armed
		data.items.append(entry)
	return data


## Применить прочитанное к уже созданному миру (хост, после сброса мира без предметов)
func apply_world() -> void:
	var data := _pending
	if data.is_empty():
		return
	var day_night: DayNight = _main.get_node("DayNight")
	day_night.day = data.get("day", 1)
	day_night.cycle_time = data.get("cycle_time", DayNight.START_TIME)
	(_main.get_node("Economy") as Economy).money = data.get("money", Economy.START_MONEY)
	(_main.get_node("FarmUpgrades") as FarmUpgrades).bought = data.get("upgrades", PackedStringArray())
	var truck: Truck = _main.get_node("Truck")
	truck.global_transform = data.truck.transform
	truck.motor_upgraded = data.truck.motor
	for path in data.plots:
		var plot := _main.get_node_or_null(path) as Plot
		if plot:
			var p: Dictionary = data.plots[path]
			plot.state = p.state
			plot.crop = p.crop
			plot.growth = p.growth
			plot.moisture = p.moisture
			plot.growth_boost = p.boost
			plot.thorny = p.thorny
			plot.biting = p.biting
			plot.sticky = p.sticky
	for path in data.fence:
		var segment := _main.get_node_or_null(path) as FenceSegment
		if segment:
			var f: Dictionary = data.fence[path]
			segment._bonus_hp = f.bonus
			segment.max_hp = f.max_hp
			segment.stone = f.stone
			segment.hp = f.hp
	for path in data.cows:
		var cow := _main.get_node_or_null(path) as Cow
		if cow:
			cow.global_transform = data.cows[path].transform
			cow.milk_ready = data.cows[path].milk
	var items: Node = _main.get_node("Items")
	for entry: Dictionary in data.items:
		var scene: String = entry.scene
		if not scene.begins_with(PickupItem.ITEMS_DIR) or not ResourceLoader.exists(scene):
			continue
		var item: Node3D = load(scene).instantiate()
		item.transform = entry.transform
		if entry.has("state") and item.has_method("set_state"):
			item.set_state(entry.state)
		if entry.has("armed") and item is Trap:
			item.armed = entry.armed
		items.add_child(item, true)
	_pending = {}


func _hosting() -> bool:
	var day_night := _main.get_node_or_null("DayNight") as DayNight
	return multiplayer.is_server() and day_night != null and day_night.running


func _key(node: Node) -> String:
	return str(_main.get_path_to(node))


static func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var data = file.get_var()
	return data if data is Dictionary and data.get("version", 0) == VERSION else {}
