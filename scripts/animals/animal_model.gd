class_name AnimalModel
extends Node3D

## Модель животного (Quaternius Ultimate Animated Animals, CC0) с анимациями.
## Анимацию выбирает каждый компьютер сам по скорости хозяина-тела,
## по сети ничего лишнего не идёт. Стоя иногда щиплет траву или оглядывается.

const LOOPED := ["Idle", "Idle_2", "Idle_Headlow", "Idle_2_HeadLow", "Walk", "Gallop", "Eating"]
const BLEND := 0.25

@export_file("*.gltf") var model_path := ""
@export var model_scale := 0.3
## Модели смотрят в +Z; поворот, чтобы смотрели в −Z, как наши животные
@export var yaw := PI
## Быстрее этого — галоп, медленнее — шаг
@export var gallop_speed := 3.0
## Скорость, при которой шаг проигрывается с обычной частотой
@export var walk_speed := 1.2
## Что играть стоя, по очереди
@export var idle_animations: PackedStringArray = ["Idle", "Eating", "Idle_2"]

var _anim: AnimationPlayer
var _body: Node3D
var _last_position := Vector3.ZERO
var _speed := 0.0
var _idle_index := 0
var _idle_left := 0.0


func _ready() -> void:
	if model_path == "":
		return
	var model: Node3D = load(model_path).instantiate()
	model.scale = Vector3.ONE * model_scale
	model.rotation.y = yaw
	add_child(model)
	_anim = model.find_children("*", "AnimationPlayer", true, false)[0]
	for anim_name in LOOPED:
		if _anim.has_animation(anim_name):
			_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_body = get_parent() as Node3D
	_last_position = _body.global_position
	_idle_left = randf_range(2.0, 6.0)
	_anim.play(idle_animations[0])


## Разовое действие: удар, лай, испуг
func play_action(anim_name: String) -> void:
	if _anim and _anim.has_animation(anim_name):
		_anim.play(anim_name, 0.1)


func _physics_process(delta: float) -> void:
	if _anim == null:
		return
	var moved := _body.global_position - _last_position
	_last_position = _body.global_position
	moved.y = 0.0
	_speed = lerpf(_speed, moved.length() / maxf(delta, 0.001), minf(8.0 * delta, 1.0))
	# Разовое действие доигрывает до конца
	if _anim.current_animation != "" and not _anim.current_animation in LOOPED:
		return
	if _speed > gallop_speed:
		_play("Gallop", _speed / (gallop_speed * 1.6))
	elif _speed > 0.25:
		_play("Walk", clampf(_speed / walk_speed, 0.6, 1.8))
	else:
		_idle_left -= delta
		if _idle_left <= 0.0:
			_idle_index = (_idle_index + 1) % idle_animations.size()
			_idle_left = randf_range(3.0, 8.0)
		_play(idle_animations[_idle_index], 1.0)


func _play(anim_name: String, speed_scale: float) -> void:
	_anim.speed_scale = speed_scale
	if _anim.current_animation != anim_name and _anim.has_animation(anim_name):
		_anim.play(anim_name, BLEND)
