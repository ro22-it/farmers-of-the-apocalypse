class_name UpgradeToggle
extends Node3D

## Часть фермы, которая появляется после покупки общего улучшения:
## до покупки её не видно и об неё не споткнуться.
## Грядки и коровы внутри включаются своим set_enabled().

@export var upgrade_id := ""

var active := false
## Что изначально сталкивалось — чтобы вернуть как было
var _solid_csg := []
var _bodies := {}


func _ready() -> void:
	add_to_group("upgrade_toggles")
	_remember(self)
	set_active(false)


func set_active(value: bool) -> void:
	active = value
	visible = value
	_switch(self, value)


func _remember(node: Node) -> void:
	for child in node.get_children():
		if child.has_method("set_enabled"):
			continue
		if child is CSGShape3D and child.use_collision:
			_solid_csg.append(child)
		elif child is CollisionObject3D:
			_bodies[child] = child.collision_layer
		_remember(child)


func _switch(node: Node, value: bool) -> void:
	for child in node.get_children():
		if child.has_method("set_enabled"):
			child.set_enabled(value)
			continue
		if child in _solid_csg:
			child.use_collision = value
		elif _bodies.has(child):
			child.collision_layer = _bodies[child] if value else 0
		_switch(child, value)
