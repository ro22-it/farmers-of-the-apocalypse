extends SceneTree

var main: Node
var player: Player

## Одиночная игра: хост без друзей. Проверяет хватку, бросок, инвентарь и фонарь.
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


func aim_at(target: Vector3) -> void:
	var cam: Camera3D = player.get_node("Head/Camera3D")
	var dir := target - cam.global_position
	player.rotation.y = atan2(-dir.x, -dir.z)
	player.get_node("Head").rotation.x = atan2(dir.y, Vector2(dir.x, dir.z).length())


func _run() -> void:
	await frames(5)
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
	check(player.inventory.slots[1].get("name") == "Лейка", "лейка во втором слоте")
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

	print("ИТОГ: %s" % ("всё прошло" if failures == 0 else "провалов: %d" % failures))
	quit(failures)
