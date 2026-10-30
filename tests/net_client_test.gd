extends SceneTree

## Сетевой тест, сторона клиента (см. net_host_test.gd).
## Подключается к 127.0.0.1 и делает всё через запросы к хосту.

const TIMEOUT_FRAMES := 600

var main: Node
var player: Player
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run()


func check(cond: bool, msg: String) -> void:
	print(("КЛИЕНТ OK   " if cond else "КЛИЕНТ FAIL ") + msg)
	if not cond:
		failures += 1


func wait_for(cond: Callable) -> bool:
	for i in TIMEOUT_FRAMES:
		if cond.call():
			return true
		await physics_frame
	return false


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func aim_at(target: Vector3) -> void:
	var cam: Camera3D = player.get_node("Head/Camera3D")
	var dir := target - cam.global_position
	player.rotation.y = atan2(-dir.x, -dir.z)
	player.get_node("Head").rotation.x = atan2(dir.y, Vector2(dir.x, dir.z).length())


func _run() -> void:
	await physics_frame
	root.get_node("Network").player_name = "Клиент"
	root.get_node("Network").player_class = "hunter"
	main._start_join("127.0.0.1")
	var players: Node = main.get_node("Players")
	var items: Node = main.get_node("Items")

	var my_name := func(): return str(root.multiplayer.get_unique_id())
	check(await wait_for(func(): return players.get_node_or_null(my_name.call()) != null), "свой персонаж создан хостом")
	player = players.get_node(my_name.call())
	check(await wait_for(func(): return players.get_child_count() == 2), "виден хост")
	check(players.get_node("1").player_name == "Хост", "имя хоста дошло")
	check(players.get_node("1").player_class == "farmer", "клиент видит, что хост — фермер")
	var host_model: Node = players.get_node("1").get_node_or_null("Body/Model")
	check(host_model != null and host_model.get_child(0).scene_file_path.ends_with("farmer.glb"), "клиент видит хоста в модели фермера")
	var expected: int = main._placed_items.size()
	check(await wait_for(func(): return items.get_child_count() == expected), "пришли все %d предметов от хоста" % expected)
	var crate: Grabbable = items.get_node("Crate1")
	check(crate.freeze, "у клиента предметы не считают физику сами")
	await frames(30)

	# Хватка и бросок через хоста
	player.global_position = crate.global_position + Vector3(0, -0.4, 2.2)
	await frames(10)
	aim_at(crate.global_position)
	await frames(5)
	player._on_primary()
	await frames(60)
	var hold := player.get_hold_position()
	check(crate.global_position.distance_to(hold) < 1.0, "ящик висит перед клиентом (%.2f м)" % crate.global_position.distance_to(hold))
	check(crate.holder_count == 1, "хост сообщил, что ящик несут")
	var before := crate.global_position
	player.get_node("Head").rotation.x = 0.0
	await frames(20)
	player.release_grab(true)
	await frames(90)
	check(crate.global_position.distance_to(before) > 2.0, "ящик улетел после броска (%.1f м)" % crate.global_position.distance_to(before))

	# Фонарь: взять, включить, выбросить
	var flashlight: Node3D = items.get_node("Flashlight")
	var flashlight_ref: WeakRef = weakref(flashlight)
	player.global_position = Vector3(-8.1, 0.05, -0.8)
	await frames(10)
	aim_at(flashlight.global_position)
	await frames(5)
	player._try_pickup()
	flashlight = null
	check(await wait_for(func(): return player.inventory.get_selected().get("name") == "Фонарь"), "фонарь в инвентаре")
	check(await wait_for(func(): return flashlight_ref.get_ref() == null), "фонарь исчез со стола и у клиента")
	await frames(5)
	player._on_primary()
	check(player.held_active, "фонарь включён")
	await frames(120)
	var count := items.get_child_count()
	player._drop_selected()
	check(await wait_for(func(): return items.get_child_count() == count + 1), "выброшенный фонарь появился в мире")

	# Ферма по сети: вторая лопата у сарая, вскопать дальнюю грядку
	var shovel: Node3D = items.get_node("Shovel2")
	player.global_position = shovel.global_position + Vector3(0, -0.1, 1.6)
	await frames(10)
	aim_at(shovel.global_position)
	await frames(5)
	player._try_pickup()
	check(await wait_for(func(): return player.inventory.get_selected().get("name") == "Лопата"), "клиент взял лопату")
	var plot: Plot = main.get_node("Plots/Plot18")
	player.global_position = plot.global_position + Vector3(0, 0.05, 2.3)
	await frames(10)
	aim_at(plot.global_position + Vector3(0, 0.25, 0))
	await frames(5)
	player._on_primary()
	check(await wait_for(func(): return plot.state == Plot.State.TILLED), "клиент видит вскопанную грядку")

	var day_night: DayNight = main.get_node("DayNight")
	check(await wait_for(func(): return day_night.is_night()), "у клиента тоже наступила ночь")
	var creatures: Node = main.get_node("Creatures")
	check(await wait_for(func(): return creatures.get_child_count() > 0), "клиент видит Грядочника")
	if creatures.get_child_count() > 0:
		var creature: Node3D = creatures.get_child(0)
		var start := creature.global_position
		await frames(60)
		check(creature.global_position.distance_to(start) > 0.5, "Грядочник у клиента движется")
		# Плавность: со сглаживанием существо сдвигается почти каждый кадр, без рывков
		var still := 0
		var moving := 0
		var biggest := 0.0
		var last := creature.global_position
		# Копим 30 кадров ходьбы (не дольше 10 с): стоять, пока ешь грядку, законно
		for i in 600:
			if moving + still >= 30:
				break
			await process_frame
			var step := creature.global_position.distance_to(last)
			last = creature.global_position
			# Стоять на месте законно, пока существо ест грядку: считаем только ходьбу
			if creature.state != Creature.State.APPROACH and creature.state != Creature.State.FLEE:
				continue
			if step < 0.0005:
				still += 1
			else:
				moving += 1
			biggest = maxf(biggest, step)
		check(moving >= (moving + still) * 0.8 and moving >= 3 and biggest < 0.25, "существо у клиента движется плавно (на ходу кадров с движением %d, без %d, наибольший шаг %.2f м)" % [moving, still, biggest])
		player._try_ability()
		check(await wait_for(func(): return creature.tracked), "«Выследить» охотника-клиента подсветил существо")

		# Выстрел клиента: попадания считает хост
		if not player.inventory.has_free_slot():
			player.inventory.take_selected()
		player.inventory.add("res://scenes/items/shotgun.tscn", "Двустволка", {"loaded": 2})
		await frames(5)
		var shot_ref: WeakRef = weakref(creature)
		creature = null
		for i in 2:
			var target: Node3D = shot_ref.get_ref()
			if target == null:
				break
			player.global_position = Vector3(target.global_position.x, 0.05, target.global_position.z + 3.0)
			await frames(2)
			aim_at(target.global_position + Vector3(0, 0.4, 0))
			player._on_primary()
			await frames(30)
		check(shot_ref.get_ref() == null or shot_ref.get_ref().hp < shot_ref.get_ref().max_hp, "выстрел клиента ранил существо")
		player.inventory.take_selected()

	# Деньги общие: хост поставил 100
	var economy: Economy = main.get_node("Economy")
	check(await wait_for(func(): return economy.money == 100), "клиент видит общие деньги")

	# Навык и улучшение от клиента: хост дал 40 опыта
	check(await wait_for(func(): return PlayerClasses.free_points(player.xp, player.skills) == 1), "клиенту пришёл опыт и очко навыка")
	player._request_learn.rpc_id(1, "hunter_a1")
	check(await wait_for(func(): return "hunter_a1" in player.skills), "клиент взял навык")
	player._request_upgrade.rpc_id(1, "pump")
	var upgrades: FarmUpgrades = main.get_node("FarmUpgrades")
	check(await wait_for(func(): return upgrades.is_bought("pump")), "клиент купил колонку для всей фермы")
	check(main.get_node("UpgradePump").visible, "и видит её")

	# Клиент за рулём: клавиши уходят хосту, пикап едет у всех
	var truck: Truck = main.get_node("Truck")
	player.test_controls = true
	player.global_position = truck.global_position + truck.global_basis.x * 2.2 + Vector3(0, -0.05, 0)
	await frames(10)
	aim_at(truck.global_position + Vector3(0, 1.0, 0))
	await frames(5)
	player._try_pickup()
	check(await wait_for(func(): return player.seated), "клиент сел за руль")
	var truck_start := truck.global_position
	Input.action_press("move_forward")
	await frames(150)
	Input.action_release("move_forward")
	check(truck.global_position.distance_to(truck_start) > 8.0, "пикап едет от клавиш клиента (%.1f м)" % truck.global_position.distance_to(truck_start))
	check(player.global_position.distance_to(truck.get_seat_position(0)) < 1.0, "клиент сидит в едущем пикапе")
	player._try_pickup()
	await frames(10)

	# Хост ранит клиента, а потом поднимает
	check(await wait_for(func(): return player.health < 60.0 or player.downed), "клиент получил урон")
	check(await wait_for(func(): return player.downed), "клиент без сознания")
	check(await wait_for(func(): return not player.downed and player.health >= 29.0), "хост поднял клиента")

	# Вылет и возвращение: прогресс должен вернуться
	var skills_before := player.skills
	var xp_before := player.xp
	var items_before := []
	for slot: Dictionary in player.inventory.slots:
		if not slot.is_empty():
			items_before.append(slot.path)
	await frames(30)
	main._leave()
	await frames(60)
	main._start_join("127.0.0.1")
	check(await wait_for(func(): return players.get_node_or_null(my_name.call()) != null), "клиент снова подключился")
	player = players.get_node(my_name.call())
	check(await wait_for(func(): return player.xp == xp_before and "hunter_a1" in player.skills), "после переподключения вернулись опыт и навыки")
	check(await wait_for(func():
		var now := []
		for slot: Dictionary in player.inventory.slots:
			if not slot.is_empty():
				now.append(slot.path)
		return now.size() == items_before.size() and items_before.size() > 0), "после переподключения вернулся инвентарь (%d вещей)" % items_before.size())

	await frames(30)
	root.get_node("Network").leave()
	print("КЛИЕНТ ИТОГ: %s" % ("всё прошло" if failures == 0 else "провалов: %d" % failures))
	await frames(10)
	quit(failures)
