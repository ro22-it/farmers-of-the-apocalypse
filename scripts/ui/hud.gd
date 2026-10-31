class_name Hud
extends CanvasLayer

## Интерфейс игрока: прицел, подсказка, сообщения, слоты инвентаря, выносливость,
## часы, монеты и меню лавки.
## Собирается из кода, чтобы не держать громоздкую сцену ради прототипа.

signal panel_action(kind: String, id: String)

const SLOT_BG := Color(0.0, 0.0, 0.0, 0.45)
const SLOT_BORDER := Color(1.0, 0.85, 0.4)
const STAMINA_COLOR := Color(0.95, 0.85, 0.35)
const EXHAUSTED_COLOR := Color(0.9, 0.3, 0.25)
const MESSAGE_TIME := 2.5
const CONTROLS_TEXT := "WASD — ходьба   Shift — бег   Ctrl — присесть   Пробел — прыжок\nЛКМ — тащить / использовать   ПКМ — бросить   E — взять   G — выбросить\n1–4, колесо — слоты   ПКМ с оружием — прицел   R — перезарядка   Q — способность   K — навыки   Esc — пауза   F1 — скрыть подсказку   F2 — к закату или рассвету"

var _hint: Label
var _clock: Label
var _money: Label
var _ability: Label
var _health: ProgressBar
var _health_fill: StyleBoxFlat
var _ammo: Label
var _damage_flash: ColorRect
var _downed_text: Label
var _tutorial: PanelContainer
var _tutorial_title: Label
var _tutorial_text: Label
var _panel: Control
var _panel_title: Label
var _panel_subtitle: Label
var _panel_list: VBoxContainer
var _panel_kind := ""
var _money_amount := 0
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

	_ability = _make_label(16)
	_ability.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(_ability)
	_ability.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_ability.offset_left = 16
	_ability.offset_right = 420
	_ability.offset_top = -64
	_ability.offset_bottom = -16

	_build_slots(root)
	_build_stamina(root)
	_build_combat(root)
	_build_tutorial(root)
	# Захваченный курсор стоит в центре экрана, прямо над прицелом.
	# Если интерфейс ловит мышь, движения не доходят до камеры игрока.
	_ignore_mouse(root)
	# Окно-список ловит мышь, поэтому собирается после и отдельно от остального
	_build_panel()


func _process(delta: float) -> void:
	if _damage_flash.color.a > 0.0 and not _downed_text.visible:
		_damage_flash.color.a = maxf(_damage_flash.color.a - delta * 0.8, 0.0)
	if _message_left > 0.0:
		_message_left -= delta
		_message.modulate.a = clampf(_message_left, 0.0, 1.0)


func _input(event: InputEvent) -> void:
	# Esc закрывает окно раньше, чем меню паузы успеет его перехватить
	if is_panel_open() and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


func hide_controls_help() -> void:
	_controls.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		_controls.visible = not _controls.visible
	elif event.is_action_pressed("toggle_tutorial") and _tutorial_title.text != "":
		_tutorial.visible = not _tutorial.visible


func set_hint(text: String) -> void:
	_hint.text = text


func set_money(amount: int) -> void:
	_money.text = "Монеты: %d" % amount
	if amount != _money_amount:
		_money_amount = amount
		if _panel_kind == "shop" or _panel_kind == "upgrade":
			_panel_subtitle.text = _money_line()


func _money_line() -> String:
	return "У команды %d монет" % _money_amount


func set_health(ratio: float, is_downed: bool) -> void:
	_health.value = ratio * 100.0
	_health_fill.bg_color = Color(0.85, 0.2, 0.2) if ratio < 0.35 else Color(0.85, 0.35, 0.3)
	_downed_text.visible = is_downed
	if is_downed:
		_damage_flash.color.a = maxf(_damage_flash.color.a, 0.35)


func set_ammo(text: String) -> void:
	_ammo.text = text


## Красная вспышка по краям экрана при ударе
func flash_damage() -> void:
	_damage_flash.color.a = 0.45


## Панель обучения. Пустой заголовок — спрятать
func set_tutorial(title: String, text: String) -> void:
	_tutorial_title.text = title
	_tutorial_text.text = text
	_tutorial.visible = title != ""


func set_ability(text: String) -> void:
	_ability.text = text


