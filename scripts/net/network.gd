extends Node

## Сетевая сессия: создание игры, подключение по IP и учёт игроков.
## Транспорт — ENet (прямое подключение). Steam позже подключится здесь же,
## остальной код работает через сигналы и не знает, какой транспорт внутри.

signal session_started
signal session_ended(reason: String)
## Только на хосте: игрок представился и его можно создавать в мире
signal player_joined(id: int, player_name: String, player_class: String)
## Только на хосте
signal player_left(id: int)

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
const MAX_NAME_LENGTH := 20
const SETTINGS_PATH := "user://settings.cfg"

var player_name := "Фермер"
var player_class := "farmer"
var last_address := "127.0.0.1"
## На хосте: имена игроков в сессии, id -> имя
var names: Dictionary = {}


func _ready() -> void:
	_load_settings()
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host(port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	names = {1: player_name}
	session_started.emit()
	player_joined.emit(1, player_name, player_class)
	return OK


func join(address: String, port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	last_address = address
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	names.clear()


func is_online() -> bool:
	return not multiplayer.multiplayer_peer is OfflineMultiplayerPeer


func clean_name(raw: String) -> String:
	var result := raw.strip_edges().left(MAX_NAME_LENGTH)
	return result if result != "" else "Фермер"


func _on_connected_to_server() -> void:
	session_started.emit()
	_register.rpc_id(1, player_name, player_class)


## Клиент сообщает хосту своё имя. Только после этого хост создаёт его персонажа:
## так у клиента к этому моменту уже точно загружена сцена.
@rpc("any_peer", "reliable")
func _register(new_name: String, new_class: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	names[id] = clean_name(new_name)
	player_joined.emit(id, names[id], new_class if new_class in PlayerClasses.ORDER else "farmer")


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	names.erase(id)
	player_left.emit(id)


func _on_connection_failed() -> void:
	leave()
	session_ended.emit("Не удалось подключиться. Проверьте IP и что хост создал игру.")


func _on_server_disconnected() -> void:
	leave()
	session_ended.emit("Хост закрыл игру.")


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	player_name = config.get_value("player", "name", player_name)
	player_class = config.get_value("player", "class", player_class)
	last_address = config.get_value("network", "last_address", last_address)


## Сохраняет имя и последний IP. Вызывает меню, чтобы тесты и отладочный
## запуск не перезаписывали настройки игрока.
func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("player", "name", player_name)
	config.set_value("player", "class", player_class)
	config.set_value("network", "last_address", last_address)
	config.save(SETTINGS_PATH)
