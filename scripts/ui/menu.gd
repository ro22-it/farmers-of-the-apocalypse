class_name Menu
extends CanvasLayer

## Главное меню поверх фермы и пауза по Esc во время игры.
## Как и HUD, собирается из кода.

signal host_pressed
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
var _status: Label
var _buttons: Array[Button] = []
var _in_session := false


func _ready() -> void:
	_main_panel = _build_main()
	_pause_panel = _build_pause()
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
	_pause_panel.hide()
	_main_panel.show()
	_set_busy(false)
	_status.text = status
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func show_connecting(text: String) -> void:
	_set_busy(true)
	_status.text = text


func enter_session() -> void:
	_in_session = true
	_main_panel.hide()
	_pause_panel.hide()


func _resume() -> void:
	_pause_panel.hide()
	get_tree().call_group("local_player", "capture_mouse")


func _set_busy(busy: bool) -> void:
	for button in _buttons:
		button.disabled = busy


func _on_class_selected(index: int) -> void:
	Network.player_class = PlayerClasses.ORDER[index]
	_class_description.text = PlayerClasses.get_info(Network.player_class).description


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
	var box := _make_panel(center, 460)

	var title := _make_label("Фермеры апокалипсиса", 34)
	title.add_theme_color_override("font_color", ACCENT)
	box.add_child(title)
	box.add_child(_make_label("кооп на 2–4 игроков", 16))

	box.add_child(_make_label("Имя", 16, HORIZONTAL_ALIGNMENT_LEFT))
	_name_edit = _make_edit(Network.player_name, "Фермер")
	_name_edit.max_length = Network.MAX_NAME_LENGTH
	box.add_child(_name_edit)

	box.add_child(_make_label("Класс", 16, HORIZONTAL_ALIGNMENT_LEFT))
	_class_option = OptionButton.new()
	_class_option.add_theme_font_size_override("font_size", 18)
	_class_option.custom_minimum_size = Vector2(0, 40)
	for id in PlayerClasses.ORDER:
		_class_option.add_item(PlayerClasses.display_name(id))
	_class_option.select(maxi(PlayerClasses.ORDER.find(Network.player_class), 0))
	_class_option.item_selected.connect(_on_class_selected)
	box.add_child(_class_option)
	_class_description = _make_label("", 14, HORIZONTAL_ALIGNMENT_LEFT)
	_class_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_class_description.modulate.a = 0.85
	box.add_child(_class_description)
	_on_class_selected(_class_option.selected)

	var host_button := _make_button("Создать игру", _on_host)
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
	if lockable:
		_buttons.append(button)
	return button
