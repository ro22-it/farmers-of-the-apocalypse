class_name TouchControls
extends CanvasLayer

## Сенсорное управление для телефона: слева — джойстик ходьбы (появляется
## под пальцем), справа — обзор пальцем и круглые кнопки действий.
## Кнопки нажимают те же действия ввода, что клавиатура и мышь, так что
## остальная игра про телефон ничего не знает.

const JOYSTICK_RADIUS := 110.0
## Доля ширины экрана слева, где палец берёт джойстик
const JOYSTICK_ZONE := 0.42
const FILL := Color(1, 1, 1, 0.16)
const FILL_PRESSED := Color(1, 0.75, 0.3, 0.45)
const OUTLINE := Color(1, 1, 1, 0.45)

## Кнопки: подпись, действие, смещение от правого нижнего угла, радиус, держать ли.
## Верхний ряд — от правого верхнего угла (y < 0 значит «сверху»), левее часов и обучения.
const BUTTONS := [
	["Прыжок", "jump", Vector2(130, 150), 72, false],
	["Удар", "primary", Vector2(300, 250), 66, true],
	["Бросок", "throw", Vector2(150, 340), 54, true],
	["Взять", "pickup", Vector2(440, 130), 52, false],
	["Бег", "sprint", Vector2(300, 90), 46, true],
	["Присесть", "crouch", Vector2(580, 110), 44, true],
	["Выбросить", "drop", Vector2(450, 300), 44, false],
	["Пауза", "ui_cancel", Vector2(450, -70), 38, false],
	["Навыки", "skills", Vector2(550, -70), 38, false],
	["Q", "ability", Vector2(650, -70), 38, false],
	["Перезар.", "reload", Vector2(750, -70), 38, false],
	["Слот", "slot_next", Vector2(850, -70), 38, false],
	["Вид", "camera_toggle", Vector2(950, -70), 38, false],
]

var _canvas: Control
## Палец -> что он делает: "joystick", "look" или индекс кнопки
var _touches := {}
var _joystick_center := Vector2.ZERO
var _joystick_offset := Vector2.ZERO
var _pressed := {}


## Включать ли сенсор: на телефоне или с флагом --touch для отладки
static func wanted() -> bool:
	return OS.has_feature("mobile") or "--touch" in OS.get_cmdline_user_args()


func _ready() -> void:
	layer = 5
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)


func _process(_delta: float) -> void:
	var player := _player()
	var active := player != null and not player.hud.is_panel_open() and not _menu_paused()
	if player:
		player.touch_mode = true
		# Подсказки про клавиатуру на телефоне ни к чему
		player.hud.hide_controls_help()
	if active != visible:
		visible = active
		if not active:
			_release_all()
	_canvas.queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		_touch_move(event.index, event.position, event.relative)


func _touch_down(index: int, position: Vector2) -> void:
	var button := _button_at(position)
	if button >= 0:
		_touches[index] = button
		_press(button, true)
		return
	if position.x < _size().x * JOYSTICK_ZONE:
		_touches[index] = "joystick"
		_joystick_center = position
		_joystick_offset = Vector2.ZERO
	else:
		_touches[index] = "look"


func _touch_move(index: int, position: Vector2, relative: Vector2) -> void:
	match _touches.get(index):
		"joystick":
			_joystick_offset = (position - _joystick_center).limit_length(JOYSTICK_RADIUS)
			_apply_joystick()
		"look":
			var player := _player()
			if player:
				player.touch_look(relative)


func _touch_up(index: int) -> void:
	var what = _touches.get(index)
	_touches.erase(index)
	if what is int:
		_press(what, false)
	elif what == "joystick":
		_joystick_offset = Vector2.ZERO
		_apply_joystick()


func _apply_joystick() -> void:
	var v := _joystick_offset / JOYSTICK_RADIUS
	_set_strength("move_right", maxf(v.x, 0.0))
	_set_strength("move_left", maxf(-v.x, 0.0))
	_set_strength("move_back", maxf(v.y, 0.0))
	_set_strength("move_forward", maxf(-v.y, 0.0))


func _set_strength(action: String, strength: float) -> void:
	if strength > 0.05:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


## Нажатие кнопки — как нажатие клавиши: и состояние Input, и событие для обработчиков
func _press(button: int, down: bool) -> void:
	var action: String = BUTTONS[button][1]
	var hold: bool = BUTTONS[button][4]
	if not down and not hold:
		_pressed.erase(button)
		return
	if down:
		_pressed[button] = true
	else:
		_pressed.erase(button)
	var event := InputEventAction.new()
	event.action = action
	event.pressed = down
	Input.parse_input_event(event)
	# Кнопка без удержания сразу «отпускается»
	if down and not hold:
		var release := InputEventAction.new()
		release.action = action
		release.pressed = false
		Input.parse_input_event.call_deferred(release)


func _release_all() -> void:
	for index in _touches.keys():
		_touch_up(index)
	_touches.clear()
	for action in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(action)


func _button_at(position: Vector2) -> int:
	for i in BUTTONS.size():
		if position.distance_to(_button_center(i)) <= BUTTONS[i][3]:
			return i
	return -1


func _button_center(i: int) -> Vector2:
	var offset: Vector2 = BUTTONS[i][2]
	var size := _size()
	if offset.y < 0.0:
		return Vector2(size.x - offset.x, -offset.y)
	return size - offset


func _size() -> Vector2:
	return _canvas.get_viewport_rect().size


func _draw_controls() -> void:
	var font := ThemeDB.fallback_font
	for i in BUTTONS.size():
		var center := _button_center(i)
		var radius: float = BUTTONS[i][3]
		_canvas.draw_circle(center, radius, FILL_PRESSED if _pressed.has(i) else FILL)
		_canvas.draw_arc(center, radius, 0.0, TAU, 40, OUTLINE, 2.0, true)
		var text: String = BUTTONS[i][0]
		var font_size := 18 if radius > 45 else 14
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
		_canvas.draw_string(font, center + Vector2(-width / 2.0, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.9))
	# Джойстик: где палец — там и он; без пальца — подсказка на привычном месте
	var base := _joystick_center if _touches.values().has("joystick") else Vector2(200, _size().y - 200)
	_canvas.draw_circle(base, JOYSTICK_RADIUS, FILL)
	_canvas.draw_arc(base, JOYSTICK_RADIUS, 0.0, TAU, 48, OUTLINE, 2.0, true)
	_canvas.draw_circle(base + _joystick_offset, 46, Color(1, 1, 1, 0.35))


func _player() -> Player:
	return get_tree().get_first_node_in_group("local_player") as Player


func _menu_paused() -> bool:
	# Без типа Menu: его скрипт зовёт автозагрузку Network, а её нет в автотестах
	var menu := get_tree().current_scene.get_node_or_null("Menu")
	return menu != null and menu.call("is_paused")
