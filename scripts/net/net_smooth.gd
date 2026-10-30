class_name NetSmooth
extends Node

## Сглаживание движения по сети. Владелец объекта (хост — для предметов и
## существ, игрок — для своего персонажа) каждый кадр пишет сюда, где объект на
## самом деле, а синхронизатор рассылает эти значения. На остальных компьютерах
## объект плавно догоняет присланное положение вместо скачков 20–30 раз в секунду.
## Ставится дочерним узлом к телу, в синхронизаторе — свойства target_*.

## Как быстро догонять (больше — точнее, но резче)
@export var rate := 14.0
## Дальше этого — не догонять, а сразу переставить (телепорт, возврат на место)
@export var snap_distance := 5.0

var target_position := Vector3.ZERO
var target_rotation := Quaternion.IDENTITY

var _body: Node3D
var _has_target := false


func _ready() -> void:
	_body = get_parent() as Node3D
	# Пришедшее при появлении — сразу на место, без «прилёта» из нуля
	if not _owns() and target_position != Vector3.ZERO:
		_snap()
	elif _owns():
		_record()


func _physics_process(_delta: float) -> void:
	if _owns():
		_record()


func _process(delta: float) -> void:
	if _owns() or not _has_target and target_position == Vector3.ZERO:
		return
	_has_target = true
	var current := _body.global_position
	if current.distance_to(target_position) > snap_distance:
		_snap()
		return
	var weight := 1.0 - exp(-rate * delta)
	_body.global_position = current.lerp(target_position, weight)
	var rotation_now := _body.global_basis.get_rotation_quaternion()
	_body.global_basis = Basis(rotation_now.slerp(target_rotation, weight)).scaled(_body.global_basis.get_scale())


func _owns() -> bool:
	return _body.is_multiplayer_authority()


func _record() -> void:
	target_position = _body.global_position
	target_rotation = _body.global_basis.get_rotation_quaternion()


func _snap() -> void:
	_body.global_position = target_position
	_body.global_basis = Basis(target_rotation).scaled(_body.global_basis.get_scale())
