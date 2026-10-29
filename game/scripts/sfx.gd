class_name Sfx
## Plays generated sound effects from res://assets/sfx by name. Missing files are skipped silently.

static var _cache := {}
static var _live := 0  # sounds playing now: past the cap of the quality level, new ones are skipped


## Loads a sound ahead of its first use.
static func preload_sound(sound: String) -> void:
	if not _cache.has(sound):
		var path := "res://assets/sfx/%s.mp3" % sound
		_cache[sound] = load(path) if ResourceLoader.exists(path) else null


static func play(node: Node, sound: String, volume_db := 0.0, pitch_jitter := 0.08) -> void:
	if not _cache.has(sound):
		var path := "res://assets/sfx/%s.mp3" % sound
		_cache[sound] = load(path) if ResourceLoader.exists(path) else null
	if _cache[sound] == null:
		return
	if _live >= int(Quality.p("sfx")):
		return
	_live += 1
	Volume.ensure()
	var player := AudioStreamPlayer.new()
	player.bus = Volume.SFX_BUS
	player.stream = _cache[sound]
	player.volume_db = volume_db
	player.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	player.finished.connect(player.queue_free)
	player.tree_exited.connect(func() -> void: _live = maxi(_live - 1, 0))
	node.get_tree().root.add_child(player)
	player.play()
