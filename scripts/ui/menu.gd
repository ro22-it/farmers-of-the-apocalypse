class_name Menu
extends CanvasLayer

## Главное меню поверх фермы и пауза по Esc во время игры.
## Как и HUD, собирается из кода.

signal host_pressed
signal continue_pressed
signal join_pressed(address: String)
signal leave_pressed

const PANEL_BG := Color(0.08, 0.1, 0.08, 0.85)
const ACCENT := Color(0.93, 0.5, 0.12)
const HELP_TEXT := "Порт 7777 (UDP). Друзьям нужен ваш IP: в одной сети — локальный,\nчерез интернет — IP из Tailscale (или проброс порта на роутере)."

var _main_panel: Control
var _pause_panel: Control
var _name_edit: LineEdit
var _address_edit: LineEdit
var _class_option: OptionButton
var _class_description: Label
var _class_preview: ClassPreview
var _tutorial_check: CheckBox
var _status: Label
var _buttons: Array[Button] = []
var _in_session := false
var _settings_panel: SettingsPanel
var _continue_button: Button
var _records: Label


func _ready() -> void:
	_main_panel = _build_main()
	_pause_panel = _build_pause()
	_settings_panel = SettingsPanel.new()
	add_child(_settings_panel)
	_settings_panel.hide()
	_settings_panel.closed.connect(_on_settings_closed)
	show_main("")


func _unhandled_input(event: InputEvent) -> void:
	if not _in_session or not event.is_action_pressed("ui_cancel"):
		return
	if _pause_panel.visible:
		_resume()
	else:
		_pause_panel.show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_viewport().set_input_as_handled()


func show_main(status: String) -> void:
	_in_session = false
	# «Продолжить» — только если есть сохранение
	var saved := SaveSystem.info()
	_continue_button.visible = saved != ""
	_continue_button.text = "Продолжить (%s)" % saved
	_pause_panel.hide()
	_main_panel.show()
	_set_busy(false)
	_status.text = status
	var meta := RunDirector.load_meta()
	_records.text = RunDirector.meta_line(meta)
	var locked := []
	for id in RunDirector.CLASS_UNLOCKS:
		if not RunDirector.class_unlocked(id, meta):
			locked.append("%s — ночь %d" % [PlayerClasses.display_name(id), RunDirector.CLASS_UNLOCKS[id]])
	if not locked.is_empty():
		_records.text += "\nЗакрыты: " + ", ".join(locked)
	if _class_option:
		_fill_classes()
		_on_class_selected(_class_option.selected)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func show_connecting(text: String) -> void:
	_set_busy(true)
	_status.text = text


func enter_session() -> void:
	_in_session = true
	_main_panel.hide()
	_pause_panel.hide()


func _open_settings() -> void:
	_main_panel.hide()
	_pause_panel.hide()
	_settings_panel.show()


func _on_settings_closed() -> void:
	if _in_session:
		_pause_panel.show()
	else:
		_main_panel.show()


## Твари, которых вы встречали, и их слабости; остальные — под вопросом
func _open_bestiary() -> void:
	var seen := RunDirector.seen_creatures()
	var lines := []
	for scene: PackedScene in [NightDirector.GRYADOCHNIK, NightDirector.TARAN, NightDirector.ROJ, NightDirector.PUGALSHIK, NightDirector.KUKURUZNIK, NightDirector.FOREST_LORD]:
		var creature: Node = scene.instantiate()
		var known: bool = creature.display_name in seen
		lines.append("• %s — %s" % [creature.display_name, creature.weakness] if known else "• ??? — ещё не встречали")
		creature.free()
	var dialog := AcceptDialog.new()
	dialog.title = "Бестиарий (%d из 6)" % seen.size()
	dialog.dialog_text = "\n\n".join(lines)
	dialog.ok_button_text = "Закрыть"
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(640, 0))


func is_paused() -> bool:
	return _pause_panel.visible


func _resume() -> void:
	_pause_panel.hide()
	get_tree().call_group("local_player", "capture_mouse")


func _set_busy(busy: bool) -> void:
	for button in _buttons:
		button.disabled = busy


## Список классов: закрытые помечены замком и выбрать их нельзя
func _fill_classes() -> void:
	var meta := RunDirector.load_meta()
	_class_option.clear()
	for id in PlayerClasses.ORDER:
		var unlocked := RunDirector.class_unlocked(id, meta)
		_class_option.add_item(PlayerClasses.display_name(id) + ("" if unlocked else " 🔒"))
		_class_option.set_item_disabled(_class_option.item_count - 1, not unlocked)
	var current := PlayerClasses.ORDER.find(Network.player_class)
	if current < 0 or not RunDirector.class_unlocked(Network.player_class, meta):
		current = 0
	_class_option.select(current)


func _on_class_selected(index: int) -> void:
	Network.player_class = PlayerClasses.ORDER[index]
	_class_description.text = PlayerClasses.get_info(Network.player_class).description
	_class_preview.show_class(Network.player_class)


