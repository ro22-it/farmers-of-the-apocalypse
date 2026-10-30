extends Node3D

## Корень игровой сцены. Позже здесь появятся запуск сети и смена дня и ночи.


func _ready() -> void:
	# Отладка: --screenshot=путь сохраняет кадр и закрывает игру (проверка без рук)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			_save_screenshot(arg.trim_prefix("--screenshot="))


func _save_screenshot(path: String) -> void:
	for i in 90:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
