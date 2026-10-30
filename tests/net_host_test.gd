extends SceneTree

## Сетевой тест, сторона хоста. Запускать вместе с net_client_test.gd:
##   godot --headless --path . --script tests/net_host_test.gd
##   godot --headless --path . --script tests/net_client_test.gd
## Хост ждёт клиента и проверяет, что видит его действия.

const TIMEOUT_FRAMES := 1800

var main: Node
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run()


func check(cond: bool, msg: String) -> void:
	print(("ХОСТ OK   " if cond else "ХОСТ FAIL ") + msg)
	if not cond:
		failures += 1


## Ждёт, пока условие станет истинным. Возвращает false по таймауту.
func wait_for(cond: Callable) -> bool:
	for i in TIMEOUT_FRAMES:
		if cond.call():
			return true
		await physics_frame
	return false


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	await physics_frame
	root.get_node("Network").player_name = "Хост"
	root.get_node("Network").player_class = "farmer"
	main._start_host()
	var players: Node = main.get_node("Players")

	check(await wait_for(func(): return players.get_child_count() == 2), "клиент подключился, игроков: %d" % players.get_child_count())
	var remote: Player
	for p in players.get_children():
		if p.name != "1":
			remote = p
	check(remote != null and remote.player_name == "Клиент", "имя клиента дошло")
	check(remote.player_class == "hunter", "хост видит, что клиент — охотник")

	check(await wait_for(func(): return remote.held_scene.ends_with("flashlight.tscn")), "видно фонарь в руке клиента")
	check(await wait_for(func(): return remote.held_active), "видно, что клиент включил фонарь")
	var crate: Node3D = main.get_node("Items/Crate1")
	check(crate.global_position.distance_to(Vector3(11, 0.4, -5)) > 1.5, "ящик сдвинут клиентом (%.1f м от места)" % crate.global_position.distance_to(Vector3(11, 0.4, -5)))

	var plot: Plot = main.get_node("Plots/Plot18")
	check(await wait_for(func(): return plot.state == Plot.State.TILLED), "хост видит грядку, вскопанную клиентом")

	# Ночь и существо — клиент должен увидеть
	var day_night: DayNight = main.get_node("DayNight")
	day_night.cycle_time = DayNight.DAY_LENGTH + 1.0
	await physics_frame
	main.get_node("NightDirector")._queue.clear()
	main.get_node("NightDirector").spawn_gryadochnik(Vector3(0.0, 0.3, 29.0))
	main.get_node("Economy").money = 100
	remote.add_xp(40)

	var truck: Truck = main.get_node("Truck")
	var truck_start := truck.global_position
	check(await wait_for(func(): return truck.global_position.distance_to(truck_start) > 8.0), "хост видит, как клиент ведёт пикап")
	check("hunter_a1" in remote.skills or await wait_for(func(): return "hunter_a1" in remote.skills), "хост видит навык клиента")
	check(main.get_node("FarmUpgrades").is_bought("pump"), "хост видит купленную клиентом колонку")

	# Урон и подъём: даём клиенту доехать на пикапе
	await frames(240)
	remote.take_damage(50.0, remote.global_position + Vector3.RIGHT)
	await frames(60)
	remote.take_damage(100.0, remote.global_position + Vector3.RIGHT)
	check(remote.downed, "клиент без сознания у хоста")
	await frames(90)
	var host_player: Player = players.get_node("1")
	host_player.global_position = remote.global_position + Vector3(1.5, 0.3, 0.0)
	await frames(5)
	host_player._request_revive.rpc_id(1, remote.get_path())
	await frames(5)
	check(not remote.downed and is_equal_approx(remote.health, Player.REVIVE_HEALTH), "хост поднял клиента")
	check(await wait_for(func(): return players.get_child_count() == 1), "клиент вышел")
	check(await wait_for(func(): return players.get_child_count() == 2), "клиент вернулся")
	var returned: Player
	for p in players.get_children():
		if p.name != "1":
			returned = p
	check(returned != null and "hunter_a1" in returned.skills and returned.player_class == "hunter", "хост вернул вернувшемуся класс и навыки")
	check(await wait_for(func(): return players.get_child_count() == 1), "после выхода клиента его персонаж убран")
	print("ХОСТ ИТОГ: %s" % ("всё прошло" if failures == 0 else "провалов: %d" % failures))
	quit(failures)