## Окно-список с кнопками: лавка, улучшения фермы, навыки.
## rows: [{text, button, id, disabled}] или {header: true, text} для заголовка.
func open_panel(kind: String, title: String, subtitle: String, rows: Array) -> void:
	_panel_kind = kind
	_panel_title.text = title
	_panel_subtitle.text = subtitle
	for child in _panel_list.get_children():
		_panel_list.remove_child(child)
		child.queue_free()
	for row in rows:
		if row.get("header", false):
			var header := _make_label(19)
			header.text = row.text
			header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			header.add_theme_color_override("font_color", Color(1.0, 0.8, 0.45))
			_panel_list.add_child(header)
			continue
		var line := HBoxContainer.new()
		var text := Label.new()
		text.text = row.text
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_theme_font_size_override("font_size", 16)
		line.add_child(text)
		# Строка без кнопки — просто текст (итоги забега)
		if row.get("button", "") == "":
			_panel_list.add_child(line)
			continue
		var button := Button.new()
		button.text = row.button
		button.disabled = row.get("disabled", false)
		button.custom_minimum_size = Vector2(170, 38)
		button.add_theme_font_size_override("font_size", 16)
		var id: String = row.get("id", "")
		button.pressed.connect(func(): panel_action.emit(kind, id))
		line.add_child(button)
		_panel_list.add_child(line)
	_panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_panel() -> void:
	_panel.hide()
	_panel_kind = ""
	get_tree().call_group("local_player", "capture_mouse")


func is_panel_open() -> bool:
	return _panel.visible


func panel_kind() -> String:
	return _panel_kind


func open_shop(items: Array, player_class: String, kind := "shop", title := "Лавка старого торговца") -> void:
	var rows := []
	var verb := "Собрать за %d" if kind == "workbench" else "Купить за %d"
	for entry in items:
		rows.append({"text": entry.name, "button": verb % PlayerClasses.shop_price(player_class, entry), "id": entry.id})
	open_panel(kind, title, _money_line(), rows)


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


func _build_panel() -> void:
	_panel = CenterContainer.new()
	# Клики мимо окна не должны уходить в игру
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.06, 0.92)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(22)
	frame.add_theme_stylebox_override("panel", style)
	frame.custom_minimum_size = Vector2(620, 0)
	_panel.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	frame.add_child(box)

	_panel_title = _make_label(28)
	_panel_title.add_theme_color_override("font_color", Color(0.93, 0.5, 0.12))
	box.add_child(_panel_title)
	_panel_subtitle = _make_label(16)
	box.add_child(_panel_subtitle)
	_panel_list = VBoxContainer.new()
	_panel_list.add_theme_constant_override("separation", 6)
	box.add_child(_panel_list)
	var close := Button.new()
	close.text = "Закрыть (Esc)"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(close_panel)
	box.add_child(close)
	_panel.hide()


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


func _build_combat(root: Control) -> void:
	_damage_flash = ColorRect.new()
	_damage_flash.color = Color(0.7, 0.0, 0.0, 0.0)
	root.add_child(_damage_flash)
	root.move_child(_damage_flash, 0)
	_damage_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_downed_text = _make_label(30)
	_downed_text.text = "Вы без сознания\nждите, пока товарищ поднимет (E), или рассвета"
	_downed_text.add_theme_color_override("font_color", Color(1.0, 0.75, 0.7))
	root.add_child(_downed_text)
	_downed_text.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_downed_text.offset_left = -400
	_downed_text.offset_right = 400
	_downed_text.offset_top = 160
	_downed_text.visible = false

	_health = ProgressBar.new()
	_health.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	background.set_corner_radius_all(3)
	_health_fill = StyleBoxFlat.new()
	_health_fill.bg_color = Color(0.85, 0.35, 0.3)
	_health_fill.set_corner_radius_all(3)
	_health.add_theme_stylebox_override("background", background)
	_health.add_theme_stylebox_override("fill", _health_fill)
	root.add_child(_health)
	_health.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_health.offset_left = 16
	_health.offset_right = 236
	_health.offset_top = -82
	_health.offset_bottom = -70

	_ammo = _make_label(17)
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_ammo)
	_ammo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo.offset_left = -520
	_ammo.offset_right = -16
	_ammo.offset_top = -48
	_ammo.offset_bottom = -20


func _build_tutorial(root: Control) -> void:
	_tutorial = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.08, 0.75)
	style.border_color = Color(0.93, 0.5, 0.12)
	style.border_width_left = 4
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	_tutorial.add_theme_stylebox_override("panel", style)
	root.add_child(_tutorial)
	_tutorial.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_tutorial.offset_left = -380
	_tutorial.offset_right = -16
	_tutorial.offset_top = 76
	_tutorial.offset_bottom = 180
	var box := VBoxContainer.new()
	_tutorial.add_child(box)
	_tutorial_title = _make_label(17)
	_tutorial_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_tutorial_title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
	box.add_child(_tutorial_title)
	_tutorial_text = _make_label(16)
	_tutorial_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_tutorial_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tutorial_text.custom_minimum_size = Vector2(340, 0)
	box.add_child(_tutorial_text)
	var hint := _make_label(12)
	hint.text = "F3 — скрыть обучение"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.modulate.a = 0.6
	box.add_child(hint)
	_tutorial.visible = false


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
