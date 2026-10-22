extends Node
## Run state (autoload "Run"): current level, loop, lives and kills. Survives scene reloads.
## Rules and level order: design/run.yaml (GameData.RUN).

signal kills_changed(kills: int, quota: int)
signal quota_reached

const RULES := GameData.RUN

var level_index := 0  # unused now that levels are generated (kept for the hand-made maps)
var depth := 0  # fights cleared this run; drives how big and tough the next level is
var in_hub := false  # the safe house between boss levels
var loadout := {}  # hearts and ammo carried from one level to the next (see store_loadout)
var _current := {}  # the level being played: generated once, kept for restarts after a death
var loop := 1
var lives: int = RULES.lives
var kills := 0
var grenades: int = GameData.GRENADE.grenades_per_level  # refilled only when a level is finished
var character := "bro"  # picked on the character select screen (scripts/character_select.gd)


## The chosen Bro's stats: everything from design/entities/bro.yaml, with the character's own
## numbers (e.g. design/entities/blala.yaml) laid over it.
func bro_stats() -> Dictionary:
	var stats: Dictionary = GameData.BRO.duplicate()
	if character == "blala":
		stats.merge(GameData.BLALA, true)
	return stats


## The level being played (scripts/level_gen.gd), generated the first time it is asked for.
func level() -> Dictionary:
	if _current.is_empty():
		_current = LevelGen.hub() if in_hub else LevelGen.combat(depth)
	return _current


## Remember the Bro's hearts and ammo when a level is cleared; the next level starts with them.
func store_loadout(player: Node) -> void:
	loadout = {"hp": player.hp, "ammo": player.ammo, "spare_mags": player.spare_mags}


func quota() -> int:
	return level().kill_quota


func quota_met() -> bool:
	return kills >= quota()


## main.gd calls this when a level (re)starts: kills always start at 0.
func begin_level() -> void:
	kills = 0


## Every enemy death, however it happened.
func add_kill() -> void:
	kills += 1
	kills_changed.emit(kills, quota())
	if kills == quota():
		quota_reached.emit()


## Next level; after the last one the run loops back to level 1.
func next_level() -> void:
	grenades = GameData.GRENADE.grenades_per_level
	_current = {}
	if in_hub:
		in_hub = false
	else:
		depth += 1
		in_hub = depth % RULES.boss_every == 0  # a boss level was just cleared


## Returns true if that was the last life (the run is over).
func lose_life() -> bool:
	lives -= 1
	loadout.erase("hp")  # the level restarts with full hearts, and with the ammo he had when it began
	return lives <= 0


func new_run() -> void:
	level_index = 0
	depth = 0
	in_hub = false
	loadout = {}
	_current = {}
	loop = 1
	lives = RULES.lives
	kills = 0
	grenades = GameData.GRENADE.grenades_per_level
