extends Node

## Звуки, которые решает хост, а слышать должны все: удары, крики, монеты, лай.
## Автозагрузка. Хост вызывает everyone(), звук играет у каждого в той же точке.


func everyone(sound: String, position: Vector3, volume_db := 0.0) -> void:
	if multiplayer.is_server() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_play.rpc(sound, position, volume_db)
	else:
		_play(sound, position, volume_db)


@rpc("authority", "call_local", "unreliable")
func _play(sound: String, position: Vector3, volume_db: float) -> void:
	SoundBank.play_at(get_tree(), sound, position, volume_db)
