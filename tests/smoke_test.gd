extends SceneTree

var main: Node
var player: Player

## Одиночная игра: хост без друзей. Проверяет хватку, бросок, инвентарь, фонарь
## цикл грядки, ночь (Грядочник, фонарь, забор), пикап, продажу, лавку, ступеньки
## классы, опыт, навыки, улучшения фермы и бой (8а). Общие проверки — без класса, потом классы.
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
	await frames(40)
	var tutorial := player.get_node_or_null("Tutorial") as Tutorial
	check(tutorial != null and tutorial.step == 4, "обучение засчитало лопату, вскопку, посадку и полив (шаг %d)" % (tutorial.step if tutorial else -1))
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
	var corpse: Corpse = null
	var carrots := 0
	for node in main.get_node("Items").get_children():
		if node is Corpse:
			corpse = node
		elif node.scene_file_path.ends_with("carrot.tscn"):
			carrots += 1
	check(main.get_node("Items").get_child_count() == items_before + 2 and carrots > 0, "он выронил украденную морковь")
	check(corpse != null, "от Грядочника осталось тело")
	if corpse:
		await frames(20)
		check(corpse.global_position.distance_to(player.global_position) > 1.0, "тело отлетело от удара")
		corpse.lifetime = 0.1
		await frames(20)
		check(not is_instance_valid(corpse), "тело исчезает по таймеру")

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
	var speed_before := truck.linear_velocity.dot(truck.global_basis.z)
	Input.action_press("move_back")
	await frames(40)
	Input.action_release("move_back")
	var speed_after := truck.linear_velocity.dot(truck.global_basis.z)
	check(speed_before > 8.0 and speed_after < speed_before * 0.5, "S тормозит пикап (%.1f → %.1f м/с)" % [speed_before, speed_after])
	await frames(60)
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
	check(player.hud.is_panel_open(), "E у прилавка открывает лавку")
	var items_count := main.get_node("Items").get_child_count()
	money = economy.money
	player.hud.panel_action.emit("shop", "hammer")
	await frames(5)
	check(economy.money == money - 15, "молоток куплен за 15")
	check(main.get_node("Items").get_child_count() == items_count + 1, "покупка лежит на прилавке")
	economy.money = 5
	player.hud.panel_action.emit("shop", "flashlight")
	await frames(5)
	check(economy.money == 5 and main.get_node("Items").get_child_count() == items_count + 1, "без денег не купить")
	player.hud.close_panel()

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
	check(PlayerClasses.weapon_damage(player, 2) == 1, "у фермера вилы бьют как лопата")

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
	main.get_node("Animals/Cow2").global_position = Vector3(20.0, 0.05, 20.0)
	player.global_position = cow.global_position + Vector3(-12.0, 0.05, 0.0)
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
	var milked := player._get_target() as Cow
	player._try_pickup()
	await frames(10)
	check(milked != null and items_node.get_child_count() == before_items + 2 and not milked.milk_ready, "скотник надоил 2 бутылки")

	# Собака лает на существо у дома
	var dog: Node3D = main.get_node("Animals/Dog")
	var intruder := director.spawn_gryadochnik(dog.global_position + Vector3(6.0, 0.3, 6.0))
	check(await wait_for(func(): return str(player.hud._message.text).begins_with("Собака лает"), 180), "собака лает на существо")
	intruder.queue_free()

	# --- Опыт и навыки ---
	player.player_class = "farmer"
	player.xp = 0
	player.skills = PackedStringArray()
	var xp_plot: Plot = main.get_node("Plots/Plot10")
	xp_plot.reset()
	xp_plot.state = Plot.State.TILLED
	xp_plot.interact(player, {"tool": "seeds", "crop": "carrot"})
	check(player.xp == PlayerClasses.XP_PLANT, "фермер получил опыт за посадку")
	xp_plot.growth = 1.0
	xp_plot.interact(player, {"tool": "hand"})
	check(player.xp == PlayerClasses.XP_PLANT + PlayerClasses.XP_HARVEST, "и за сбор урожая")
	player.add_xp(40 - player.xp)
	check(PlayerClasses.level_for(player.xp) == 2 and PlayerClasses.free_points(player.xp, player.skills) == 1, "40 опыта — уровень 2 и очко навыка")
	player._request_learn.rpc_id(1, "farmer_a2")
	await frames(2)
	check(player.skills.is_empty(), "второй навык ветки без первого не взять")
	player._request_learn.rpc_id(1, "farmer_b1")
	await frames(2)
	check("farmer_b1" in player.skills, "взят навык «Колючие грядки»")
	player._request_learn.rpc_id(1, "farmer_b2")
	await frames(2)
	check(not "farmer_b2" in player.skills, "без свободного очка навык не взять")
	player._open_skills()
	check(player.hud.panel_kind() == "skill", "K открывает окно навыков")
	player.hud.close_panel()

	# Боевые растения: колючие и кусачие грядки
	player.skills = PackedStringArray(["farmer_b1", "farmer_b2"])
	get_root().get_tree().call_group("plots", "reset")
	xp_plot.reset()
	xp_plot.state = Plot.State.TILLED
	xp_plot.interact(player, {"tool": "seeds", "crop": "carrot"})
	check(xp_plot.thorny and xp_plot.biting, "грядка фермера колючая и кусачая")
	var biter_victim := director.spawn_gryadochnik(xp_plot.global_position + Vector3(1.5, 0.3, 0.0))
	var victim_ref: WeakRef = weakref(biter_victim)
	biter_victim = null
	check(await wait_for(func(): return victim_ref.get_ref() == null or victim_ref.get_ref().hp < victim_ref.get_ref().max_hp, 400), "кусачая грядка кусает Грядочника")
	if victim_ref.get_ref():
		victim_ref.get_ref().queue_free()
	player.skills = PackedStringArray()

	# Механик: двойные жерди
	player.player_class = "mechanic"
	player.skills = PackedStringArray(["mechanic_a1", "mechanic_a2"])
	var strong_piece: FenceSegment = get_nodes_in_group("fence")[5]
	strong_piece.hp = 1
	strong_piece.interact(player, {"tool": "hammer"})
	check(strong_piece.max_hp == FenceSegment.MAX_HP + 2 and strong_piece.hp == strong_piece.max_hp, "пролёт механика с навыком прочнее на 2")
	check(PlayerClasses.ability_cooldown(player) == 30.0, "«Расторопность»: перезарядка 30 с вместо 60")
	player.skills = PackedStringArray()

	# --- Общие улучшения ---
	var upgrades: FarmUpgrades = main.get_node("FarmUpgrades")
	var extra_plot: Plot = main.get_node("UpgradeBeds/Plot19")
	check(not extra_plot.enabled and not extra_plot.visible, "новые грядки до покупки спрятаны")
	economy.money = 1000
	for id in ["pump", "cow", "beds", "tower", "motor", "stone"]:
		player._request_upgrade.rpc_id(1, id)
		await frames(2)
	check(upgrades.bought.size() == 6 and economy.money == 1000 - 570, "куплены все 6 улучшений за 570")
	check(extra_plot.enabled and extra_plot.visible, "новые грядки появились")
	check(main.get_node("UpgradeCow/Cow3").enabled, "третья корова появилась")
	check(main.get_node("Truck").motor_upgraded, "у пикапа новый мотор")
	var stone_piece: FenceSegment = get_nodes_in_group("fence")[0]
	check(stone_piece.stone and stone_piece.max_hp == FenceSegment.STONE_HP and stone_piece.hp == FenceSegment.STONE_HP, "забор стал каменным")
	player._request_upgrade.rpc_id(1, "beds")
	await frames(2)
	check(economy.money == 430, "второй раз то же улучшение не купить")
	var tower_light: Node3D = main.get_node("UpgradeTower/Light")
	day_night.cycle_time = DayNight.DAY_LENGTH + 10.0
	await frames(3)
	check(tower_light.scares(tower_light.global_position + Vector3(5, -5, 0)), "ночью фонарь вышки отпугивает рядом")
	check(not tower_light.scares(tower_light.global_position + Vector3(15, -5, 0)), "а дальше 10 м — нет")

	# По лестнице на вышку
	player.global_position = Vector3(-18.0, 0.05, 21.5)
	player.rotation.y = 0.0
	player.get_node("Head").rotation.x = 0.0
	await frames(5)
	Input.action_press("move_forward")
	var climbed := await wait_for(func(): return player.global_position.y > 3.8, 240)
	Input.action_release("move_forward")
	check(climbed, "игрок поднялся на вышку по лестнице (y=%.1f)" % player.global_position.y)

	# --- 8а: бой ---
	player.player_class = ""
	player.skills = PackedStringArray()
	director.reset()
	day_night.cycle_time = 100.0
	await frames(3)
	player.global_position = Vector3(-4.5, 0.05, 16.0)
	player.rotation.y = 0.0
	player.get_node("Head").rotation.x = 0.0
	await frames(5)
	player.take_damage(40.0, player.global_position + Vector3(1, 0, 0))
	check(is_equal_approx(player.health, 60.0), "урон 40 — осталось 60 здоровья")
	player.take_damage(100.0, player.global_position + Vector3(1, 0, 0))
	check(player.downed and player.health == 0.0, "при 0 — без сознания")
	await frames(120)
	var lying_at := player.global_position
	Input.action_press("move_forward")
	await frames(30)
	Input.action_release("move_forward")
	check(Vector2(player.global_position.x - lying_at.x, player.global_position.z - lying_at.z).length() < 0.1, "без сознания не двигается")
	day_night.cycle_time = DayNight.CYCLE - 0.3
	await frames(30)
	check(not player.downed and is_equal_approx(player.health, Player.REVIVE_HEALTH), "на рассвете встал с 30 здоровья")
	player._last_hit_msec = -100000
	await frames(60)
	check(player.health > Player.REVIVE_HEALTH, "здоровье само восстанавливается")
	day_night.cycle_time = 100.0
	await frames(2)

	# Двустволка вблизи
	player.inventory.select(3)
	player.inventory.take_selected()
	player.inventory.add("res://scenes/items/shotgun.tscn", "Двустволка", {"loaded": 2})
	await frames(3)
	var shotgun := player._get_held_item() as Gun
	check(shotgun != null and shotgun.weapon == "shotgun", "двустволка в руке")
	player.global_position = Vector3(-4.5, 0.05, 16.0)
	await frames(5)
	var close_target := director.spawn_gryadochnik(player.global_position + Vector3(0, 0.3, -5.0))
	close_target.trap(10.0)
	await frames(2)
	aim_at(close_target.global_position + Vector3(0, 0.4, 0))
	var target_ref: WeakRef = weakref(close_target)
	close_target = null
	player._on_primary()
	await frames(5)
	check(target_ref.get_ref() == null, "выстрел из двустволки свалил Грядочника")
	check(shotgun.loaded == 1, "в стволе остался 1 патрон")
	player._next_shot_msec = 0
	player._server_next_shot_msec = 0
	var crate_target: Node3D = main.get_node("Items/Pumpkin3")
	player.global_position = crate_target.global_position + Vector3(0, -0.3, 3.0)
	await frames(5)
	var crate_before := crate_target.global_position
	aim_at(crate_target.global_position)
	player._on_primary()
	await frames(30)
	check(crate_target.global_position.distance_to(crate_before) > 0.5, "выстрел отбрасывает тыкву (%.1f м)" % crate_target.global_position.distance_to(crate_before))
	check(shotgun.loaded == 0, "двустволка пуста")
	player._next_shot_msec = 0
	player._on_primary()
	check(shotgun.loaded == 0, "без патронов не стреляет")
	player.ammo = 6
	player._try_reload()
	await frames(150)
	check(shotgun.loaded == 2 and player.ammo == 4, "перезарядка: 2 в стволах, 4 в запасе")

	# Коробка патронов — сразу в запас
	var box: Node3D = load("res://scenes/items/ammo_box.tscn").instantiate()
	box.position = player.global_position + Vector3(0, 0.3, -1.5)
	items_node.add_child(box, true)
	await frames(30)
	aim_at(box.global_position)
	await frames(2)
	player._try_pickup()
	await frames(5)
	check(player.ammo == 10, "коробка патронов добавила 6 в запас")

	# Винтовка на 20 м
	player.inventory.take_selected()
	player.inventory.add("res://scenes/items/rifle.tscn", "Винтовка", {"loaded": 5})
	await frames(3)
	player.global_position = Vector3(-4.5, 0.05, 16.0)
	await frames(3)
	var far_target := director.spawn_gryadochnik(player.global_position + Vector3(0, 0.3, -20.0))
	far_target.trap(10.0)
	await frames(2)
	aim_at(far_target.global_position + Vector3(0, 0.4, 0))
	var far_ref: WeakRef = weakref(far_target)
	far_target = null
	player._server_next_shot_msec = 0
	player._on_primary()
	await frames(5)
	check(far_ref.get_ref() == null, "винтовка достаёт на 20 м")

	# Капкан на пути Тарана
	player.inventory.take_selected()
	player.inventory.add("res://scenes/items/trap.tscn", "Капкан")
	await frames(3)
	player.global_position = Vector3(-4.0, 0.05, 16.0)
	player.rotation.y = 0.0
	player.get_node("Head").rotation.x = deg_to_rad(-45)
	await frames(5)
	player._on_primary()
	await frames(5)
	var placed: Trap = null
	for node in items_node.get_children():
		if node is Trap:
			placed = node
	check(placed != null and player.inventory.get_selected().is_empty(), "капкан поставлен на землю")
	var taran := director.spawn_taran(Vector3(placed.global_position.x, 0.3, placed.global_position.z - 8.0))
	check(await wait_for(func(): return taran.state == Creature.State.TRAPPED, 300), "Таран бросился и попал в капкан")
	player.inventory.add("res://scenes/items/rifle.tscn", "Винтовка", {"loaded": 5})
	await frames(3)
	var taran_ref: WeakRef = weakref(taran)
	taran = null
	for i in 3:
		if taran_ref.get_ref() == null:
			break
		aim_at(taran_ref.get_ref().global_position + Vector3(0, 1.3, 0))
		player._server_next_shot_msec = 0
		player._next_shot_msec = 0
		player._on_primary()
		await frames(5)
	check(taran_ref.get_ref() == null, "в капкане Таран падает с двух выстрелов винтовки")

	# Таран бьёт игрока
	player.global_position = Vector3(5.0, 0.05, 16.0)
	player._last_hit_msec = Time.get_ticks_msec()
	await frames(3)
	var health_before := player.health
	var charger := director.spawn_taran(player.global_position + Vector3(0, 0.3, -9.0))
	check(await wait_for(func(): return player.health <= health_before - 25.0 or player.downed, 300), "разбег Тарана — минус 30 здоровья")
	charger.queue_free()

	# Таран ломает забор с одного удара
	player.global_position = Vector3(-15.0, 0.05, -15.0)
	await frames(3)
	var breaker := director.spawn_taran(Vector3(0.0, 0.3, 30.0))
	breaker._goal = Vector3(0.0, 0.0, 10.0)
	var any_broken := func():
		for piece: FenceSegment in get_nodes_in_group("fence"):
			if piece.is_broken():
				return true
		return false
	check(await wait_for(any_broken, 600), "Таран проломил забор")
	breaker.queue_free()
	player.revive(Player.MAX_HEALTH)

	# --- Поворот предмета: поднять упавшее пугало ---
	director.reset()
	await wait_for(func(): return player._tumble == null, 400)
	var scarecrow_body: RigidBody3D = main.get_node("Items/Scarecrow")
	player.inventory.select(3)
	player.inventory.take_selected()
	await frames(2)
	player.global_position = Vector3(-8.0, 0.05, 18.6)
	scarecrow_body.global_transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)), Vector3(-8.0, 0.3, 15.0))
	scarecrow_body.linear_velocity = Vector3.ZERO
	scarecrow_body.angular_velocity = Vector3.ZERO
	await frames(30)
	check(scarecrow_body.global_basis.y.dot(Vector3.UP) < 0.3, "пугало лежит")
	aim_at(scarecrow_body.global_position + scarecrow_body.global_basis.y * 1.2)
	await frames(2)
	player._on_primary()
	await frames(10)
	check(player._grabbed == scarecrow_body, "лежащее пугало схвачено")
	player._request_upright.rpc_id(1)
	await frames(60)
	check(scarecrow_body.global_basis.y.dot(Vector3.UP) > 0.9, "R — пугало повёрнуто ровно")
	var yaw_before := scarecrow_body.global_rotation.y
	player._request_rotate_grab.rpc_id(1, 40.0)
	await frames(40)
	check(absf(angle_difference(yaw_before, scarecrow_body.global_rotation.y)) > deg_to_rad(25.0), "колесо вертит предмет в руках")
	player.release_grab()
	await frames(90)
	check(scarecrow_body.global_basis.y.dot(Vector3.UP) > 0.85, "отпущенное пугало стоит на ногах")

	# --- Кувырок ---
	player.revive(Player.MAX_HEALTH)
	player.global_position = Vector3(-4.0, 0.05, 20.0)
	await frames(5)
	player.take_damage(30.0, player.global_position + Vector3(0, 0, -1), true)
	await frames(5)
	check(player._tumble != null and player._collision.disabled, "от сильного удара игрок кувыркается")
	await frames(20)
	check(player._body.global_basis.y.dot(Vector3.UP) < 0.95 or player.global_position.y > 0.4, "тело летит и вертится")
	check(await wait_for(func(): return player._tumble == null, 400), "кувырок закончился")
	await frames(10)
	check(not player._collision.disabled and player.is_on_floor() and player.global_position.y < 0.6, "игрок снова стоит на земле (y=%.2f)" % player.global_position.y)

	# Пикап сбивает игрока
	var hit_truck: Truck = main.get_node("Truck")
	player.global_position = hit_truck.global_position + hit_truck.global_basis.z * 2.3 + Vector3(0, -0.1, 0)
	await frames(3)
	var hp_before := player.health
	hit_truck._run_over_players(12.0)
	await frames(5)
	check(player._tumble != null and player.health < hp_before, "пикап сбил игрока — урон и кувырок")
	await wait_for(func(): return player._tumble == null, 400)

	# Удар товарища лопатой: «шутка»
	var buddy: Player = main._create_player({"id": 77, "name": "Друг", "class": "", "position": player.global_position + Vector3(1.2, 0, 0)})
	main.get_node("Players").add_child(buddy)
	await frames(5)
	player.inventory.add("res://scenes/items/shovel.tscn", "Лопата")
	await frames(3)
	aim_at(buddy.global_position + Vector3(0, 1.0, 0))
	await frames(2)
	player._on_primary()
	await frames(3)
	check(is_equal_approx(buddy.health, Player.MAX_HEALTH - Player.PRANK_DAMAGE), "удар лопатой по товарищу: −5 здоровья")
	buddy.queue_free()

	# Пинок пустой рукой: отбрасывает, но не ранит
	player.inventory.select(0)
	player.inventory.take_selected()
	director.reset()
	await frames(3)
	player.global_position = Vector3(-4.0, 0.05, 20.0)
	await frames(3)
	var kicked := director.spawn_gryadochnik(player.global_position + Vector3(0, 0.3, -1.4))
	kicked.trap(0.0)
	await frames(2)
	var kick_from := kicked.global_position
	aim_at(kicked.global_position + Vector3(0, 0.5, 0))
	player._on_primary()
	await frames(15)
	check(kicked.hp == kicked.max_hp and kicked.global_position.distance_to(kick_from) > 0.5, "пинок отбрасывает монстра без урона")
	kicked.queue_free()

	# --- Настройки ---
	var settings: Node = root.get_node("Settings")
	settings.fov = 95.0
	settings.effects_volume = 0.5
	settings.apply()
	await frames(60)
	check(absf(player.get_node("Head/Camera3D").fov - 95.0) < 1.0, "поле зрения из настроек")
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Effects")) - linear_to_db(0.5)) < 0.1, "громкость эффектов из настроек")
	settings.fov = 80.0
	settings.effects_volume = 1.0
	settings.apply()

	# --- Сохранение и загрузка ---
	var saver: SaveSystem = main.get_node("SaveSystem")
	check(saver.save_path == SaveSystem.TEST_SAVE, "тест пишет в отдельный файл, а не в сохранение игрока")
	var save_plot: Plot = main.get_node("Plots/Plot5")
	save_plot.reset()
	save_plot.state = Plot.State.PLANTED
	save_plot.crop = "corn"
	save_plot.growth = 0.7
	economy.money = 321
	day_night.day = 4
	player.xp = 150
	player.skills = PackedStringArray(["herder_a1"])
	player.inventory.select(1)
	player.inventory.take_selected()
	player.inventory.add("res://scenes/items/hammer.tscn", "Молоток")
	await frames(5)
	# Тела монстров не сохраняются — они всё равно исчезают через полторы минуты
	var count_items := func():
		var n := 0
		for node in items_node.get_children():
			if not node is Corpse and not node.is_queued_for_deletion():
				n += 1
		return n
	var saved_items: int = count_items.call()
	check(saver.save(), "игра сохранена")
	# Портим мир и прогресс
	main._reset_world(true)
	player.xp = 0
	player.skills = PackedStringArray()
	for i in Inventory.SIZE:
		player.inventory.slots[i] = {}
	player.inventory.changed.emit()
	await frames(5)
	check(economy.money == Economy.START_MONEY and save_plot.state == Plot.State.UNTILLED, "мир сброшен")
	check(saver.read(), "сохранение прочитано")
	main._reset_world(false)
	saver.apply_world()
	await frames(5)
	check(economy.money == 321 and day_night.day == 4, "вернулись деньги и день")
	check(save_plot.state == Plot.State.PLANTED and save_plot.crop == "corn" and is_equal_approx(save_plot.growth, 0.7), "вернулась кукуруза на грядке")
	check(count_items.call() == saved_items, "вернулись предметы (%d из %d)" % [count_items.call(), saved_items])
	saver.apply_profile(player, saver.profile_for(player.player_name))
	await frames(60)
	check(player.xp == 150 and "herder_a1" in player.skills, "вернулись опыт и навыки игрока")
	var has_hammer := false
	for slot: Dictionary in player.inventory.slots:
		has_hammer = has_hammer or str(slot.get("path", "")).ends_with("hammer.tscn")
	check(has_hammer, "вернулся инвентарь игрока")
	saver.delete_save()
	check(not FileAccess.file_exists(SaveSystem.TEST_SAVE), "тестовое сохранение удалено")

	# --- Дом: дверь открывается, внутрь можно зайти ---
	var door: Node3D = main.get_node("Farm/House/DoorHinge/Door")
	player.global_position = Vector3(-12.0, 0.3, -6.6)
	player.velocity = Vector3.ZERO
	await frames(5)
	aim_at(door.global_position)
	await frames(2)
	player._try_pickup()
	await frames(40)
	check(door.is_open, "дверь дома открылась по E")
	aim_at(Vector3(-12.0, 1.4, -13.0))
	player.get_node("Head").rotation.x = 0.0
	Input.action_press("move_forward")
	await frames(90)
	Input.action_release("move_forward")
	check(player.global_position.z < -9.5, "игрок зашёл в дом (z=%.1f)" % player.global_position.z)

	print("ИТОГ: %s" % ("всё прошло" if failures == 0 else "провалов: %d" % failures))
	quit(failures)
