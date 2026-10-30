class_name Tutorial
extends Node

## Обучение для новичков: по одной задаче за раз, справа на экране.
## Задача засчитывается, когда её результат виден в мире — неважно, кто из
## команды её сделал. Работает у своего игрока, ничего не шлёт по сети.

const CHECK_INTERVAL := 0.5
const STEPS := [
	["Возьмите лопату со стола у дома: наведите и нажмите E", "has_shovel"],
	["Вскопайте грядку: лопата в руке — ЛКМ по грядке", "plot_tilled"],
	["Возьмите со стола пакет семян (E) и посадите: ЛКМ по вскопанной грядке", "plot_planted"],
	["Полейте: возьмите лейку и нажмите ЛКМ по грядке. Пустую лейку наполняют ЛКМ по бочке", "plot_watered"],
	["Урожай растёт только днём. Пока ждёте, сядьте в пикап у ворот (E). W — газ, V — камера", "seated"],
	["Соберите урожай: E по спелой грядке. F2 — перемотать время", "has_produce"],
	["Продайте урожай в деревне на востоке: бросьте в ящик скупки или нажмите E с урожаем в руке", "sold"],
	["Купите что-нибудь в лавке: семена, фонарь или оружие (E у прилавка)", "bought"],
	["Ночью из леса выходят существа. Фонарь пугает Грядочника, лопата и оружие бьют, забор чинят молотком", "night"],
	["Продержитесь до рассвета! Упавшего товарища поднимают E", "dawn"],
]

var step := 0

var _player: Player
var _check := 0.0
## Сколько было денег, когда началась текущая задача (для «продайте» и «купите»)
var _money_at_step := 0


func _init(player: Player) -> void:
	_player = player
	name = "Tutorial"


func _ready() -> void:
	_money_at_step = _money()
	_show()


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0 or step >= STEPS.size():
		return
	_check = CHECK_INTERVAL
	# Уже сделанное (в том числе товарищами) засчитываем сразу, хоть несколько шагов
	var advanced := false
	while step < STEPS.size() and _done(STEPS[step][1]):
		step += 1
		_money_at_step = _money()
		advanced = true
	if not advanced:
		return
	if step >= STEPS.size():
		_finish()
	else:
		_player.hud.show_message("Готово! Дальше — шаг %d" % (step + 1))
		_show()


func _show() -> void:
	_player.hud.set_tutorial("Обучение %d/%d" % [step + 1, STEPS.size()], STEPS[step][0])


func _finish() -> void:
	_player.hud.set_tutorial("", "")
	_player.hud.show_message("Обучение пройдено! Q — способность класса, K — навыки, доска улучшений у дома")
	var network := _player.get_node_or_null("/root/Network")
	if network:
		network.tutorial_enabled = false
		network.save_settings()


func _done(check: String) -> bool:
	match check:
		"has_shovel":
			return _has_item(func(path): return path.ends_with("shovel.tscn"))
		"plot_tilled":
			return _any_plot(func(plot: Plot): return plot.state != Plot.State.UNTILLED)
		"plot_planted":
			return _any_plot(func(plot: Plot): return plot.state == Plot.State.PLANTED)
		"plot_watered":
			return _any_plot(func(plot: Plot): return plot.moisture > 0.0)
		"seated":
			return _player.seated
		"has_produce":
			return _has_item(func(path): return Economy.price_of(path) > 0) or _money() > _money_at_step
		"sold":
			return _money() > _money_at_step
		"bought":
			return _money() < _money_at_step
		"night":
			return _day_night() != null and _day_night().is_night()
		"dawn":
			return _day_night() != null and not _day_night().is_night() and _day_night().day >= 2
	return false


func _has_item(test: Callable) -> bool:
	for slot: Dictionary in _player.inventory.slots:
		if not slot.is_empty() and test.call(slot.path):
			return true
	return false


func _any_plot(test: Callable) -> bool:
	for plot: Plot in _player.get_tree().get_nodes_in_group("plots"):
		if plot.enabled and test.call(plot):
			return true
	return false


func _money() -> int:
	var economy := _player.get_tree().get_first_node_in_group("economy") as Economy
	return economy.money if economy else 0


func _day_night() -> DayNight:
	return _player.get_tree().get_first_node_in_group("day_night") as DayNight
