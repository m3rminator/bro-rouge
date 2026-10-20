class_name Sfx
## Plays generated sound effects from res://assets/sfx by name. Missing files are skipped silently.

static var _cache := {}


static func play(node: Node, sound: String, volume_db := 0.0, pitch_jitter := 0.08) -> void:
	if not _cache.has(sound):
		var path := "res://assets/sfx/%s.mp3" % sound
		_cache[sound] = load(path) if ResourceLoader.exists(path) else null
	if _cache[sound] == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = _cache[sound]
	player.volume_db = volume_db
	player.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	player.finished.connect(player.queue_free)
	node.get_tree().root.add_child(player)
	player.play()
