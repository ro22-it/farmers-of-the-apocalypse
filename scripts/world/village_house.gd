class_name VillageHouse
extends StaticBody3D

## Дом деревни, собранный из деталей Quaternius Medieval Village MegaKit (CC0):
## стены по 2 м, двери, окна со ставнями, углы, черепичная крыша и фронтоны.
## Сборка одинаковая у всех игроков: случайность зависит только от variant.
## Столкновение — по стенам; у лавки фасад открыт, внутри пол.

const KIT := "res://assets/village/%s.gltf"
const CELL := 2.0
const WALL_HEIGHT := 3.12
## Размеры, под которые в наборе есть крыши и фронтоны
const WIDTHS := [2, 3, 4]

## Ширина по фасаду (2–4 клетки по 2 м) и глубина (2–7 клеток)
@export_range(2, 4) var width_cells := 3
@export_range(2, 7) var depth_cells := 4
@export_enum("Plaster", "UnevenBrick") var style := "Plaster"
@export var variant := 1
@export var chimney := true
## Ставни на окнах открыты
@export var shutters_open := true
## Лавка: фасада нет, внутри деревянный пол
@export var open_front := false


func _ready() -> void:
	_build()


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant
	var w := width_cells * CELL
	var d := depth_cells * CELL
	# Фасад смотрит в +Z: дверь посередине, по бокам окна
	var door_cell := width_cells / 2
	for i in width_cells:
		var x := -w / 2.0 + CELL * (i + 0.5)
		if not open_front:
			var front := "Door_Round" if i == door_cell else _window_or_wall(rng)
			_wall(front, Vector3(x, 0.0, d / 2.0), 0.0, i == door_cell)
		_wall(_window_or_wall(rng), Vector3(x, 0.0, -d / 2.0), PI, false)
	for i in depth_cells:
		var z := -d / 2.0 + CELL * (i + 0.5)
		_wall(_window_or_wall(rng), Vector3(w / 2.0, 0.0, z), PI / 2.0, false)
		_wall(_window_or_wall(rng), Vector3(-w / 2.0, 0.0, z), -PI / 2.0, false)
	for corner in [Vector3(w, 0, d), Vector3(-w, 0, d), Vector3(w, 0, -d), Vector3(-w, 0, -d)]:
		_piece("Corner_Exterior_Wood", corner / 2.0, 0.0)
	# Крыша и фронтоны
	_piece("Roof_RoundTiles_%dx%d" % [w, d], Vector3(0.0, WALL_HEIGHT, 0.0), 0.0)
	_piece("Roof_Front_Brick%d" % w, Vector3(0.0, WALL_HEIGHT, d / 2.0), 0.0)
	_piece("Roof_Front_Brick%d" % w, Vector3(0.0, WALL_HEIGHT, -d / 2.0), PI)
	if chimney:
		_piece("Prop_Chimney", Vector3(w / 4.0, WALL_HEIGHT + 0.6, -d / 4.0), 0.0)
	if open_front:
		for ix in width_cells:
			for iz in depth_cells:
				_piece("Floor_WoodDark", Vector3(-w / 2.0 + CELL * (ix + 0.5), 0.02, -d / 2.0 + CELL * (iz + 0.5)), 0.0)
	# Столкновение: по стене на каждую сторону
	var height := WALL_HEIGHT + 1.0
	_solid(Vector3(w + 0.4, height, 0.4), Vector3(0.0, height / 2.0, -d / 2.0))
	_solid(Vector3(0.4, height, d + 0.4), Vector3(w / 2.0, height / 2.0, 0.0))
	_solid(Vector3(0.4, height, d + 0.4), Vector3(-w / 2.0, height / 2.0, 0.0))
	if not open_front:
		_solid(Vector3(w + 0.4, height, 0.4), Vector3(0.0, height / 2.0, d / 2.0))


func _solid(size: Vector3, at: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	add_child(shape)


func _window_or_wall(rng: RandomNumberGenerator) -> String:
	return "Window_Wide_Round" if rng.randf() < 0.55 else "Straight"


## Стена клетки: kind — Straight, Door_Round, Window_Wide_Round
func _wall(kind: String, at: Vector3, angle: float, with_door: bool) -> void:
	_piece("Wall_%s_%s" % [style, kind], at, angle)
	if with_door:
		_piece("Door_1_Round", at, angle)
	elif kind.begins_with("Window"):
		_piece("Window_Wide_Round1", at, angle)
		_piece("WindowShutters_Wide_Round_%s" % ("Open" if shutters_open else "Closed"), at, angle)


func _piece(piece: String, at: Vector3, angle: float) -> Node3D:
	var scene := load(KIT % piece) as PackedScene
	if scene == null:
		push_warning("Нет детали деревни: %s" % piece)
		return null
	var node: Node3D = scene.instantiate()
	node.position = at
	node.rotation.y = angle
	add_child(node)
	return node
