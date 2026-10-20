extends Node
## Run state (autoload "Run"): current level, loop, lives and kills. Survives scene reloads.
## Rules and level order: design/run.yaml (GameData.RUN).

signal kills_changed(kills: int, quota: int)
signal quota_reached

const RULES := GameData.RUN

var level_index := 0
var loop := 1
var lives: int = RULES.lives
var kills := 0


func level() -> Dictionary:
	return RULES.levels[level_index]


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
	level_index += 1
	if level_index >= RULES.levels.size():
		level_index = 0
		loop += 1


## Returns true if that was the last life (the run is over).
func lose_life() -> bool:
	lives -= 1
	return lives <= 0


func new_run() -> void:
	level_index = 0
	loop = 1
	lives = RULES.lives
	kills = 0
