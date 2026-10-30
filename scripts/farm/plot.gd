class_name Plot
extends Interactable

## Участок грядки: вскопать лопатой → посадить семена → поливать → собрать (E).
## Состояние меняет только хост, остальным его рассылает синхронизатор.
## Растения — простые фигуры, собираются из кода по культуре и стадии роста.

enum State { UNTILLED, TILLED, PLANTED }

## За сколько секунд полностью политая земля высыхает
const DRY_TIME := 150.0
## Где стоят растения на участке 2×2 м (тыква — одна в центре)
const PLANT_SPOTS: Array[Vector3] = [
	Vector3(-0.45, 0.0, -0.5), Vector3(0.45, 0.0, -0.5),
	Vector3(-0.45, 0.0, 0.5), Vector3(0.45, 0.0, 0.5),
]
const COLORS := {
	"dry": Color(0.42, 0.3, 0.2),
	"wet": Color(0.22, 0.15, 0.1),
	"leaf": Color(0.3, 0.55, 0.22),
	"stalk": Color(0.45, 0.6, 0.25),
	"carrot": Color(0.95, 0.5, 0.15),
	"cob": Color(0.95, 0.82, 0.3),
	"pumpkin": Color(0.93, 0.5, 0.12),
}

static var _materials := {}

var state: int = State.UNTILLED:
	set(value):
		state = value
		_dirty = true
var crop := "":
	set(value):
		crop = value
		_dirty = true
## 0..1, при 1 урожай созрел
var growth := 0.0:
	set(value):
		growth = value
		_dirty = true
## 0..1, сколько осталось воды
var moisture := 0.0:
	set(value):
		moisture = value
		_dirty = true

var _dirty := true
var _built_key := ""
## «Созрело» над грядкой — видит только фермер
var _ripe_label: Label3D

@onready var _soil: MeshInstance3D = $Soil
@onready var _plants: Node3D = $Plants


func _ready() -> void:
	add_to_group("plots")
	_ripe_label = Label3D.new()
	_ripe_label.text = "Созрело"
	_ripe_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_ripe_label.font_size = 48
	_ripe_label.outline_size = 12
	_ripe_label.modulate = Color(0.6, 1.0, 0.4)
	_ripe_label.position = Vector3(0.0, 2.8, 0.0)
	_ripe_label.visible = false
	add_child(_ripe_label)


func _process(_delta: float) -> void:
	var local := get_tree().get_first_node_in_group("local_player") as Player
	_ripe_label.visible = is_ripe() and local != null and local.player_class == "farmer"
	if _dirty:
		_dirty = false
		_update_visuals()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	# Ночью ничего не растёт и не сохнет
	var day_night := get_tree().get_first_node_in_group("day_night") as DayNight
	if day_night and day_night.is_night():
		return
	if moisture > 0.0:
		moisture = maxf(moisture - delta / DRY_TIME, 0.0)
		if state == State.PLANTED and growth < 1.0:
			growth = minf(growth + delta / Crops.get_info(crop).grow_time, 1.0)


func reset() -> void:
	state = State.UNTILLED
	crop = ""
	growth = 0.0
	moisture = 0.0


## Грядочник ест грядку. Только на хосте. Посаженное пропадает, вскопанное вытаптывается.
## Возвращает путь к сцене урожая, если было что унести (созревшее), иначе пусто.
func steal() -> String:
	var loot := ""
	if state == State.PLANTED:
		if is_ripe():
			loot = Crops.get_info(crop).produce
		crop = ""
		growth = 0.0
		state = State.TILLED
	elif state == State.TILLED:
		state = State.UNTILLED
	return loot


func is_ripe() -> bool:
	return state == State.PLANTED and growth >= 1.0


func get_hint(item: PickupItem) -> String:
	var tool := item.tool if item else ""
	match state:
		State.UNTILLED:
			return "ЛКМ — вскопать" if tool == "shovel" else "Грядка не вскопана — нужна лопата"
		State.TILLED:
			if tool == "seeds":
				return "ЛКМ — посадить"
			if tool == "watering_can":
				return "ЛКМ — полить"
			return "Вскопано — можно сажать семена"
	var info := Crops.get_info(crop)
	if is_ripe():
		return "E — собрать: %s" % info.name
	var text := "%s: %d%%, %s" % [info.name, int(growth * 100.0), "полито" if moisture > 0.0 else "сухо — не растёт"]
	if tool == "watering_can":
		text += "\nЛКМ — полить"
	return text


