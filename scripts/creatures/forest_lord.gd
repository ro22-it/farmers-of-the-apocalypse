class_name ForestLord
extends Creature

## Хозяин леса: огромный тёмный олень, босс редких ночей.
## Идёт к ближайшему игроку (или к центру фермы), ломает забор с пары ударов,
## топотом раскидывает всех рядом и зовёт волчат Роя. Удары его не отбрасывают
## и не пугают. Победа — награда всей ферме.

const STOMP_RADIUS := 5.0
const STOMP_DAMAGE := 20.0
const STOMP_INTERVAL := 4.0
const SUMMON_INTERVAL := 25.0
const SUMMON_COUNT := 2
const FENCE_DAMAGE := 3
const FENCE_INTERVAL := 1.5
## Дальше этого игроков не преследует, идёт к ферме
const CHASE_DISTANCE := 30.0
const FARM_CENTER := Vector3(0.0, 0.0, 6.0)
const REWARD := 150

## Счётчик топотов — по его изменению все проигрывают удар
var stomp_count := 0

var _stomp_time := STOMP_INTERVAL
var _summon_time := 8.0
var _fence_time := 0.0
var _last_stomp := 0

@onready var _look: CreepyModel = $Model/Look


func _ready() -> void:
	super._ready()
	_marker.position.y = 3.6
	if multiplayer.is_server():
		var economy := get_tree().get_first_node_in_group("economy") as Economy
		if economy:
			economy.announce.rpc("Из леса вышел Хозяин леса!")
		SoundBank.everyone(get_tree(), "giant_roar", global_position)


func _physics_process(delta: float) -> void:
	_animate(delta)
	if not multiplayer.is_server():
		return
	if state == State.TRAPPED:
		_update_trapped(delta)
		return
	if state == State.FLEE:
		_walk_to(_home, flee_speed, delta)
		if _far_from_farm() or global_position.distance_to(_home) < 1.5:
			queue_free()
		return
	var target := _target_point()
	var fence := _walk_to(target, speed, delta) if global_position.distance_to(target) > 2.5 else null
	if fence == null and global_position.distance_to(target) <= 2.5:
		_stand(delta)
	if fence and not fence.is_broken():
		_fence_time -= delta
		if _fence_time <= 0.0:
			_fence_time = FENCE_INTERVAL
			fence.damage(FENCE_DAMAGE)
			SoundBank.everyone(get_tree(), "fence_break", fence.global_position)
	_stomp_time -= delta
	if _stomp_time <= 0.0 and _players_near() > 0:
		_stomp_time = STOMP_INTERVAL
		_stomp()
	_summon_time -= delta
	if _summon_time <= 0.0:
		_summon_time = SUMMON_INTERVAL
		_summon()


func _target_point() -> Vector3:
	var best := FARM_CENTER
	var best_distance := CHASE_DISTANCE
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player.downed or player.seated:
			continue
		var distance := player.global_position.distance_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = player.global_position
	return best


func _players_near() -> int:
	var count := 0
	for player: Player in get_tree().get_nodes_in_group("players"):
		if not player.downed and player.global_position.distance_to(global_position) < STOMP_RADIUS:
			count += 1
	return count


func _stomp() -> void:
	stomp_count += 1
	SoundBank.everyone(get_tree(), "boom_medium", global_position)
	for player: Player in get_tree().get_nodes_in_group("players"):
		if not player.downed and player.global_position.distance_to(global_position) < STOMP_RADIUS:
			player.take_damage(STOMP_DAMAGE, global_position, true)


func _summon() -> void:
	var director := get_tree().get_first_node_in_group("night_director") as NightDirector
	if director == null:
		return
	SoundBank.everyone(get_tree(), "growl", global_position)
	for i in SUMMON_COUNT:
		var offset := Vector3(randf_range(-2.5, 2.5), 0.3, randf_range(-2.5, 2.5))
		director.spawn(NightDirector.ROJ, global_position + offset)


## Махину не отбросить и не испугать
func take_hit(amount: int, from_position: Vector3, _knockback := 1.0, _scare_time := 2.0) -> bool:
	return super.take_hit(amount, from_position, 0.0, 0.0)


func scare(_from_position: Vector3, _duration: float) -> void:
	pass


func _on_died() -> void:
	var economy := get_tree().get_first_node_in_group("economy") as Economy
	if economy:
		economy.add(REWARD)
		economy.announce.rpc("Хозяин леса повержен! Ферме +%d монет" % REWARD)
	SoundBank.everyone(get_tree(), "giant_death", global_position)


func _animate(_delta: float) -> void:
	if stomp_count != _last_stomp:
		_last_stomp = stomp_count
		_look.play("Attack_Kick", 1.2, true)
		return
	if _look.is_playing_once():
		return
	if state == State.TRAPPED:
		_look.play("Idle_HitReact1")
	elif _moved_recently():
		_look.play("Walk", 0.7)
	else:
		_look.play("Idle_Headlow")


var _last_position := Vector3.ZERO


## Скорость по смещению — так она видна и клиентам
func _moved_recently() -> bool:
	var moved := global_position.distance_to(_last_position) > 0.005
	_last_position = global_position
	return moved
