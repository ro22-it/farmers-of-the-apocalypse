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


func _run() -> void:
	await physics_frame
	root.get_node("Network").player_name = "Хост"
	main._start_host()
	var players: Node = main.get_node("Players")

	check(await wait_for(func(): return players.get_child_count() == 2), "клиент подключился, игроков: %d" % players.get_child_count())
	var remote: Player
	for p in players.get_children():
		if p.name != "1":
			remote = p
	check(remote != null and remote.player_name == "Клиент", "имя клиента дошло")

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

	var truck: Truck = main.get_node("Truck")
	var truck_start := truck.global_position
	check(await wait_for(func(): return truck.global_position.distance_to(truck_start) > 8.0), "хост видит, как клиент ведёт пикап")
	check(await wait_for(func(): return players.get_child_count() == 1), "после выхода клиента его персонаж убран")
	print("ХОСТ ИТОГ: %s" % ("всё прошло" if failures == 0 else "провалов: %d" % failures))
	quit(failures)
