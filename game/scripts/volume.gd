class_name Volume
## The two volume sliders of SETTINGS: SFX (every sound effect: shots, blasts, enemies, steps) and MUSIC. Each is a share
## from 0 to 1 on its own audio bus, saved in user://settings.cfg. `ensure()` makes the buses (once) and sets them.

const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"

static var sfx := 1.0
static var music := 1.0
static var _made := false


static func ensure() -> void:
	if _made:
		return
	_made = true
	var file := ConfigFile.new()
	if file.load(Quality.PATH) == OK:
		sfx = clampf(float(file.get_value("audio", "sfx", 1.0)), 0.0, 1.0)
		music = clampf(float(file.get_value("audio", "music", 1.0)), 0.0, 1.0)
	for bus in [SFX_BUS, MUSIC_BUS]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	_apply()


static func set_sfx(value: float) -> void:
	ensure()
	sfx = clampf(value, 0.0, 1.0)
	_apply()


static func set_music(value: float) -> void:
	ensure()
	music = clampf(value, 0.0, 1.0)
	_apply()


static func save() -> void:
	var file := ConfigFile.new()
	file.load(Quality.PATH)  # keep the other settings
	file.set_value("audio", "sfx", sfx)
	file.set_value("audio", "music", music)
	file.save(Quality.PATH)


static func _apply() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SFX_BUS), linear_to_db(sfx) if sfx > 0.0 else -80.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MUSIC_BUS), linear_to_db(music) if music > 0.0 else -80.0)
