class_name RunDirector
extends Node

## Цель забега: дожить до рассвета после последней ночи — победа;
## все игроки без сознания разом — поражение, ферма сгорает.
## Считает итоги (убитые твари, заработанные монеты) и у каждого игрока
## хранит рекорды между забегами в user://meta.cfg.
## Решает хост, итоги рассылает всем.

const WIN_NIGHTS := 15
## Сколько секунд все должны пролежать без сознания, чтобы засчитать поражение
const DEFEAT_DELAY := 3.0
const META_PATH := "user://meta.cfg"

var kills := 0
var earned := 0
var over := false

var _all_down_time := 0.0


func _ready() -> void:
	add_to_group("run_director")
	var day_night := get_tree().get_first_node_in_group("day_night") as DayNight
	if day_night:
		day_night.phase_changed.connect(_on_phase_changed)


func reset() -> void:
	kills = 0
	earned = 0
	over = false
	_all_down_time = 0.0


func _process(delta: float) -> void:
	if over or not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return
	for player: Player in players:
		if not player.downed:
			_all_down_time = 0.0
			return
	_all_down_time += delta
	if _all_down_time >= DEFEAT_DELAY:
		_finish(false)


## Только на хосте
func on_kill() -> void:
	kills += 1


## Только на хосте
func on_earned(amount: int) -> void:
	if amount > 0:
		earned += amount


func _on_phase_changed(is_night: bool, day: int) -> void:
	if over or is_night or not multiplayer.is_server():
		return
	# Рассвет после ночи N — это день N+1
	if day > WIN_NIGHTS:
		_finish(true)


func _finish(won: bool) -> void:
	over = true
	var day_night := get_tree().get_first_node_in_group("day_night") as DayNight
	var night := WIN_NIGHTS if won else (day_night.day if day_night else 1)
	_show_end.rpc(won, night, kills, earned)
	var save := get_tree().current_scene.get_node_or_null("SaveSystem") as SaveSystem
	if save:
		save.delete_save()


@rpc("authority", "call_local", "reliable")
func _show_end(won: bool, night: int, kill_count: int, money: int) -> void:
	over = true
	var day_night := get_tree().get_first_node_in_group("day_night") as DayNight
	if day_night:
		day_night.running = false
	var meta := record_run(won, night, kill_count)
	var title := "Победа! Ферма выстояла" if won else "Ферма сгорела"
	var subtitle := ("Вы продержались все %d ночей." % WIN_NIGHTS) if won else ("Все без сознания на %d-й ночи." % night)
	var rows := [
		{"header": true, "text": "Итоги забега"},
		{"text": "Ночей пережито: %d" % (night if won else night - 1), "button": "", "disabled": true},
		{"text": "Тварей побеждено: %d" % kill_count, "button": "", "disabled": true},
		{"text": "Заработано монет: %d" % money, "button": "", "disabled": true},
		{"header": true, "text": "Рекорды"},
		{"text": meta_line(meta), "button": "", "disabled": true},
		{"text": "", "button": "В меню", "id": "menu"},
	]
	get_tree().call_group("local_player", "show_end_screen", title, subtitle, rows)


## Записать забег в рекорды этого компьютера. Возвращает обновлённые рекорды.
static func record_run(won: bool, night: int, kill_count: int) -> Dictionary:
	var meta := load_meta()
	meta.runs += 1
	if won:
		meta.wins += 1
	meta.best_night = maxi(meta.best_night, night)
	meta.kills += kill_count
	# Без окна (автотесты) рекорды игрока не трогаем
	if DisplayServer.get_name() != "headless":
		var config := ConfigFile.new()
		for key in meta:
			config.set_value("meta", key, meta[key])
		config.save(META_PATH)
	return meta


static func load_meta() -> Dictionary:
	var meta := {"runs": 0, "wins": 0, "best_night": 0, "kills": 0}
	var config := ConfigFile.new()
	if config.load(META_PATH) == OK:
		for key in meta:
			meta[key] = config.get_value("meta", key, meta[key])
	return meta


## Бестиарий: каких тварей этот игрок уже встречал
static func mark_seen(creature_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var config := ConfigFile.new()
	config.load(META_PATH)
	var seen: PackedStringArray = config.get_value("bestiary", "seen", PackedStringArray())
	if creature_name in seen:
		return
	seen.append(creature_name)
	config.set_value("bestiary", "seen", seen)
	config.save(META_PATH)


static func seen_creatures() -> PackedStringArray:
	var config := ConfigFile.new()
	config.load(META_PATH)
	return config.get_value("bestiary", "seen", PackedStringArray())


## Классы, которые открываются забегами: класс -> до какой ночи дожить
const CLASS_UNLOCKS := {"herder": 4, "herbalist": 8}


## Открыт ли класс на этом компьютере
static func class_unlocked(class_id: String, meta: Dictionary) -> bool:
	return meta.best_night >= CLASS_UNLOCKS.get(class_id, 0)


static func unlock_hint(class_id: String) -> String:
	return "Откроется, когда доживёте до %d-й ночи" % CLASS_UNLOCKS.get(class_id, 0)


static func meta_line(meta: Dictionary) -> String:
	if meta.runs == 0:
		return "Первый забег. Цель — дожить до рассвета после %d-й ночи." % WIN_NIGHTS
	return "Забегов: %d · побед: %d · лучшая ночь: %d · тварей всего: %d" % [meta.runs, meta.wins, meta.best_night, meta.kills]
