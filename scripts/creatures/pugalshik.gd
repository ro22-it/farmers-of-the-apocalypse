class_name Pugalshik
extends Creature

## Пугальщик: оживший пугало. Пока на него смотрит хоть один игрок —
## стоит как вкопанный. Стоит всем отвернуться — рывками подбирается
## к ближайшему и бьёт так, что тот летит кувырком.
## Решает хост; «смотрят ли на меня» приходит клиентам для анимации.

const HIT_DAMAGE := 25.0
## Руки длинные: достаёт по горизонтали на столько
const HIT_RADIUS := 1.7
const HIT_COOLDOWN := 2.5
## Под каким углом от центра взгляда игрок «видит» Пугальщика
const LOOK_ANGLE := 38.0
const SEE_DISTANCE := 45.0
const WATCH_CHECK_INTERVAL := 0.1
const FENCE_HIT_INTERVAL := 1.2

## Смотрит ли на него кто-то прямо сейчас
var watched := false

var _hit_cooldown := 0.0
var _watch_check := 0.0
var _fence_time := 0.0
var _twitch := 0.0
var _model: Node3D
var _head: Node3D


func _ready() -> void:
	super._ready()
	_build_model()


func _physics_process(delta: float) -> void:
	_animate(delta)
	if not multiplayer.is_server():
		return
	_hit_cooldown -= delta
	_watch_check -= delta
	if _watch_check <= 0.0:
		_watch_check = WATCH_CHECK_INTERVAL
		var now := _is_watched()
		if watched and not now:
			SoundBank.everyone(get_tree(), "creak", global_position, -6.0)
		watched = now
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
			_hunt(delta)


func _hunt(delta: float) -> void:
	if watched:
		_stand(delta)
		return
	var target := _nearest_player()
	if target == null:
		_stand(delta)
		return
	var fence := _walk_to(target.global_position, speed, delta)
	if fence and not fence.is_broken():
		_fence_time -= delta
		if _fence_time <= 0.0:
			_fence_time = FENCE_HIT_INTERVAL
			fence.damage(1)
	var flat := target.global_position - global_position
	flat.y = 0.0
	if _hit_cooldown <= 0.0 and flat.length() < HIT_RADIUS:
		_hit_cooldown = HIT_COOLDOWN
		target.take_damage(HIT_DAMAGE, global_position, true)
		SoundBank.everyone(get_tree(), "punch", global_position)


## Свет его не пугает — только удары
func scare(from_position: Vector3, duration: float) -> void:
	super.scare(from_position, minf(duration, 1.0))


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


## Хоть один игрок в сознании смотрит на него, и между ними ничего нет
func _is_watched() -> bool:
	var chest := global_position + Vector3(0.0, 1.3, 0.0)
	var space := get_world_3d().direct_space_state
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player.downed:
			continue
		var camera: Camera3D = player.get_node("Head/Camera3D")
		var to_me := chest - camera.global_position
		if to_me.length() > SEE_DISTANCE:
			continue
		var forward := -camera.global_basis.z
		if forward.angle_to(to_me) > deg_to_rad(LOOK_ANGLE):
			continue
		var query := PhysicsRayQueryParameters3D.create(camera.global_position, chest, 1)
		if space.intersect_ray(query).is_empty():
			return true
	return false


## Под взглядом — замер; без взгляда — подёргивается и подпрыгивает на ходу
func _animate(delta: float) -> void:
	if _model == null:
		return
	if watched or state == State.TRAPPED:
		return
	if _is_moving():
		_twitch += delta * 11.0
		_model.position.y = absf(sin(_twitch)) * 0.12
		_model.rotation.z = sin(_twitch * 0.5) * 0.12
		_head.rotation.z = sin(_twitch * 0.37) * 0.35
	else:
		_model.position.y = 0.0


## Модель из простых форм: мешковина, плащ, руки в стороны, соломенная шляпа
func _build_model() -> void:
	_model = Node3D.new()
	add_child(_model)
	var burlap := _material(Color(0.62, 0.52, 0.36))
	var coat := _material(Color(0.2, 0.17, 0.15))
	var straw := _material(Color(0.78, 0.66, 0.32))
	var hat := _material(Color(0.28, 0.22, 0.15))
	var eyes := _material(Color(1.0, 0.35, 0.1))
	eyes.emission_enabled = true
	eyes.emission = Color(1.0, 0.3, 0.05)
	eyes.emission_energy_multiplier = 5.0
	for side in [-0.12, 0.12]:
		_part(_model, _box(Vector3(0.1, 0.9, 0.1)), coat, Vector3(side, 0.45, 0.0))
	_part(_model, _box(Vector3(0.62, 0.85, 0.32)), coat, Vector3(0.0, 1.25, 0.0))
	_part(_model, _box(Vector3(1.7, 0.12, 0.12)), coat, Vector3(0.0, 1.55, 0.0))
	for side in [-0.9, 0.9]:
		var tuft := CylinderMesh.new()
		tuft.top_radius = 0.02
		tuft.bottom_radius = 0.09
		tuft.height = 0.22
		_part(_model, tuft, straw, Vector3(side, 1.55, 0.0)).rotation.z = signf(side) * -PI / 2.0
	_head = Node3D.new()
	_head.position = Vector3(0.0, 1.88, 0.0)
	_model.add_child(_head)
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.23
	head_mesh.height = 0.5
	_part(_head, head_mesh, burlap, Vector3.ZERO)
	for side in [-0.08, 0.08]:
		var eye := SphereMesh.new()
		eye.radius = 0.035
		eye.height = 0.07
		_part(_head, eye, eyes, Vector3(side, 0.03, -0.2))
	_part(_head, _box(Vector3(0.16, 0.025, 0.02)), coat, Vector3(0.0, -0.09, -0.21))
	var brim := CylinderMesh.new()
	brim.top_radius = 0.4
	brim.bottom_radius = 0.4
	brim.height = 0.03
	_part(_head, brim, hat, Vector3(0.0, 0.17, 0.0))
	var crown := CylinderMesh.new()
	crown.top_radius = 0.05
	crown.bottom_radius = 0.2
	crown.height = 0.3
	_part(_head, crown, hat, Vector3(0.0, 0.32, 0.0)).rotation.z = 0.15


func _part(parent: Node3D, mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = at
	parent.add_child(part)
	return part


static func _box(size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	return box


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material
