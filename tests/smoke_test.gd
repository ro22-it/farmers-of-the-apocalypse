extends SceneTree

var main: Node
var player: Player

## Одиночная игра: хост без друзей. Проверяет хватку, бросок, инвентарь, фонарь
## цикл грядки, ночь (Грядочник, фонарь, забор), пикап, продажу, лавку, ступеньки
## и классы. Общие проверки — без класса, потом каждый класс отдельно.
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run()


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func wait_for(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await physics_frame
	return false


func aim_at(target: Vector3) -> void:
	var cam: Camera3D = player.get_node("Head/Camera3D")
	var dir := target - cam.global_position
	player.rotation.y = atan2(-dir.x, -dir.z)
	player.get_node("Head").rotation.x = atan2(dir.y, Vector2(dir.x, dir.z).length())


func _run() -> void:
	await frames(5)
	root.get_node("Network").player_class = ""
	main._start_host()
	await frames(120)
	player = main.get_node("Players/1")
	check(player.is_on_floor(), "игрок стоит на земле, y=%.2f" % player.global_position.y)

	for item in main.get_node("Items").get_children():
		check(item.global_position.y > -0.5, "%s не провалился, y=%.2f" % [item.name, item.global_position.y])
	var scarecrow: Node3D = main.get_node("Items/Scarecrow")
	check(scarecrow.global_basis.y.dot(Vector3.UP) > 0.95, "пугало стоит ровно")

	# Хватка ящика
	var crate: Grabbable = main.get_node("Items/Crate1")
	player.global_position = crate.global_position + Vector3(0, -0.4, 2.2)
	await frames(5)
	aim_at(crate.global_position)
	await frames(2)
	player._on_primary()
	check(player._grabbed == crate, "ЛКМ схватил ящик")
	var start := crate.global_position
	await frames(60)
	var hold := player.get_hold_position()
	check(crate.global_position.distance_to(hold) < 0.9, "ящик висит у точки удержания (%.2f м)" % crate.global_position.distance_to(hold))
	start = crate.global_position
	player.get_node("Head").rotation.x = 0.0
	await frames(30)
	player.release_grab(true)
	await frames(90)
	check(crate.global_position.distance_to(start) > 2.0, "брошенный ящик улетел на %.1f м" % crate.global_position.distance_to(start))
	check(crate.holders.is_empty(), "после броска у ящика нет держателей")

	# Инвентарь: фонарь со стола
	var flashlight: PickupItem = main.get_node("Items/Flashlight")
	player.global_position = Vector3(-8.1, 0.05, -0.8)
	await frames(10)
	aim_at(flashlight.global_position)
	await frames(2)
	player._try_pickup()
	await frames(2)
	check(not is_instance_valid(flashlight), "фонарь пропал со стола")
	check(player.inventory.get_selected().get("name") == "Фонарь", "фонарь в выбранном слоте")
	var held := player._get_held_item()
	check(held != null and held.display_name == "Фонарь", "фонарь в руке")
	held.use(player)
	check(held.get_node("SpotLight3D").visible, "ЛКМ включил фонарь")

	# Лейка во второй слот, переключение слотов
	var can: PickupItem = main.get_node("Items/WateringCan")
	aim_at(can.global_position)
	await frames(2)
	player._try_pickup()
	await frames(2)
	check(str(player.inventory.slots[1].get("name")).begins_with("Лейка"), "лейка во втором слоте")
	player.inventory.select(0)
	await frames(2)
	check(player._get_held_item().display_name == "Фонарь", "переключение на слот 1")

	# Выбрасывание
	var before := main.get_node("Items").get_child_count()
	player._drop_selected()
	await frames(60)
	check(main.get_node("Items").get_child_count() == before + 1, "фонарь выброшен в мир")
	check(player.inventory.slots[0].is_empty(), "слот 1 освободился")

	# Тяжёлый тюк замедляет
	var hay: Grabbable = main.get_node("Items/HayBale")
	hay.start_grab(player)
	check(hay.get_carry_factor() < 0.6, "тюк сена тяжёлый для одного (%.2f)" % hay.get_carry_factor())
	hay.holder_count = 2
	check(hay.get_carry_factor() > 0.6, "вдвоём легче (%.2f)" % hay.get_carry_factor())
	hay.stop_grab(player)


	# Ферма: лопата со стола
	var shovel: Node3D = main.get_node("Items/Shovel")
	player.global_position = Vector3(-9.7, 0.05, -0.8)
	await frames(10)
	aim_at(shovel.global_position)
	await frames(2)
	player._try_pickup()
	await frames(3)
	check(player.inventory.get_selected().get("name") == "Лопата", "лопата в руке")

	var plot: Plot = main.get_node("Plots/Plot1")
	var plot_top := plot.global_position + Vector3(0, 0.25, 0)
	player.global_position = plot.global_position + Vector3(0, 0.05, 2.3)
	await frames(10)
	aim_at(plot_top)
	await frames(2)
	check(player._get_target() == plot, "прицел на грядке")
	player._on_primary()
	await frames(3)
	check(plot.state == Plot.State.TILLED, "лопатой грядка вскопана")

	# Пакет семян со стола
	var bag: Node3D = main.get_node("Items/SeedBag")
	player.global_position = Vector3(-9.9, 0.05, -1.0)
	await frames(10)
	aim_at(bag.global_position)
	await frames(2)
	player._try_pickup()
	await frames(3)
	check(str(player.inventory.get_selected().get("name")).begins_with("Семена моркови ×5"), "пакет семян со стола")

	player.global_position = plot.global_position + Vector3(0, 0.05, 2.3)
	await frames(10)
	aim_at(plot_top)
	await frames(2)
	player._on_primary()
	await frames(3)
	check(plot.state == Plot.State.PLANTED and plot.crop == "carrot", "морковь посажена")
	check(player.inventory.get_selected().get("state", {}).get("count") == 4, "в пакете осталось 4 семени")

	# Полив
	player.inventory.select(1)
	await frames(3)
	player._on_primary()
	await frames(3)
	check(plot.moisture > 0.9, "грядка полита")
	check(player.inventory.get_selected().get("name") == "Лейка 4/5", "в лейке 4 полива")
	var before_growth := plot.growth
	await frames(60)
	check(plot.growth > before_growth, "политая морковь растёт")

	# Урожай
	plot.growth = 1.0
	await frames(3)
	var count := main.get_node("Items").get_child_count()
	player._try_pickup()
	await frames(60)
	check(plot.state == Plot.State.UNTILLED, "после сбора грядку снова надо вскопать")
	check(main.get_node("Items").get_child_count() == count + 2, "выпало 2 моркови")

	# Бочка: наполнить лейку
	var barrel: Node3D = main.get_node("WaterBarrel")
	player.global_position = barrel.global_position + Vector3(0, 0.05, 1.5)
	await frames(10)
	aim_at(barrel.global_position + Vector3(0, 0.6, 0))
	await frames(2)
	player._on_primary()
	await frames(3)
	check(player.inventory.get_selected().get("name") == "Лейка 5/5", "лейка наполнена у бочки")

	var wheelbarrow: Node3D = main.get_node("Items/Wheelbarrow")
	check(wheelbarrow.global_position.y > -0.3, "тачка стоит на земле")

	# --- Ночь ---
	var day_night: DayNight = main.get_node("DayNight")
	check(day_night.running and not day_night.is_night(), "игра идёт, сейчас день")
	day_night.cycle_time = DayNight.DAY_LENGTH - 0.5
	await frames(60)
	check(day_night.is_night(), "наступила ночь")
	check(main.get_node("Moon").light_energy > 0.2 and not main.get_node("Sun").visible, "ночью светит луна, солнца нет")
	var director: NightDirector = main.get_node("NightDirector")
	check(director._queue.size() == 2, "в первую ночь выйдут 2 Грядочника")
	# Случайные существа тесту мешают — выпускаем своих
	director._queue.clear()

	# Кража спелой моркови
	var target: Plot = main.get_node("Plots/Plot2")
	target.state = Plot.State.PLANTED
	target.crop = "carrot"
	target.growth = 1.0
	var thief := director.spawn_gryadochnik(target.global_position + Vector3(4.0, 0.3, 0.0))
	check(await wait_for(func(): return target.state == Plot.State.TILLED, 600), "Грядочник съел морковь")
	check(is_instance_valid(thief) and thief.carrying != "", "и несёт её в лес")

	# Три удара лопатой
	player.inventory.select(0)
	await frames(3)
	var items_before := main.get_node("Items").get_child_count()
	for i in 3:
		if not is_instance_valid(thief):
			break
		player.global_position = Vector3(thief.global_position.x, 0.05, thief.global_position.z + 1.2)
		aim_at(thief.global_position + Vector3(0, 0.4, 0))
		await frames(1)
		player._on_primary()
		await frames(5)
	check(not is_instance_valid(thief), "после трёх ударов лопатой Грядочник повержен")
	check(main.get_node("Items").get_child_count() == items_before + 1, "он выронил украденную морковь")

	# Свет фонаря
	var shy := director.spawn_gryadochnik(Vector3(3.0, 0.3, 21.0))
	player.global_position = Vector3(3.0, 0.05, 13.0)
	player.held_scene = Player.FLASHLIGHT_SCENE
	player.held_active = true
	for i in 30:
		aim_at(shy.global_position + Vector3(0, 0.4, 0))
		await physics_frame
	check(shy.state == Creature.State.SCARED, "в луче фонаря Грядочник убегает")
	player._on_inventory_changed()
	shy.queue_free()

	# Забор: существо снаружи, грядка внутри
	target.state = Plot.State.PLANTED
	target.crop = "carrot"
	target.growth = 0.5
	var chewer := director.spawn_gryadochnik(Vector3(0.0, 0.3, 29.0))
	var damaged := func():
		for segment: FenceSegment in get_nodes_in_group("fence"):
			if segment.hp < FenceSegment.MAX_HP:
				return segment
		return null
	check(await wait_for(func(): return damaged.call() != null, 600), "Грядочник грызёт забор")
	var segment: FenceSegment = damaged.call()
	check(await wait_for(func(): return segment.is_broken(), 600), "и прогрызает пролёт")
	check(await wait_for(func(): return is_instance_valid(chewer) and chewer.global_position.z < 23.0, 300), "и пролезает внутрь")
	segment.interact(player, {"tool": "hammer"})
	check(segment.hp == 1 and segment.collision_layer == FenceSegment.SOLID_LAYER, "молоток подлатал сломанный пролёт, он снова держит")
	if is_instance_valid(chewer):
		chewer.queue_free()

	# Рассвет
	day_night.cycle_time = DayNight.CYCLE - 0.5
	await frames(60)
	check(not day_night.is_night() and day_night.day == 2, "рассвело, день 2")

	# --- Ступеньки: на крыльцо дома без прыжка ---
	# Нажатия клавиш имитируем через Input, мышь считаем захваченной
	player.test_controls = true
	player.global_position = Vector3(-12.0, 0.05, -4.8)
	player.rotation.y = 0.0
	player.get_node("Head").rotation.x = 0.0
	await frames(10)
	Input.action_press("move_forward")
	var on_porch := await wait_for(func(): return player.global_position.y > 0.15 and player.global_position.z < -7.0, 120)
	Input.action_release("move_forward")
	check(on_porch, "игрок сам зашёл на крыльцо (y=%.2f)" % player.global_position.y)

	# --- Пикап ---
	var economy: Economy = main.get_node("Economy")
	var truck: Truck = main.get_node("Truck")
	player.global_position = truck.global_position + truck.global_basis.x * 2.2 + Vector3(0, -0.05, 0)
	await frames(10)
	aim_at(truck.global_position + Vector3(0, 1.0, 0))
	await frames(2)
	player._try_pickup()
	await frames(5)
	check(player.seated and player._seat_index == Truck.DRIVER_SEAT, "сел за руль пикапа")
	var truck_start := truck.global_position
	Input.action_press("move_forward")
	await frames(150)
	Input.action_release("move_forward")
	var driven := truck.global_position - truck_start
	check(driven.x > 8.0 and absf(driven.z) < 2.0, "пикап поехал по дороге на восток (%.1f м)" % driven.x)
	check(truck.global_basis.y.dot(Vector3.UP) > 0.95, "пикап не перевернулся")
	check(player.global_position.distance_to(truck.get_seat_position(0)) < 0.3, "водитель едет вместе с пикапом")
	Input.action_press("jump")
	await frames(90)
	Input.action_release("jump")
	check(truck.linear_velocity.length() < 1.0, "пикап остановился на тормозе")
	player._try_pickup()
	await frames(5)
	check(not player.seated and truck.seats[0] == 0, "вышел из пикапа")

	# --- Продажа ---
	var money := economy.money
	var sale_bin: Node3D = main.get_node("Village/Market/SaleBin")
	player.inventory.select(3)
	player.inventory.take_selected()
	player.inventory.add("res://scenes/items/carrot.tscn", "Морковь")
	player.global_position = sale_bin.global_position + Vector3(0, 0.05, 2.0)
	await frames(10)
	aim_at(sale_bin.global_position + Vector3(0, 0.5, 0))
	await frames(2)
	player._try_pickup()
	await frames(5)
	check(economy.money == money + 5, "морковь из руки продана за 5")
	check(player.inventory.get_selected().is_empty(), "проданная морковь пропала из руки")
	var thrown: Node3D = load("res://scenes/items/corn_cob.tscn").instantiate()
	thrown.position = sale_bin.global_position + Vector3(0, 1.5, 0)
	main.get_node("Items").add_child(thrown, true)
	check(await wait_for(func(): return economy.money == money + 13, 120), "брошенный в ящик початок продан за 8")

	# --- Лавка ---
	var counter: ShopCounter = main.get_node("Village/Shop/Counter")
	player.global_position = counter.global_position + Vector3(0, 0.05, 1.6)
	await frames(10)
	aim_at(counter.global_position + Vector3(0, 0.9, 0))
	await frames(2)
	player._try_pickup()
	await frames(5)
	check(player.hud.is_shop_open(), "E у прилавка открывает лавку")
	var items_count := main.get_node("Items").get_child_count()
	money = economy.money
	player.hud.buy_pressed.emit("hammer")
	await frames(5)
	check(economy.money == money - 15, "молоток куплен за 15")
	check(main.get_node("Items").get_child_count() == items_count + 1, "покупка лежит на прилавке")
	economy.money = 5
	player.hud.buy_pressed.emit("flashlight")
	await frames(5)
	check(economy.money == 5 and main.get_node("Items").get_child_count() == items_count + 1, "без денег не купить")
	player.hud.close_shop()

	# --- Классы ---
	var reset_ability := func():
		player._ability_ready_msec = 0
		player._server_ability_ready_msec = 0
	var items_node: Node = main.get_node("Items")

	# Фермер: +1 урожай и подкормка
	player.player_class = "farmer"
	var farm_plot: Plot = main.get_node("Plots/Plot7")
	farm_plot.state = Plot.State.PLANTED
	farm_plot.crop = "carrot"
	farm_plot.growth = 1.0
	player.global_position = farm_plot.global_position + Vector3(0, 0.05, 2.3)
	await frames(5)
	aim_at(farm_plot.global_position + Vector3(0, 0.25, 0))
	await frames(2)
	var before_items := items_node.get_child_count()
	player._try_pickup()
	await frames(10)
	check(items_node.get_child_count() == before_items + 3, "фермер собирает 3 моркови вместо 2")
	farm_plot.state = Plot.State.PLANTED
	farm_plot.crop = "corn"
	farm_plot.growth = 0.5
	reset_ability.call()
	player._try_ability()
	await frames(5)
	check(absf(farm_plot.growth - 0.65) < 0.02, "подкормка фермера: +15%% роста (%.2f)" % farm_plot.growth)
	check(PlayerClasses.weapon_damage("farmer", 2) == 1, "у фермера вилы бьют как лопата")

	# Механик: чинит целиком, остальные — по 1
	var fence_piece: FenceSegment = get_nodes_in_group("fence")[0]
	fence_piece.hp = 1
	player.player_class = ""
	fence_piece.interact(player, {"tool": "hammer"})
	check(fence_piece.hp == 2, "без класса молоток чинит на 1")
	player.player_class = "mechanic"
	fence_piece.interact(player, {"tool": "hammer"})
	check(fence_piece.hp == FenceSegment.MAX_HP, "механик чинит пролёт целиком")
	fence_piece.hp = 0
	player.global_position = fence_piece.get_center() + Vector3(0, 0.05, 0)
	await frames(3)
	reset_ability.call()
	player._try_ability()
	await frames(5)
	check(fence_piece.hp == FenceSegment.MAX_HP, "быстрый ремонт механика")
	check(PlayerClasses.shop_price("mechanic", ShopCatalog.find("hammer")) == 11, "механику молоток за 11 вместо 15")

	# Охотник: бьёт сильнее, выслеживает
	player.player_class = "hunter"
	var prey := director.spawn_gryadochnik(Vector3(0.0, 0.3, 16.0))
	await frames(2)
	reset_ability.call()
	player._try_ability()
	await frames(5)
	check(prey.tracked, "охотник выследил существо")
	player.inventory.select(0)
	await frames(2)
	for i in 2:
		if not is_instance_valid(prey):
			break
		player.global_position = Vector3(prey.global_position.x, 0.05, prey.global_position.z + 1.2)
		aim_at(prey.global_position + Vector3(0, 0.4, 0))
		await frames(1)
		player._on_primary()
		await frames(5)
	check(not is_instance_valid(prey), "охотник валит Грядочника с 2 ударов лопатой")

	# Травник: дым и продажа дороже
	player.player_class = "herbalist"
	var victim := director.spawn_gryadochnik(player.global_position + Vector3(3.0, 0.3, 0.0))
	await frames(2)
	reset_ability.call()
	player._try_ability()
	await frames(5)
	check(victim.state == Creature.State.SCARED, "дым травника пугает существо")
	victim.queue_free()
	player.global_position = sale_bin.global_position + Vector3(0, 0.05, 2.0)
	await frames(5)
	money = economy.money
	var sold: Node3D = load("res://scenes/items/carrot.tscn").instantiate()
	sold.position = sale_bin.global_position + Vector3(0, 1.5, 0)
	items_node.add_child(sold, true)
	check(await wait_for(func(): return economy.money == money + 7, 120), "рядом с травником морковь продана за 7 вместо 5")

	# Скотник: свист и молоко
	player.player_class = "herder"
	var cow: Cow = main.get_node("Animals/Cow1")
	player.global_position = cow.global_position + Vector3(12.0, 0.05, 0.0)
	await frames(3)
	var cow_distance := cow.global_position.distance_to(player.global_position)
	reset_ability.call()
	player._try_ability()
	await frames(150)
	check(cow.global_position.distance_to(player.global_position) < cow_distance - 4.0, "по свисту корова идёт к скотнику")
	player.global_position = cow.global_position + Vector3(0, 0.05, 2.2)
	await frames(3)
	aim_at(cow.global_position + Vector3(0, 0.9, 0))
	await frames(2)
	before_items = items_node.get_child_count()
	player._try_pickup()
	await frames(10)
	check(items_node.get_child_count() == before_items + 2 and not cow.milk_ready, "скотник надоил 2 бутылки")

	# Собака лает на существо у дома
	var dog: Node3D = main.get_node("Animals/Dog")
	var intruder := director.spawn_gryadochnik(dog.global_position + Vector3(6.0, 0.3, 6.0))
	check(await wait_for(func(): return str(player.hud._message.text).begins_with("Собака лает"), 180), "собака лает на существо")
	intruder.queue_free()

	print("ИТОГ: %s" % ("всё прошло" if failures == 0 else "провалов: %d" % failures))
	quit(failures)