func _on_continue() -> void:
	Network.player_name = Network.clean_name(_name_edit.text)
	Network.save_settings()
	continue_pressed.emit()


func _on_host() -> void:
	Network.player_name = Network.clean_name(_name_edit.text)
	Network.save_settings()
	host_pressed.emit()


func _on_join() -> void:
	Network.player_name = Network.clean_name(_name_edit.text)
	var address := _address_edit.text.strip_edges()
	if address == "":
		_status.text = "Введите IP хоста"
		return
	Network.last_address = address
	Network.save_settings()
	join_pressed.emit(address)


func _build_main() -> Control:
	var center := _make_center(self)
	# Слева — предпросмотр выбранного персонажа, справа — само меню
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	center.add_child(row)
	_class_preview = ClassPreview.new(PANEL_BG)
	_class_preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_class_preview)
	var box := _make_panel(row, 460)

	var title := _make_label("Фермеры апокалипсиса", 34)
	title.add_theme_color_override("font_color", ACCENT)
	box.add_child(title)
	box.add_child(_make_label("кооп на 2–4 игроков", 16))
	_records = _make_label("", 13)
	_records.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_records.modulate.a = 0.75
	box.add_child(_records)

	box.add_child(_make_label("Имя", 16, HORIZONTAL_ALIGNMENT_LEFT))
	_name_edit = _make_edit(Network.player_name, "Фермер")
	_name_edit.max_length = Network.MAX_NAME_LENGTH
	box.add_child(_name_edit)

	box.add_child(_make_label("Класс", 16, HORIZONTAL_ALIGNMENT_LEFT))
	_class_option = OptionButton.new()
	_class_option.add_theme_font_size_override("font_size", 18)
	_class_option.custom_minimum_size = Vector2(0, 40)
	_fill_classes()
	_class_option.item_selected.connect(_on_class_selected)
	box.add_child(_class_option)
	_class_description = _make_label("", 14, HORIZONTAL_ALIGNMENT_LEFT)
	_class_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_class_description.modulate.a = 0.85
	box.add_child(_class_description)
	_on_class_selected(_class_option.selected)

	_tutorial_check = CheckBox.new()
	_tutorial_check.text = "Обучение для новичков"
	_tutorial_check.add_theme_font_size_override("font_size", 16)
	_tutorial_check.button_pressed = Network.tutorial_enabled
	_tutorial_check.toggled.connect(func(on: bool): Network.tutorial_enabled = on)
	box.add_child(_tutorial_check)

	_continue_button = _make_button("Продолжить", _on_continue)
	box.add_child(_continue_button)
	var host_button := _make_button("Новая игра", _on_host)
	box.add_child(host_button)

	box.add_child(_make_label("IP хоста", 16, HORIZONTAL_ALIGNMENT_LEFT))
	_address_edit = _make_edit(Network.last_address, "например, 100.64.0.2")
	_address_edit.text_submitted.connect(func(_t): _on_join())
	box.add_child(_address_edit)
	box.add_child(_make_button("Подключиться", _on_join))

	_status = _make_label("", 16)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	box.add_child(_status)

	box.add_child(_make_button("Бестиарий", _open_bestiary, false))
	box.add_child(_make_button("Настройки", _open_settings))
	box.add_child(_make_button("Выход", func(): get_tree().quit()))
	var help := _make_label(HELP_TEXT, 13)
	help.modulate.a = 0.7
	box.add_child(help)
	return center


func _build_pause() -> Control:
	# Полупрозрачный фон на весь экран, чтобы клики мимо кнопок не уходили в игру
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.4)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := _make_panel(_make_center(shade), 320)
	box.add_child(_make_label("Пауза", 30))
	box.add_child(_make_button("Продолжить", _resume, false))
	box.add_child(_make_button("Настройки", _open_settings, false))
	box.add_child(_make_button("Выйти в меню", func(): leave_pressed.emit(), false))
	box.add_child(_make_button("Выйти из игры", func(): get_tree().quit(), false))
	return shade


## Контейнер на весь экран, который держит панель по центру при любом размере окна.
func _make_center(parent: Node) -> CenterContainer:
	var center := CenterContainer.new()
	parent.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return center


## Панель с вертикальным списком внутри. Возвращает список, куда класть элементы.
func _make_panel(parent: Control, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_corner_radius_all(10)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(width, 0)
	parent.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	return box


func _make_label(text: String, font_size: int, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _make_edit(text: String, placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.placeholder_text = placeholder
	edit.add_theme_font_size_override("font_size", 18)
	edit.custom_minimum_size = Vector2(0, 40)
	return edit


func _make_button(text: String, callback: Callable, lockable := true) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 20)
	button.custom_minimum_size = Vector2(0, 46)
	button.pressed.connect(callback)
	button.pressed.connect(func(): SoundBank.play_ui(get_tree(), "ui_click"))
	if lockable:
		_buttons.append(button)
	return button
