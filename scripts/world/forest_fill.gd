extends Node3D

## Густой лес до самых краёв карты, чтобы не было видно, где она кончается.
## Деревья рисуются пачкой (MultiMesh) — тысячи стволов почти не нагружают видеокарту.
## Расстановка одинаковая у всех игроков (фиксированное зерно), синхронизировать не нужно.

const TREE_SCENE := preload("res://scenes/world/tree.tscn")
const SEED := 2026
const SPACING := 4.5
## Земля: от и до по X и Z (края закрыты невидимой стеной)
const AREA_MIN := Vector2(-96.0, -96.0)
const AREA_MAX := Vector2(256.0, 96.0)
## Где деревьев быть не должно: ферма, дорога, деревня
const FARM_RADIUS := 31.0
const VILLAGE_CENTER := Vector2(169.0, 0.0)
const VILLAGE_RADIUS := 33.0
const ROAD_HALF_WIDTH := 7.0
const ROAD_FROM_X := 20.0


func _ready() -> void:
	var template := TREE_SCENE.instantiate()
	var parts: Array[MeshInstance3D] = []
	for child in template.get_children():
		if child is MeshInstance3D:
			parts.append(child)
	var trunk_shape: CylinderShape3D = template.get_node("CollisionShape3D").shape

	var transforms := _place_trees()
	for part in parts:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = part.mesh
		multimesh.instance_count = transforms.size()
		for i in transforms.size():
			multimesh.set_instance_transform(i, transforms[i] * part.transform)
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		add_child(instance)

	# Стволы твёрдые: одно статическое тело на весь лес
	var body := StaticBody3D.new()
	add_child(body)
	for t in transforms:
		var shape := CollisionShape3D.new()
		shape.shape = trunk_shape
		shape.transform = t * Transform3D(Basis(), Vector3(0.0, 1.5, 0.0))
		body.add_child(shape)
	template.free()


func _place_trees() -> Array[Transform3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var result: Array[Transform3D] = []
	var x := AREA_MIN.x
	while x <= AREA_MAX.x:
		var z := AREA_MIN.y
		while z <= AREA_MAX.y:
			var point := Vector2(x + rng.randf_range(-1.6, 1.6), z + rng.randf_range(-1.6, 1.6))
			var size := rng.randf_range(0.8, 1.6)
			var turn := rng.randf_range(0.0, TAU)
			if _allowed(point):
				var basis := Basis(Vector3.UP, turn).scaled(Vector3.ONE * size)
				result.append(Transform3D(basis, Vector3(point.x, 0.0, point.y)))
			z += SPACING
		x += SPACING
	return result


func _allowed(point: Vector2) -> bool:
	if point.length() < FARM_RADIUS:
		return false
	if point.distance_to(VILLAGE_CENTER) < VILLAGE_RADIUS:
		return false
	if point.x > ROAD_FROM_X and point.x < VILLAGE_CENTER.x and absf(point.y) < ROAD_HALF_WIDTH:
		return false
	return true
