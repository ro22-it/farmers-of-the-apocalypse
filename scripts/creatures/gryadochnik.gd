class_name Gryadochnik
extends Creature

## Грядочник: мелкий вор урожая, похож на картофелину с ножками.
## Идёт к самой спелой грядке, ест и убегает с добычей. Боится света.

const EAT_TIME := 3.0
const CHEW_INTERVAL := 1.5
const EAT_DISTANCE := 0.9
const LIGHT_CHECK_INTERVAL := 0.2
const SCARE_TIME := 4.0
## Кусачие грядки фермера кусают раз в столько секунд
const BITE_INTERVAL := 1.5

## Путь к сцене украденного урожая. Пусто — ничего не несёт.
## Синхронизируется, чтобы все видели добычу на спине.
var carrying := ""

var _target_plot: Plot = null
var _chewing: FenceSegment = null
## Куда вернуться, когда забор прогрызен
var _state_before_chew: int = State.APPROACH
var _light_check := 0.0
var _bite_time := 0.0

@onready var _model: Node3D = $Model
@onready var _loot: Node3D = $Model/Loot


func _physics_process(delta: float) -> void:
	_animate(delta)
	if not multiplayer.is_server():
		return
	_light_check -= delta
	if _light_check <= 0.0:
		_light_check = LIGHT_CHECK_INTERVAL
		_check_light()

	match state:
		State.APPROACH:
			_approach(delta)
		State.CHEW:
			_chew(delta)
		State.EAT:
			_eat(delta)
		State.FLEE:
			_start_chew(_walk_to(_home, flee_speed, delta))
			if _far_from_farm() or global_position.distance_to(_home) < 1.5:
				queue_free()
		State.TRAPPED:
			_update_trapped(delta)
		State.SCARED:
			_start_chew(_walk_away_from(_scare_from, flee_speed, delta))
			_state_time -= delta
			if _state_time <= 0.0:
				state = State.FLEE if carrying != "" else State.APPROACH
			if _far_from_farm() and carrying != "":
				queue_free()


func _approach(delta: float) -> void:
	if _target_plot == null or not is_instance_valid(_target_plot) or _target_plot.state == Plot.State.UNTILLED:
		_target_plot = _pick_plot()
		if _target_plot == null:
			# Поживиться нечем — уходит
			state = State.FLEE
			return
	_start_chew(_walk_to(_target_plot.global_position, speed, delta))
	var flat := _target_plot.global_position - global_position
	flat.y = 0.0
	if state == State.APPROACH and flat.length() < EAT_DISTANCE:
		state = State.EAT
		# Колючие грядки фермера едятся вдвое дольше
		_state_time = EAT_TIME * (2.0 if _target_plot.thorny else 1.0)
		_bite_time = BITE_INTERVAL


func _eat(delta: float) -> void:
	_stand(delta)
	if not is_instance_valid(_target_plot) or _target_plot.state == Plot.State.UNTILLED:
		state = State.APPROACH
		return
	if _target_plot.biting:
		_bite_time -= delta
		if _bite_time <= 0.0:
			_bite_time = BITE_INTERVAL
			if take_hit(1, _target_plot.global_position):
				return
	if state != State.EAT:
		return
	_state_time -= delta
	if _state_time <= 0.0:
		carrying = _target_plot.steal()
		_target_plot = null
		state = State.FLEE


func _chew(delta: float) -> void:
	_stand(delta)
	if not is_instance_valid(_chewing) or _chewing.is_broken():
		_chewing = null
		state = _state_before_chew
		return
	_state_time -= delta
	if _state_time <= 0.0:
		_state_time = CHEW_INTERVAL
		_chewing.damage(1)


func _start_chew(fence: FenceSegment) -> void:
	if fence == null or fence.is_broken():
		return
	_state_before_chew = State.FLEE if state == State.SCARED else state
	_chewing = fence
	state = State.CHEW
	_state_time = CHEW_INTERVAL


## Самая спелая посаженная грядка, а если не посажено ничего — ближайшая вскопанная.
func _pick_plot() -> Plot:
	var best: Plot = null
	var best_score := -INF
	for plot: Plot in get_tree().get_nodes_in_group("plots"):
		if not plot.enabled:
			continue
		var score := -INF
		if plot.state == Plot.State.PLANTED:
			score = 100.0 + plot.growth * 100.0 - global_position.distance_to(plot.global_position)
		elif plot.state == Plot.State.TILLED:
			score = -global_position.distance_to(plot.global_position)
		if score > best_score:
			best_score = score
			best = plot
	return best


func _check_light() -> void:
	var chest := global_position + Vector3(0.0, 0.4, 0.0)
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player.is_shining_at(chest):
			scare(player.global_position, SCARE_TIME)
			return
	# Прочий свет: фонарь на вышке, фары пикапа
	for light in get_tree().get_nodes_in_group("scare_lights"):
		if light.scares(chest):
			scare(light.global_position, SCARE_TIME)
			return


func _state_after_trap() -> int:
	return State.FLEE if carrying != "" else State.APPROACH


func _on_died() -> void:
	if carrying == "":
		return
	var item: Node3D = load(carrying).instantiate()
	item.position = global_position + Vector3(0.0, 0.6, 0.0)
	get_tree().current_scene.get_node("Items").add_child(item, true)


## Анимация по состоянию — одинаково у хоста и клиентов.
func _animate(delta: float) -> void:
	_loot.visible = carrying != ""
	var rate := 14.0 if state == State.FLEE or state == State.SCARED else 9.0
	if _is_moving():
		_anim_time += delta * rate
		_model.position.y = absf(sin(_anim_time)) * 0.08
		_model.rotation.x = 0.0
	elif state == State.CHEW or state == State.EAT:
		_anim_time += delta * 18.0
		_model.position.y = 0.0
		_model.rotation.x = -0.25 + sin(_anim_time) * 0.12
	else:
		_model.position.y = 0.0
		_model.rotation.x = 0.0
