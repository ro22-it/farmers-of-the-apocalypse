class_name Kukuruznik
extends Creature

## Кукурузник: длинный зелёный демон из кукурузного поля. Подкрадывается
## к игроку, хватает и тащит в лес. Отбить пленника можно любым ударом.
## Дотащил до опушки — пленник получает сильный урон и остаётся в лесу.

const GRAB_RADIUS := 1.3
const DRAG_SPEED := 2.4
## Урон, если дотащил до леса
const DRAG_DAMAGE := 45.0
## Сколько секунд тащит, прежде чем бросить в лесу
const DRAG_TIME := 14.0
## После того как отбили, столько секунд не хватает снова
const REGRAB_COOLDOWN := 6.0
## Тащит к опушке: на столько метров от центра фермы
const FOREST_EDGE := 40.0
const FARM_CENTER := Vector3(0.0, 0.0, 6.0)

## Тащит ли кого-то сейчас — для анимации у всех
var dragging := false

var _victim: Player = null
var _cooldown := 0.0
var _drag_to := Vector3.ZERO

@onready var _look: CreepyModel = $Model/Look


func _physics_process(delta: float) -> void:
	_animate(delta)
	if not multiplayer.is_server():
		return
	_cooldown -= delta
	if dragging and (not is_instance_valid(_victim) or _victim.downed):
		_release()
	match state:
		State.TRAPPED:
			_update_trapped(delta)
		State.SCARED:
			_walk_away_from(_scare_from, flee_speed, delta)
			_state_time -= delta
			if _state_time <= 0.0:
				state = State.APPROACH
		State.FLEE:
			_walk_to(_home, flee_speed, delta)
			if _far_from_farm() or global_position.distance_to(_home) < 1.5:
				queue_free()
		_:
			if dragging:
				_drag(delta)
			else:
				_stalk(delta)


func _stalk(delta: float) -> void:
	var target := _nearest_player()
	if target == null or _cooldown > 0.0:
		_stand(delta)
		return
	_walk_to(target.global_position, speed, delta)
	var flat := target.global_position - global_position
	flat.y = 0.0
	if flat.length() < GRAB_RADIUS:
		_victim = target
		dragging = true
		_state_time = DRAG_TIME
		var away := global_position - FARM_CENTER
		away.y = 0.0
		_drag_to = FARM_CENTER + (away.normalized() if away.length() > 0.1 else Vector3.BACK) * FOREST_EDGE
		target._set_dragged.rpc_id(target.get_multiplayer_authority(), get_path())
		SoundBank.everyone(get_tree(), "goblin_laugh", global_position)


func _drag(delta: float) -> void:
	_walk_to(_drag_to, DRAG_SPEED, delta)
	_state_time -= delta
	if _state_time <= 0.0 or global_position.distance_to(_drag_to) < 2.0:
		var victim := _victim
		_release()
		victim.take_damage(DRAG_DAMAGE, global_position, true)
		state = State.FLEE


## Любой удар заставляет отпустить пленника
func take_hit(amount: int, from_position: Vector3, knockback := 1.0, scare_time := 2.0) -> bool:
	if dragging:
		_release()
		_cooldown = REGRAB_COOLDOWN
	return super.take_hit(amount, from_position, knockback, scare_time)


func trap(duration: float) -> void:
	_release()
	super.trap(duration)


func dawn() -> void:
	_release()
	super.dawn()


func _on_died() -> void:
	_release()


func _exit_tree() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_release()


func _release() -> void:
	if is_instance_valid(_victim):
		_victim._set_dragged.rpc_id(_victim.get_multiplayer_authority(), NodePath())
	_victim = null
	dragging = false


func _nearest_player() -> Player:
	var best: Player = null
	var best_distance := INF
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player.downed or player.seated:
			continue
		var distance := player.global_position.distance_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


func _animate(_delta: float) -> void:
	match state:
		State.FLEE, State.SCARED:
			_look.play("Run", 1.4)
		State.TRAPPED:
			_look.play("HitReact", 1.0)
		_:
			if dragging:
				_look.play("Walk", 0.8)
			elif _is_moving():
				_look.play("Run", 1.0)
			else:
				_look.play("Idle")
