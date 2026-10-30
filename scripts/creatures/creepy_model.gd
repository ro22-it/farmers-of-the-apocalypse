class_name CreepyModel
extends Node3D

## Модель существа из готового набора (Quaternius), сделанная жутче:
## затемнённая, без оружия, со светящимися глазами на кости головы.
## Умеет проигрывать анимации по имени и замереть в позе (для тела после смерти).

## Во сколько раз темнее исходных цветов
@export var tint := Color(0.45, 0.42, 0.4)
@export var eye_color := Color(1.0, 0.85, 0.2)
## Куда ставить глаза относительно кости головы
@export var eye_offset := Vector3(0.11, 0.12, 0.28)
@export var eye_size := 0.07
## Меши, которые спрятать (например, оружие в руке)
@export var hide_meshes: PackedStringArray = []
## Если задано — модель замирает в последнем кадре этой анимации
@export var frozen_pose := ""

var _player: AnimationPlayer
var _current := ""


func _ready() -> void:
	_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mesh.name in hide_meshes:
			mesh.visible = false
			continue
		_darken(mesh)
	_add_eyes()
	if frozen_pose != "" and _player and _player.has_animation(frozen_pose):
		_player.play(frozen_pose)
		_player.seek(_player.get_animation(frozen_pose).length, true)
		_player.pause()
	else:
		play("Idle")


func play(animation: String, speed := 1.0) -> void:
	if _player == null or not _player.has_animation(animation):
		return
	_player.speed_scale = speed
	if animation != _current:
		_current = animation
		_player.play(animation, 0.2)


func _darken(mesh: MeshInstance3D) -> void:
	for i in mesh.mesh.get_surface_count():
		var material := mesh.get_active_material(i) as StandardMaterial3D
		if material == null:
			continue
		var dark: StandardMaterial3D = material.duplicate()
		dark.albedo_color = material.albedo_color * tint
		dark.roughness = 1.0
		mesh.set_surface_override_material(i, dark)


func _add_eyes() -> void:
	var skeleton := find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or skeleton.find_bone("Head") < 0:
		return
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = "Head"
	skeleton.add_child(attachment)
	var material := StandardMaterial3D.new()
	material.albedo_color = eye_color
	material.emission_enabled = true
	material.emission = eye_color
	material.emission_energy_multiplier = 4.0
	var sphere := SphereMesh.new()
	sphere.radius = eye_size
	sphere.height = eye_size * 2.0
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = sphere
		eye.material_override = material
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.position = Vector3(eye_offset.x * side, eye_offset.y, eye_offset.z)
		attachment.add_child(eye)
