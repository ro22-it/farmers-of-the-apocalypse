class_name SettingsPanel
extends CenterContainer

## Окно настроек: экран, графика, звук, управление. Любое изменение сразу
## применяется и сохраняется. Открывается из главного меню и из паузы.

signal closed

const FPS_NAMES := ["Без ограничения", "30", "60", "120", "144"]
const SHADOW_NAMES := ["Выключены", "Простые", "Чёткие"]

var _settings: Node


func _ready() -> void:
	_settings = get_node("/root/Settings")
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.08, 0.94)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(22)
	frame.add_theme_stylebox_override("panel", style)
	frame.custom_minimum_size = Vector2(560, 0)
	add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	frame.add_child(box)

	box.add_child(_title("Настройки", 28))
	box.add_child(_title("Экран и графика", 18))
	box.add_child(_check("Полный экран (F11)", "fullscreen"))
	box.add_child(_option("Качество графики", ["Низкое", "Среднее", "Высокое"], _settings.quality, func(i: int): _change("quality", i)))
	box.add_child(_check("Вертикальная синхронизация", "vsync"))
	box.add_child(_option("Ограничение кадров", FPS_NAMES, _settings.FPS_CHOICES.find(_settings.max_fps), func(i: int): _change("max_fps", _settings.FPS_CHOICES[i])))
	box.add_child(_option("Тени", SHADOW_NAMES, _settings.shadows, func(i: int): _change("shadows", i)))
	box.add_child(_slider("Масштаб отрисовки (для слабых ПК)", "render_scale", 0.5, 1.0, 0.05, func(v): return "%d%%" % roundi(v * 100.0)))
	box.add_child(_slider("Поле зрения", "fov", 60.0, 110.0, 1.0, func(v): return "%d°" % roundi(v)))
	box.add_child(_title("Звук", 18))
	box.add_child(_slider("Общая громкость", "master_volume", 0.0, 1.0, 0.05, _percent))
	box.add_child(_slider("Фон: лес и ночь", "ambience_volume", 0.0, 1.0, 0.05, _percent))
	box.add_child(_slider("Эффекты", "effects_volume", 0.0, 1.0, 0.05, _percent))
	box.add_child(_title("Управление", 18))
	box.add_child(_slider("Чувствительность мыши", "mouse_sensitivity", 0.2, 3.0, 0.1, func(v): return "×%.1f" % v))
	box.add_child(_check("Инвертировать мышь по вертикали", "invert_y"))

	var back := Button.new()
	back.text = "Назад"
	back.custom_minimum_size = Vector2(0, 42)
	back.add_theme_font_size_override("font_size", 18)
	back.pressed.connect(func():
		hide()
		closed.emit())
	box.add_child(back)


func _change(key: String, value: Variant) -> void:
	_settings.set(key, value)
	_settings.apply()
	_settings.save()


static func _percent(value: float) -> String:
	return "%d%%" % roundi(value * 100.0)


func _title(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.93, 0.5, 0.12) if size > 20 else Color(1.0, 0.8, 0.45))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if size > 20 else HORIZONTAL_ALIGNMENT_LEFT
	return label


func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 16)
	row.add_child(label)
	return row


func _check(text: String, key: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.add_theme_font_size_override("font_size", 16)
	check.button_pressed = _settings.get(key)
	check.toggled.connect(func(on: bool): _change(key, on))
	return check


func _option(text: String, names: Array, selected: int, on_select: Callable) -> HBoxContainer:
	var row := _row(text)
	var option := OptionButton.new()
	for name in names:
		option.add_item(name)
	option.select(maxi(selected, 0))
	option.custom_minimum_size = Vector2(200, 0)
	option.item_selected.connect(on_select)
	row.add_child(option)
	return row


func _slider(text: String, key: String, from: float, to: float, step: float, format: Callable) -> HBoxContainer:
	var row := _row(text)
	var slider := HSlider.new()
	slider.min_value = from
	slider.max_value = to
	slider.step = step
	slider.value = _settings.get(key)
	slider.custom_minimum_size = Vector2(160, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(70, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = format.call(slider.value)
	slider.value_changed.connect(func(value: float):
		value_label.text = format.call(value)
		_change(key, value))
	row.add_child(slider)
	row.add_child(value_label)
	return row
