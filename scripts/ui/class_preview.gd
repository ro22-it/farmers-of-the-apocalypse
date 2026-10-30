class_name ClassPreview
extends PanelContainer

## Предпросмотр персонажа в меню: свой маленький 3D-мир с моделью класса.
## Модель медленно крутится, мышью её можно повернуть. Рисуется, только пока видна.

const SIZE := Vector2(300, 440)
const SPIN_SPEED := 0.35
const DRAG_SPEED := 0.01

var _pivot: Node3D
var _model: CharacterModel
var _title: Label
var _dragging := false


func _init(background: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	add_child(box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	box.add_child(_title)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = SIZE
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	container.gui_input.connect(_on_input)
	box.add_child(container)
	var hint := Label.new()
	hint.text = "потяните мышью, чтобы повернуть"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate.a = 0.6
	box.add_child(hint)

	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	_build_stage(viewport)


func show_class(class_id: String) -> void:
	_title.text = PlayerClasses.display_name(class_id)
	if _model:
		_model.queue_free()
	_model = CharacterModel.new()
	_pivot.add_child(_model)
	_model.setup(class_id)
	_model.play_action("Wave")


func _process(delta: float) -> void:
	if is_visible_in_tree() and not _dragging:
		_pivot.rotation.y += SPIN_SPEED * delta


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_pivot.rotation.y += event.relative.x * DRAG_SPEED


## Сцена: камера, тёплый и холодный свет, круглая подставка
func _build_stage(viewport: SubViewport) -> void:
	var stage := Node3D.new()
	viewport.add_child(stage)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.6, 0.65)
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	stage.add_child(world_environment)

	var camera := Camera3D.new()
	camera.fov = 32.0
	stage.add_child(camera)
	camera.position = Vector3(0.0, 1.15, 4.2)
	camera.rotation.x = deg_to_rad(-6.0)

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.9, 0.75)
	key.light_energy = 1.3
	key.shadow_enabled = true
	key.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(30.0), 0.0)
	stage.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.6, 0.75, 1.0)
	rim.light_energy = 0.7
	rim.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(200.0), 0.0)
	stage.add_child(rim)

	var base_material := StandardMaterial3D.new()
	base_material.albedo_color = Color(0.36, 0.5, 0.27)
	base_material.roughness = 0.9
	var base := CylinderMesh.new()
	base.top_radius = 0.75
	base.bottom_radius = 0.8
	base.height = 0.12
	base.material = base_material
	var base_mesh := MeshInstance3D.new()
	base_mesh.mesh = base
	base_mesh.position.y = -0.06
	stage.add_child(base_mesh)

	_pivot = Node3D.new()
	stage.add_child(_pivot)
	# Чуть повёрнут к зрителю
	_pivot.rotation.y = deg_to_rad(-20.0)
