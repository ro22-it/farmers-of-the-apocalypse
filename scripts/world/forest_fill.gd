extends Node3D

## Густой лес до самых краёв карты, чтобы не было видно, где она кончается.
## Сосны и мёртвые деревья (Quaternius, CC0), между ними кусты и камни.
## Всё рисуется пачками (MultiMesh) — тысячи деревьев почти не нагружают видеокарту.
## Расстановка одинаковая у всех игроков (фиксированное зерно), синхронизировать не нужно.

const PREFABS := "res://assets/nature/prefabs/%s.tscn"
## Деревья: сцена, вес (как часто встречается), масштаб от и до
const TREES := [
	["pine_tree_1", 1.0, 1.3, 2.0], ["pine_tree_2", 1.0, 1.3, 2.0], ["pine_tree_3", 1.0, 1.6, 2.4],
	["pine_tree_4", 1.0, 1.3, 2.0], ["pine_tree_5", 1.0, 1.3, 2.0],
	["dead_tree_1", 0.25, 0.9, 1.3], ["dead_tree_2", 0.25, 0.9, 1.3], ["dead_tree_3", 0.25, 0.9, 1.3],
	["dead_tree_4", 0.25, 0.9, 1.3], ["dead_tree_5", 0.25, 0.9, 1.3],
]
## Мелочь без столкновений
const DECOR := [["bush_large", 1.0, 0.8, 1.4], ["bush", 1.0, 0.8, 1.4], ["rock_1", 0.5, 0.8, 1.6], ["rock_3", 0.5, 0.8, 1.6], ["rock_5", 0.5, 0.8, 1.6]]
const TRUNK_RADIUS := 0.35
const TRUNK_HEIGHT := 3.0
## У краёв карты мёртвых деревьев больше — лес жутче
const EDGE_DEAD_BONUS := 3.0
const SEED := 2026
const SPACING := 4.5
const DECOR_PER_TREE := 0.6
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
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var trees := {}
	var decor := {}
	var trunks: Array[Transform3D] = []
	var x := AREA_MIN.x
	while x <= AREA_MAX.x:
		var z := AREA_MIN.y
		while z <= AREA_MAX.y:
			var point := Vector2(x + rng.randf_range(-1.6, 1.6), z + rng.randf_range(-1.6, 1.6))
			if _allowed(point):
				var edge := _edge_factor(point)
				var pick := _pick(TREES, rng, edge)
				var t := _transform(point, rng, pick)
				trees.get_or_add(pick[0], []).append(t)
				trunks.append(t)
				if rng.randf() < DECOR_PER_TREE:
					var near := point + Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
					var small := _pick(DECOR, rng, 0.0)
					decor.get_or_add(small[0], []).append(_transform(near, rng, small))
			z += SPACING
		x += SPACING
	for name in trees:
		_add_batch(name, trees[name])
	for name in decor:
		_add_batch(name, decor[name])
	_add_trunk_collisions(trunks)


## Одна пачка на вид дерева: берём меши из сцены вместе с материалами
func _add_batch(name: String, transforms: Array) -> void:
	var template: Node3D = load(PREFABS % name).instantiate()
	for part: MeshInstance3D in template.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = part.mesh.duplicate()
		for i in mesh.get_surface_count():
			var material := part.get_surface_override_material(i)
			if material:
				mesh.surface_set_material(i, material)
		var local := _relative(template, part)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = transforms.size()
		for i in transforms.size():
			multimesh.set_instance_transform(i, transforms[i] * local)
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		add_child(instance)
	template.free()


## Стволы твёрдые: одно статическое тело на весь лес
func _add_trunk_collisions(trunks: Array[Transform3D]) -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var shape := CylinderShape3D.new()
	shape.radius = TRUNK_RADIUS
	shape.height = TRUNK_HEIGHT
	for t in trunks:
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = t.origin + Vector3.UP * TRUNK_HEIGHT / 2.0
		body.add_child(collision)


static func _relative(root: Node3D, node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current := node
	while current != root and current != null:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result


static func _pick(list: Array, rng: RandomNumberGenerator, edge: float) -> Array:
	var total := 0.0
	for entry in list:
		total += _weight(entry, edge)
	var roll := rng.randf() * total
	for entry in list:
		roll -= _weight(entry, edge)
		if roll <= 0.0:
			return entry
	return list[0]


static func _weight(entry: Array, edge: float) -> float:
	return entry[1] * (1.0 + EDGE_DEAD_BONUS * edge if str(entry[0]).begins_with("dead") else 1.0)


static func _transform(point: Vector2, rng: RandomNumberGenerator, entry: Array) -> Transform3D:
	var size := rng.randf_range(entry[2], entry[3])
	var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * size)
	return Transform3D(basis, Vector3(point.x, 0.0, point.y))


## 0 — у фермы, 1 — у края карты
func _edge_factor(point: Vector2) -> float:
	var to_edge := minf(minf(point.x - AREA_MIN.x, AREA_MAX.x - point.x), minf(point.y - AREA_MIN.y, AREA_MAX.y - point.y))
	return clampf(1.0 - to_edge / 40.0, 0.0, 1.0)


func _allowed(point: Vector2) -> bool:
	if point.length() < FARM_RADIUS:
		return false
	if point.distance_to(VILLAGE_CENTER) < VILLAGE_RADIUS:
		return false
	if point.x > ROAD_FROM_X and point.x < VILLAGE_CENTER.x and absf(point.y) < ROAD_HALF_WIDTH:
		return false
	return true
