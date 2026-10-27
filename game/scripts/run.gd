extends Node
## Run state (autoload "Run"): current level, loop, lives and kills. Survives scene reloads.
## Rules and level order: design/run.yaml (GameData.RUN).

signal kills_changed(kills: int, quota: int)
signal quota_reached
signal upgrade_ended(kind: String)

const RULES := GameData.RUN

var level_index := 0  # unused now that levels are generated (kept for the hand-made maps)
var depth := 0  # fights cleared this run; drives how big and tough the next level is
var in_hub := false  # the safe house between boss levels
var in_start := true  # the starting zone: walk to the box and be dealt three Bros (the game opens here)
var perks := {}  # permanent safe-house perks of this run: kind -> how many were taken (see bro_stats)
var upgrades := {}  # crate boosts running now: kind ("mag", "rate", "speed", "damage") -> seconds left (see bro_stats)
var loadout := {}  # hearts and ammo carried from one level to the next (see store_loadout)
var _current := {}  # the level being played: generated once, kept for restarts after a death
var loop := 1
var lives: int = RULES.lives
var kills := 0
var grenades: int = GameData.GRENADE.grenades_per_level  # refilled only when a level is finished
## Characters drawn with another character's sprite until they get their own.
const LOOKS := {}

var character := "bro"  # picked on the character select screen (scripts/bro_picker.gd)


## The chosen Bro's stats: everything from design/entities/bro.yaml, with the character's own
## numbers (e.g. design/entities/blala.yaml) laid over it.
func bro_stats() -> Dictionary:
	var stats: Dictionary = GameData.BRO.duplicate()
	if character == "blala":
		stats.merge(GameData.BLALA, true)
	elif character == "sharif":
		stats.merge(GameData.SHARIF, true)
	elif character == "heavy":
		stats.merge(GameData.HEAVY, true)
	elif character == "mib":
		stats.merge(GameData.MIB, true)
	elif character == "bruce":
		stats.merge(GameData.BRUCE, true)
	if upgrades.has("mag"):
		if stats.shells_start > 0:
			stats.shells_max = int(ceil(stats.shells_max * (1.0 + RULES.upgrade_mag)))
		else:
			stats.magazine_size = int(ceil(stats.magazine_size * (1.0 + RULES.upgrade_mag)))
	if upgrades.has("rate"):
		stats.fire_interval = stats.fire_interval / (1.0 + RULES.upgrade_rate)
	if upgrades.has("speed"):
		stats.speed = stats.speed * (1.0 + RULES.upgrade_speed)
		stats.speed_crouch = stats.speed_crouch * (1.0 + RULES.upgrade_speed)
	# permanent perks from the safe house (they stack, last the whole run and lift the usual limits)
	stats.max_hp += perk("heart") * RULES.perk_heart
	stats.max_spare_mags += perk("spare") * RULES.perk_spare
	stats.magazines += perk("spare") * RULES.perk_spare
	stats.grenades = (stats.grenades if stats.grenades > 0 else GameData.GRENADE.grenades_per_level) + perk("grenade") * RULES.perk_grenade
	var size := 1.0 + perk("size") * RULES.perk_size
	stats.magazine_size = int(ceil(stats.magazine_size * size))
	if stats.shells_start > 0:
		stats.shells_max = int(ceil(stats.shells_max * size))
	stats.fire_interval = stats.fire_interval / (1.0 + perk("rate") * RULES.perk_rate)
	stats.speed = stats.speed * (1.0 + perk("speed") * RULES.perk_speed)
	stats.speed_crouch = stats.speed_crouch * (1.0 + perk("speed") * RULES.perk_speed)
	stats.jump_velocity = stats.jump_velocity * (1.0 + perk("jump") * RULES.perk_jump)
	stats.reload_time = stats.reload_time * maxf(0.34, 1.0 - perk("reload") * RULES.perk_reload)
	stats.damage_mult = (RULES.upgrade_damage if upgrades.has("damage") else 0.0) + perk("damage") * RULES.perk_damage
	return stats


## A crate boost (30 s): taking the same kind again starts its time over.
func boost(kind: String) -> void:
	upgrades[kind] = RULES.upgrade_time


## A safe-house perk: permanent for the run, and it stacks.
func add_perk(kind: String) -> void:
	perks[kind] = perk(kind) + 1


func perk(kind: String) -> int:
	return perks.get(kind, 0)


func _process(delta: float) -> void:
	for kind in upgrades.keys():
		upgrades[kind] -= delta
		if upgrades[kind] <= 0.0:
			upgrades.erase(kind)
			upgrade_ended.emit(kind)


## Grenades (or missiles, C4 charges, revolver rounds) carried per level: the character's own
## `grenades` stat, else design/entities/grenade.yaml's grenades_per_level.
func grenade_max() -> int:
	var own: int = bro_stats().grenades
	return own if own > 0 else GameData.GRENADE.grenades_per_level


## The sprite sheet a character is drawn with: his own once it exists, else the default Bro's.
func look_of(id: String) -> String:
	if ResourceLoader.exists("res://assets/sprites/%s_frames.tres" % id):
		return id
	return LOOKS.get(id, "bro")


func look() -> String:
	return look_of(character)


## The level being played (scripts/level_gen.gd), generated the first time it is asked for.
func level() -> Dictionary:
	if _current.is_empty():
		_current = LevelGen.start_zone() if in_start else (LevelGen.hub() if in_hub else LevelGen.combat(depth))
	return _current


## Remember the Bro's hearts and ammo when a level is cleared; the next level starts with them.
func store_loadout(player: Node) -> void:
	loadout = {"hp": player.hp, "ammo": player.ammo, "spare_mags": player.spare_mags}


var by_truck := false  # the next level starts with the truck driving the Bro in (set when he leaves one by truck)
var spawned := -1  # enemies that really stand in the level (main.gd counts them); the quota can never ask for more


func quota() -> int:
	var q: int = level().kill_quota
	return q if spawned < 0 else mini(q, spawned)


func quota_met() -> bool:
	return kills >= quota()


## main.gd calls this when a level (re)starts: kills always start at 0.
func begin_level() -> void:
	kills = 0
	spawned = -1


## Every enemy death, however it happened.
func add_kill() -> void:
	kills += 1
	kills_changed.emit(kills, quota())
	if kills == quota():
		quota_reached.emit()


## Next level; after the last one the run loops back to level 1.
func next_level() -> void:
	_current = {}
	if in_hub:
		in_hub = false
	else:
		depth += 1
		loop = depth / RULES.boss_every + 1  # fight, fight, fight, boss = one loop
		in_hub = true  # a safe house after every level


## Returns true if that was the last life (the run is over). A run starts with the Bro and one extra life.
func lose_life() -> bool:
	lives -= 1
	loadout.erase("hp")  # the level restarts with full hearts, and with the ammo he had when it began
	return lives <= 0


## Back to the starting zone: a fresh run waits for a Bro to be picked there.
func go_to_start() -> void:
	new_run()
	character = "bro"
	in_start = true
	grenades = grenade_max()


func new_run() -> void:
	in_start = false
	upgrades = {}
	perks = {}
	level_index = 0
	by_truck = false
	depth = 0
	in_hub = false
	loadout = {}
	_current = {}
	loop = 1
	lives = RULES.lives
	kills = 0
	grenades = grenade_max()
