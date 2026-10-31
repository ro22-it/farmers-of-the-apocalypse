extends Node3D

## Корень игровой сцены: меню, создание игроков и предметов в сети,
## сброс мира (грядки, забор, время, существа) в начале и конце игры.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const SPAWN_POINT := Vector3(0.0, 0.05, 18.0)
const SPAWN_STEP := 1.5

## Предметы, расставленные в редакторе: путь к сцене и положение.
## В сети их заново создаёт хост через спавнер, чтобы у всех были одинаковые узлы.
var _placed_items: Array[Dictionary] = []

@onready var _players: Node3D = $Players
@onready var _items: Node3D = $Items
@onready var _player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _item_spawner: MultiplayerSpawner = $ItemSpawner
@onready var _menu: Menu = $Menu
@onready var _menu_camera: Camera3D = $MenuCamera
@onready var _day_night: DayNight = $DayNight
@onready var _night_director: NightDirector = $NightDirector
@onready var _creature_spawner: MultiplayerSpawner = $CreatureSpawner
@onready var _economy: Economy = $Economy
@onready var _truck: Truck = $Truck
@onready var _farm_upgrades: FarmUpgrades = $FarmUpgrades
@onready var _save: SaveSystem = $SaveSystem
var _run: RunDirector


func _ready() -> void:
	_run = RunDirector.new()
	_run.name = "RunDirector"
	add_child(_run)
	if TouchControls.wanted():
		add_child(TouchControls.new())
	_player_spawner.spawn_function = _create_player
	for item in _items.get_children():
		_placed_items.append({"name": item.name, "scene": item.scene_file_path, "transform": item.transform})
	for path in _item_scene_paths():
		_item_spawner.add_spawnable_scene(path)
	_creature_spawner.add_spawnable_scene(NightDirector.GRYADOCHNIK.resource_path)
	_creature_spawner.add_spawnable_scene(NightDirector.TARAN.resource_path)
	_creature_spawner.add_spawnable_scene(NightDirector.ROJ.resource_path)
	_creature_spawner.add_spawnable_scene(NightDirector.PUGALSHIK.resource_path)
	_creature_spawner.add_spawnable_scene(NightDirector.KUKURUZNIK.resource_path)
	_creature_spawner.add_spawnable_scene(NightDirector.FOREST_LORD.resource_path)

	_menu.host_pressed.connect(_start_host)
	_menu.continue_pressed.connect(_start_host.bind(true))
	_day_night.phase_changed.connect(_on_phase_changed)
	_menu.join_pressed.connect(_start_join)
	_menu.leave_pressed.connect(_leave)
	Network.session_started.connect(_on_session_started)
	Network.session_ended.connect(_on_session_ended)
	Network.player_joined.connect(_on_player_joined)
	Network.player_left.connect(_on_player_left)
	_handle_debug_args()


## continue_game — продолжить сохранённый забег, иначе новый
func _start_host(continue_game := false) -> void:
	# Прогресс игроков нужен до подключения хоста: он сам первый «входит» в игру
	var loaded := continue_game and _save.read()
	if not loaded:
		_save.clear_profiles()
	var err := Network.host()
	if err != OK:
		_menu.show_main("Не удалось создать игру (ошибка %d). Возможно, порт %d занят." % [err, Network.DEFAULT_PORT])
		return
	# Пересоздаём уже в сети, чтобы спавнер отслеживал предметы и слал их новым игрокам
	_reset_world(not loaded)
	if loaded:
		_save.apply_world()


func _start_join(address: String) -> void:
	# Свои предметы убираем заранее: хост пришлёт свои сразу после подключения
	_reset_world(false)
	_menu.show_connecting("Подключение к %s…" % address)
	var err := Network.join(address)
	if err != OK:
		_reset_world(true)
		_menu.show_main("Не удалось начать подключение (ошибка %d)" % err)


func _leave() -> void:
	# Законченный забег не сохраняем — его сохранение уже удалено
	if multiplayer.is_server() and not _run.over:
		_save.save()
	Network.leave()
	_on_session_ended("")


func _on_session_started() -> void:
	_menu.enter_session()
	_day_night.running = true


func _on_session_ended(reason: String) -> void:
	_day_night.running = false
	for player in _players.get_children():
		_players.remove_child(player)
		player.queue_free()
	_reset_world(true)
	_menu_camera.current = true
	_menu.show_main(reason)


func _on_player_joined(id: int, player_name: String, player_class: String) -> void:
	var spot := SPAWN_POINT + Vector3(SPAWN_STEP * _players.get_child_count(), 0.0, 0.0)
	# Вернувшийся игрок получает свой класс, место и прогресс
	var profile := _save.profile_for(player_name)
	var player: Player = _player_spawner.spawn({
		"id": id,
		"name": player_name,
		"class": profile.get("class", player_class),
		"position": profile.get("position", spot),
	})
	if not profile.is_empty():
		_save.apply_profile(player, profile)


func _on_player_left(id: int) -> void:
	var player := _players.get_node_or_null(str(id))
	if player:
		_save.remember(player)
		player.queue_free()


func _on_phase_changed(is_night: bool, _day: int) -> void:
	# Автосохранение на рассвете
	if not is_night and multiplayer.is_server() and _day_night.running:
		_save.save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and multiplayer.is_server() and _day_night.running:
		_save.save()


## Вызывается спавнером на всех компьютерах с одинаковыми данными.
func _create_player(data: Dictionary) -> Node:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = str(data.id)
	player.player_name = data.name
	player.player_class = data.get("class", "")
	player.position = data.position
	return player


## Начинает мир заново: утро первого дня, грядки и забор целы, существ нет.
## Предметы убирает, а с refill — ставит заново по расстановке из редактора
## (это делает только хост или игра без сети). Клиенту состояние потом пришлёт хост.
func _reset_world(refill: bool) -> void:
	_run.reset()
	_day_night.reset()
	_night_director.reset()
	_economy.reset()
	_farm_upgrades.reset()
	if multiplayer.is_server():
		_truck.reset()
	get_tree().call_group("plots", "reset")
	get_tree().call_group("fence", "reset")
	if multiplayer.is_server():
		get_tree().call_group("animals", "reset")
	for item in _items.get_children():
		_items.remove_child(item)
		item.queue_free()
	if not refill:
		return
	for placed in _placed_items:
		var item: Node3D = load(placed.scene).instantiate()
		item.name = placed.name
		item.transform = placed.transform
		_items.add_child(item, true)


func _item_scene_paths() -> Array[String]:
	var paths: Array[String] = []
	for file in ResourceLoader.list_directory(PickupItem.ITEMS_DIR):
		if file.ends_with(".tscn"):
			paths.append(PickupItem.ITEMS_DIR + file)
	return paths


## Отладка без рук: --name=Имя, --class=farmer, --host, --join=адрес, --screenshot=путь
func _handle_debug_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--name="):
			Network.player_name = Network.clean_name(arg.trim_prefix("--name="))
		elif arg.begins_with("--class="):
			Network.player_class = arg.trim_prefix("--class=")
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			_start_host()
		elif arg == "--continue":
			_start_host(true)
		elif arg.begins_with("--join="):
			_start_join(arg.trim_prefix("--join="))
		elif arg.begins_with("--screenshot="):
			_save_screenshot(arg.trim_prefix("--screenshot="))


func _save_screenshot(path: String) -> void:
	for i in 150:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