func interact(player: Node3D, info: Dictionary) -> Dictionary:
	var player_class: String = player.get("player_class") if player.get("player_class") != null else ""
	match info.get("tool", ""):
		"shovel":
			if state != State.UNTILLED:
				return {"message": "Уже вскопано" if state == State.TILLED else "Здесь уже растёт"}
			state = State.TILLED
			return {"message": ""}
		"seeds":
			if state == State.UNTILLED:
				return {"message": "Сначала вскопайте лопатой"}
			if state == State.PLANTED:
				return {"message": "Здесь уже растёт"}
			var seed: String = info.get("crop", "")
			if Crops.get_info(seed).is_empty():
				return {}
			crop = seed
			growth = 0.0
			state = State.PLANTED
			return {"consume": 1}
		"watering_can":
			if state == State.UNTILLED:
				return {"message": "Сначала вскопайте лопатой"}
			moisture = maxf(moisture, PlayerClasses.water_amount(player_class))
			return {"consume": 1}
		"hand":
			if state != State.PLANTED:
				return {"message": "Здесь ничего не растёт"}
			if not is_ripe():
				return {"message": "Ещё не созрело: %d%%" % int(growth * 100.0)}
			_spawn_produce(PlayerClasses.harvest_bonus(player_class))
			reset()
			return {"message": ""}
	return {}


func _spawn_produce(bonus: int) -> void:
	var info := Crops.get_info(crop)
	var scene: PackedScene = load(info.produce)
	for i in maxi(info.amount + bonus, 1):
		var item: Node3D = scene.instantiate()
		item.position = global_position + Vector3(randf_range(-0.4, 0.4), 0.6 + i * 0.5, randf_range(-0.5, 0.5))
		_items_root().add_child(item, true)


func _update_visuals() -> void:
	_soil.visible = state != State.UNTILLED
	_soil.material_override = _material("wet" if moisture > 0.0 else "dry")
	var stage := _stage()
	var key := "%s:%d" % [crop, stage] if state == State.PLANTED else ""
	if key != _built_key:
		_built_key = key
		for child in _plants.get_children():
			child.queue_free()
		if key != "":
			_build_plants(stage)
	# Пока растёт, растение плавно увеличивается
	_plants.scale = Vector3.ONE * (1.0 if stage == 2 else lerpf(0.35, 0.9, growth))


## 0 — росток, 1 — растёт, 2 — созрело
func _stage() -> int:
	if growth >= 1.0:
		return 2
	return 0 if growth < 0.4 else 1


func _build_plants(stage: int) -> void:
	match crop:
		"carrot":
			for spot in PLANT_SPOTS:
				_add(_cone(0.14, 0.35), spot + Vector3(0.0, 0.17, 0.0), "leaf")
				if stage == 2:
					_add(_cylinder(0.07, 0.05, 0.1), spot + Vector3(0.0, 0.03, 0.0), "carrot")
		"corn":
			for spot in PLANT_SPOTS:
				_add(_cylinder(0.035, 0.05, 2.2), spot + Vector3(0.0, 1.1, 0.0), "stalk")
				_add(_cone(0.35, 0.9), spot + Vector3(0.0, 1.9, 0.0), "leaf")
				if stage >= 1:
					_add(_cone(0.3, 0.7), spot + Vector3(0.0, 1.2, 0.0), "leaf")
				if stage == 2:
					_add(_cylinder(0.06, 0.06, 0.3), spot + Vector3(0.1, 1.0, 0.0), "cob")
		"pumpkin":
			_add(_sphere(0.65, 0.25), Vector3(0.0, 0.1, 0.0), "leaf")
			if stage >= 1:
				var radius := 0.22 if stage == 1 else 0.42
				_add(_sphere(radius, radius * 1.6), Vector3(0.25, radius * 0.8, 0.15), "pumpkin")


func _add(mesh: Mesh, at: Vector3, color_key: String) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color_key)
	instance.position = at
	_plants.add_child(instance)


static func _material(key: String) -> StandardMaterial3D:
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = COLORS[key]
		material.roughness = 1.0
		_materials[key] = material
	return _materials[key]


static func _cone(radius: float, height: float) -> CylinderMesh:
	return _cylinder(0.0, radius, height)


static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 6
	mesh.rings = 1
	return mesh


static func _sphere(radius: float, height: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 5
	return mesh
