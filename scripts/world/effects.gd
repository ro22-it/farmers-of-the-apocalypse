class_name Effects
extends RefCounted

## Короткие визуальные эффекты: вспышка у ствола, трассер, облачко попадания.
## Создаются у каждого игрока сами и сами исчезают.

static var _materials := {}


## Яркая вспышка и свет у ствола на долю секунды
static func muzzle_flash(tree: SceneTree, at: Vector3) -> void:
	var flash := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	flash.mesh = mesh
	flash.material_override = _glow("flash", Color(1.0, 0.85, 0.4))
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.45)
	light.light_energy = 3.0
	light.omni_range = 6.0
	flash.add_child(light)
	tree.current_scene.add_child(flash)
	flash.global_position = at
	_fade_out(flash, 0.06)


## Тонкий светящийся след от ствола до попадания
static func tracer(tree: SceneTree, from: Vector3, to: Vector3, color: Color) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var line := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.015, 0.015, length)
	line.mesh = mesh
	line.material_override = _glow("tracer_%s" % color.to_html(), color)
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tree.current_scene.add_child(line)
	line.global_position = (from + to) / 2.0
	line.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	_fade_out(line, 0.08)


## Облачко пыли или щепок в точке попадания
static func impact(tree: SceneTree, at: Vector3, color: Color) -> void:
	var puff := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	mesh.radial_segments = 6
	mesh.rings = 3
	puff.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material_override = material
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tree.current_scene.add_child(puff)
	puff.global_position = at
	var tween := puff.create_tween().set_parallel()
	tween.tween_property(puff, "scale", Vector3.ONE * 3.0, 0.35)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.35)
	tween.chain().tween_callback(puff.queue_free)


static func _fade_out(node: Node3D, time: float) -> void:
	var tween := node.create_tween()
	tween.tween_interval(time)
	tween.tween_callback(node.queue_free)


static func _glow(key: String, color: Color) -> StandardMaterial3D:
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 4.0
		_materials[key] = material
	return _materials[key]
