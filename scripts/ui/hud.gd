class_name Hud
extends CanvasLayer

## Интерфейс игрока: прицел, подсказка, сообщения, слоты инвентаря, выносливость,
## часы, монеты и меню лавки.
## Собирается из кода, чтобы не держать громоздкую сцену ради прототипа.

signal buy_pressed(id: String)

const SLOT_BG := Color(0.0, 0.0, 0.0, 0.45)
const SLOT_BORDER := Color(1.0, 0.85, 0.4)
const STAMINA_COLOR := Color(0.95, 0.85, 0.35)
const EXHAUSTED_COLOR := Color(0.9, 0.3, 0.25)
const MESSAGE_TIME := 2.5
const CONTROLS_TEXT := "WASD — ходьба   Shift — бег   Ctrl — присесть   Пробел — прыжок\nЛКМ — тащить / использовать   ПКМ — бросить   E — взять   G — выбросить\n1–4, колесо — слоты   Esc — пауза   F1 — скрыть подсказку"

var _hint: Label
var _clock: Label
var _money: Label
var _shop: Control
var _shop_list: VBoxContainer
var _shop_money: Label
var _message: Label
var _message_left := 0.0
var _controls: Label
var _stamina: ProgressBar
var _stamina_fill: StyleBoxFlat
var _slot_panels: Array[PanelContainer] = []
var _slot_labels: Array[Label] = []
var _slot_style: StyleBoxFlat
var _slot_selected_style: StyleBoxFlat


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var crosshair := ColorRect.new()
	crosshair.color = Color(1.0, 1.0, 1.0, 0.85)
	crosshair.custom_minimum_size = Vector2(4, 4)
	root.add_child(crosshair)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)

	_hint = _make_label(20)
	root.add_child(_hint)
	_hint.set_anchors_preset(Control.PRESET_CENTER)
	_hint.offset_left = -400
	_hint.offset_right = 400
	_hint.offset_top = 24
	_hint.offset_bottom = 54

	_message = _make_label(26)
	root.add_child(_message)
	_message.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_message.offset_top = 90
	_message.offset_bottom = 80

	_controls = _make_label(14)
	_controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(_controls)
	_controls.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_controls.offset_left = 16
	_controls.offset_top = 12
	_controls.text = CONTROLS_TEXT

	_clock = _make_label(20)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_clock)
	_clock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_clock.offset_left = -300
	_clock.offset_right = -16
	_clock.offset_top = 12
	_clock.offset_bottom = 40

	_money = _make_label(18)
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	root.add_child(_money)
	_money.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_money.offset_left = -300
	_money.offset_right = -16
	_money.offset_top = 40
	_money.offset_bottom = 66

	_build_slots(root)
	_build_stamina(root)
	# Захваченный курсор стоит в центре экрана, прямо над прицелом.
	# Если интерфейс ловит мышь, движения не доходят до камеры игрока.
	_ignore_mouse(root)
	# Лавка ловит мышь, поэтому собирается после и отдельно от остального
	_build_shop()


func _process(delta: float) -> void:
	if _message_left > 0.0:
		_message_left -= delta
		_message.modulate.a = clampf(_message_left, 0.0, 1.0)


func _input(event: InputEvent) -> void:
	# Esc закрывает лавку раньше, чем меню паузы успеет его перехватить
	if is_shop_open() and event.is_action_pressed("ui_cancel"):
		close_shop()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		_controls.visible = not _controls.visible


func set_hint(text: String) -> void:
	_hint.text = text


func set_money(amount: int) -> void:
	_money.text = "Монеты: %d" % amount
	_shop_money.text = "У команды %d монет" % amount


func open_shop(items: Array) -> void:
	for child in _shop_list.get_children():
		child.queue_free()
	for entry in items:
		var row := HBoxContainer.new()
		var title := Label.new()
		title.text = entry.name
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_theme_font_size_override("font_size", 18)
		row.add_child(title)
		var button := Button.new()
		button.text = "Купить за %d" % entry.price
		button.custom_minimum_size = Vector2(170, 38)
		button.add_theme_font_size_override("font_size", 16)
		var id: String = entry.id
		button.pressed.connect(func(): buy_pressed.emit(id))
		row.add_child(button)
		_shop_list.add_child(row)
	_shop.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_shop() -> void:
	_shop.hide()
	get_tree().call_group("local_player", "capture_mouse")


func is_shop_open() -> bool:
	return _shop.visible


func set_clock(text: String) -> void:
	_clock.text = text


func show_message(text: String) -> void:
	_message.text = text
	_message_left = MESSAGE_TIME
	_message.modulate.a = 1.0


func set_stamina(ratio: float, exhausted: bool) -> void:
	_stamina.value = ratio * 100.0
	_stamina.visible = ratio < 0.999
	_stamina_fill.bg_color = EXHAUSTED_COLOR if exhausted else STAMINA_COLOR


func update_inventory(inventory: Inventory) -> void:
	for i in Inventory.SIZE:
		var slot: Dictionary = inventory.slots[i]
		_slot_labels[i].text = "%d\n%s" % [i + 1, slot.get("name", "—")]
		var style := _slot_selected_style if i == inventory.selected else _slot_style
		_slot_panels[i].add_theme_stylebox_override("panel", style)


func _build_shop() -> void:
	_shop = CenterContainer.new()
	# Клики мимо панели не должны уходить в игру
	_shop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shop)
	_shop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.06, 0.92)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(520, 0)
	_shop.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := _make_label(28)
	title.text = "Лавка старого торговца"
	title.add_theme_color_override("font_color", Color(0.93, 0.5, 0.12))
	box.add_child(title)
	_shop_money = _make_label(16)
	box.add_child(_shop_money)
	_shop_list = VBoxContainer.new()
	_shop_list.add_theme_constant_override("separation", 6)
	box.add_child(_shop_list)
	var close := Button.new()
	close.text = "Уйти (Esc)"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(close_shop)
	box.add_child(close)
	_shop.hide()


func _build_slots(root: Control) -> void:
	_slot_style = _make_slot_style(Color(1.0, 1.0, 1.0, 0.15))
	_slot_selected_style = _make_slot_style(SLOT_BORDER)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.offset_left = -240
	row.offset_right = 240
	row.offset_top = -86
	row.offset_bottom = -24

	for i in Inventory.SIZE:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(110, 56)
		var label := _make_label(15)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		panel.add_child(label)
		row.add_child(panel)
		_slot_panels.append(panel)
		_slot_labels.append(label)


func _build_stamina(root: Control) -> void:
	_stamina = ProgressBar.new()
	_stamina.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	_stamina_fill = StyleBoxFlat.new()
	_stamina_fill.bg_color = STAMINA_COLOR
	_stamina.add_theme_stylebox_override("background", bg)
	_stamina.add_theme_stylebox_override("fill", _stamina_fill)
	root.add_child(_stamina)
	_stamina.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stamina.offset_left = -120
	_stamina.offset_right = 120
	_stamina.offset_top = -100
	_stamina.offset_bottom = -94


func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_ignore_mouse(child)


func _make_slot_style(border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = SLOT_BG
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(6)
	return style


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
