class_name Quality
## Performance settings (SETTINGS on the title screen, saved in user://settings.cfg). A level (LOW, RECOMMENDED, HIGH)
## scales every particle effect and caps how many of them live at once, so a few blasts and a lot of blood cannot pile
## up and slow a phone down. RECOMMENDED is the default. Effects ask `n()` for their amount and `take()` for room in
## the budget of their kind, and hand it back with `give()` when they are gone.

const PATH := "user://settings.cfg"
const NAMES := ["LOW", "RECOMMENDED", "HIGH"]
const FPS_CHOICES := [30, 60]
## scale: share of every particle amount; drops/crumbs/cpu/embers/sfx: most alive at once; grass_step: seconds between
## wind updates; enemy_range: enemies farther than this (px) from the Bro stand still.
const PRESETS := [
	{"scale": 0.4, "drops": 50, "crumbs": 70, "cpu": 70, "embers": 16, "sfx": 8, "grass_step": 0.2, "enemy_range": 560.0},
	{"scale": 0.65, "drops": 110, "crumbs": 150, "cpu": 160, "embers": 36, "sfx": 12, "grass_step": 0.1, "enemy_range": 760.0},
	{"scale": 1.0, "drops": 260, "crumbs": 320, "cpu": 400, "embers": 80, "sfx": 20, "grass_step": 0.05, "enemy_range": 1100.0},
]

static var level := 1
static var fps := 60
static var _loaded := false
static var _used := {}  # budget kind -> how many are alive


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var file := ConfigFile.new()
	if file.load(PATH) == OK:
		level = clampi(int(file.get_value("quality", "level", 1)), 0, PRESETS.size() - 1)
		fps = int(file.get_value("quality", "fps", 60))
		if not FPS_CHOICES.has(fps):
			fps = 60
	Engine.max_fps = fps


## The value of one number in the chosen preset.
static func p(key: String) -> Variant:
	_ensure()
	return PRESETS[level][key]


## `amount` scaled to the chosen level (at least 1 for anything that was asked for).
static func n(amount: int) -> int:
	_ensure()
	if amount <= 0:
		return 0
	return maxi(1, roundi(amount * float(PRESETS[level].scale)))


## Room for up to `wanted` of `kind`: how many it may use now (0 when the cap is reached). Give them back with give().
static func take(kind: String, wanted: int) -> int:
	_ensure()
	var room := maxi(int(PRESETS[level][kind]) - int(_used.get(kind, 0)), 0)
	var got := mini(wanted, room)
	_used[kind] = int(_used.get(kind, 0)) + got
	return got


static func give(kind: String, amount: int) -> void:
	_used[kind] = maxi(int(_used.get(kind, 0)) - amount, 0)


static func reset_budgets() -> void:
	_used.clear()


static func set_level(value: int) -> void:
	_ensure()
	level = posmod(value, PRESETS.size())
	save()


static func set_fps(value: int) -> void:
	_ensure()
	fps = value
	Engine.max_fps = fps
	save()


static func save() -> void:
	var file := ConfigFile.new()
	file.load(PATH)  # keep the other settings (the volumes)
	file.set_value("quality", "level", level)
	file.set_value("quality", "fps", fps)
	file.save(PATH)
