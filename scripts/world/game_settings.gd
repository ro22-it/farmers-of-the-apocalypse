extends Node

## Настройки игры: экран, графика, звук, управление. Автозагрузка «Settings».
## Хранятся в том же файле, что имя и IP (user://settings.cfg), в своих разделах.

signal changed

const PATH := "user://settings.cfg"
const FPS_CHOICES := [0, 30, 60, 120, 144]
const SHADOW_SIZES := [0, 2048, 4096]

var fullscreen := false
var vsync := true
## 0 — без ограничения
var max_fps := 0
## Доля разрешения, в которой рисуется 3D: меньше — быстрее на слабых ПК
var render_scale := 1.0
## 0 — без теней, 1 — простые, 2 — чёткие
var shadows := 2
## Качество графики: 0 — низкое, 1 — среднее, 2 — высокое.
## Дальность леса, тени деревьев, затенение (SSAO), свечение, сглаживание.
var quality := 1
var fov := 80.0
var master_volume := 1.0
var ambience_volume := 0.8
var effects_volume := 1.0
var mouse_sensitivity := 1.0
var invert_y := false


func _ready() -> void:
	_load()
	apply()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		fullscreen = not fullscreen
		apply()
		save()


func apply() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps
	get_tree().root.scaling_3d_scale = render_scale
	# Уменьшенное разрешение растягиваем FSR — заметно чётче простого растяжения
	get_tree().root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	get_tree().root.msaa_3d = Viewport.MSAA_DISABLED if quality == 0 else Viewport.MSAA_2X
	get_tree().call_group("graphics_quality", "apply_quality", quality)
	if shadows > 0:
		RenderingServer.directional_shadow_atlas_set_size(SHADOW_SIZES[shadows], true)
	get_tree().call_group("shadow_lights", "set", "shadow_enabled", shadows > 0)
	_set_bus("Master", master_volume)
	_set_bus("Ambience", ambience_volume)
	_set_bus("Effects", effects_volume)
	changed.emit()


func save() -> void:
	# Без окна (автотесты, сервер) настройки игрока не трогаем
	if DisplayServer.get_name() == "headless":
		return
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("video", "vsync", vsync)
	config.set_value("video", "max_fps", max_fps)
	config.set_value("video", "render_scale", render_scale)
	config.set_value("video", "shadows", shadows)
	config.set_value("video", "quality", quality)
	config.set_value("video", "fov", fov)
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "ambience", ambience_volume)
	config.set_value("audio", "effects", effects_volume)
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("controls", "invert_y", invert_y)
	config.save(PATH)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	fullscreen = config.get_value("video", "fullscreen", fullscreen)
	vsync = config.get_value("video", "vsync", vsync)
	max_fps = config.get_value("video", "max_fps", max_fps)
	render_scale = config.get_value("video", "render_scale", render_scale)
	shadows = config.get_value("video", "shadows", shadows)
	quality = config.get_value("video", "quality", quality)
	fov = config.get_value("video", "fov", fov)
	master_volume = config.get_value("audio", "master", master_volume)
	ambience_volume = config.get_value("audio", "ambience", ambience_volume)
	effects_volume = config.get_value("audio", "effects", effects_volume)
	mouse_sensitivity = config.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	invert_y = config.get_value("controls", "invert_y", invert_y)


func _set_bus(bus: String, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))
