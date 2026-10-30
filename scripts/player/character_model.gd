class_name CharacterModel
extends Node3D

## Модель персонажа по классу (Quaternius Modular Men/Women, CC0) с анимациями.
## Анимацию каждый компьютер выбирает сам по движению игрока, поэтому для
## чужих игроков ничего дополнительно по сети не передаётся.
## Используется и в меню для предпросмотра (без игрока).

const MODELS := {
	"farmer": "res://assets/characters/farmer.glb",
	"mechanic": "res://assets/characters/mechanic.glb",
	"hunter": "res://assets/characters/hunter.glb",
	"herder": "res://assets/characters/herder.glb",
	"herbalist": "res://assets/characters/herbalist.glb",
}
## Рост модели в исходном файле и рост игрока
const MODEL_HEIGHT := 1.86
const PLAYER_HEIGHT := 1.8
const LOOPED := ["Idle", "Idle_Neutral", "Idle_Gun", "Walk", "Run", "Run_Back", "Run_Left", "Run_Right", "Wave"]
const GUNS := ["shotgun", "rifle", "slingshot"]
const BLEND := 0.2

var _anim: AnimationPlayer
var _player: Node3D
var _last_position := Vector3.ZERO
var _velocity := Vector3.ZERO
var _action_left := 0.0
var _idle_override := ""


## class_id — класс игрока; player — его узел (null в предпросмотре)
func setup(class_id: String, player: Node3D = null) -> void:
	_player = player
	var path: String = MODELS.get(class_id, MODELS.farmer)
	var model: Node3D = load(path).instantiate()
	# Модели смотрят в +Z, а «вперёд» у игрока — это −Z
	model.rotation.y = PI
	model.scale = Vector3.ONE * PLAYER_HEIGHT / MODEL_HEIGHT
	add_child(model)
	_anim = model.find_children("*", "AnimationPlayer", true, false)[0]
	for anim_name in LOOPED:
		if _anim.has_animation(anim_name):
			_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_anim.play("Idle")
	if _player:
		_last_position = _player.global_position


## Своё тело игрок не видит, только тень от него. В виде от 3 лица — видит.
func set_shadow_only(value: bool) -> void:
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if value else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = mode


## Разовое действие поверх ходьбы: удар, выстрел, взмах рукой
func play_action(anim_name: String) -> void:
	if _anim == null or not _anim.has_animation(anim_name):
		return
	_anim.speed_scale = 1.0
	_anim.play(anim_name, 0.05)
	_action_left = _anim.get_animation(anim_name).length


## Для предпросмотра: что играть вместо обычного покоя
func set_idle(anim_name: String) -> void:
	_idle_override = anim_name


func _physics_process(delta: float) -> void:
	if _anim == null:
		return
	if _player:
		# Скорость по смещению: так она есть и у чужих игроков
		var moved := (_player.global_position - _last_position) / maxf(delta, 0.001)
		_last_position = _player.global_position
		_velocity = _velocity.lerp(Vector3(moved.x, 0.0, moved.z), minf(12.0 * delta, 1.0))
	if _action_left > 0.0:
		_action_left -= delta
		return
	_play_loop(_pick_animation())


func _pick_animation() -> String:
	if _player == null:
		return _idle_override if _idle_override != "" else "Idle"
	if _player.downed or _player.seated:
		return "Idle_Neutral"
	var speed := _velocity.length()
	_anim.speed_scale = 1.0
	if speed < 0.4:
		return "Idle_Gun" if _holds_gun() else "Idle"
	var basis := _player.global_basis
	var forward := _velocity.dot(-basis.z)
	var side := _velocity.dot(basis.x)
	if absf(side) > absf(forward) and absf(side) > 1.0:
		return "Run_Right" if side > 0.0 else "Run_Left"
	if forward < -0.5:
		return "Run_Back"
	if speed > Player.WALK_SPEED + 0.8:
		_anim.speed_scale = speed / Player.SPRINT_SPEED
		return "Run"
	_anim.speed_scale = clampf(speed / Player.WALK_SPEED * 1.4, 0.6, 1.6)
	return "Walk"


func _play_loop(anim_name: String) -> void:
	if _anim.current_animation != anim_name:
		_anim.play(anim_name, BLEND)


func _holds_gun() -> bool:
	var held: String = _player.held_scene
	for gun in GUNS:
		if held.contains(gun):
			return true
	return false
