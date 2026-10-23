extends Node2D
## Builds the current run level (Run autoload -> design/run.yaml -> design/levels/*.txt),
## spawns everything, and runs the level flow: kill quota -> exit opens -> level clear,
## or death -> lose a life (restart level) / run over (new run).
## Symbols: # block  . air  P Bro  E mook  K kamikaze  B Brute  O barrel  X exit

const ENEMY_SCENES := {
	"E": preload("res://scenes/mook.tscn"),
	"K": preload("res://scenes/kamikaze.tscn"),
	"B": preload("res://scenes/brute.tscn"),
}
const MUSIC := "res://assets/music/level_jungle.mp3"

@onready var player: CharacterBody2D = $Player

var hud: Hud
var exit_flag: LevelExit
var _ending := false
var _locked_cooldown := 0.0
var _fall_limit := 0.0


func _ready() -> void:
	var lv: Dictionary = Run.level()
	var rows: Array = lv.rows
	var hub: bool = lv.kind == "hub"
	Run.begin_level()
	var tile := Block.SIZE
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var pos := Vector2(x * tile + tile / 2.0, y * tile + tile / 2.0)
			var ch := row[x]
			if ch == "#":
				_add_block(rows, x, y, pos, lv.get("biome", "earth"))
			elif ch == "P":
				player.position = pos
			elif ch == "O":
				var barrel := Barrel.new()
				barrel.position = pos
				add_child(barrel)
			elif HubStation.KINDS.has(ch):
				var station := HubStation.new()
				station.kind = ch
				station.position = pos
				add_child(station)
				station.used.connect(_on_station_used)
			elif ch == "X":
				exit_flag = LevelExit.new()
				exit_flag.position = pos
				add_child(exit_flag)
				exit_flag.touched.connect(_on_exit_touched)
			elif ENEMY_SCENES.has(ch):
				var enemy: Node2D = ENEMY_SCENES[ch].instantiate()
				enemy.position = pos
				add_child(enemy)
	move_child(player, -1)  # drawn and processed after the level

	var cam: Camera2D = player.get_node("Camera")
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = rows[0].length() * tile
	cam.limit_bottom = rows.size() * tile
	_fall_limit = rows.size() * tile + 48.0

	var background := Background.new()
	add_child(background)
	background.track(cam)

	hud = Hud.new()
	add_child(hud)
	hud.track(player)
	hud.set_lives(Run.lives)
	if hub:
		hud.show_hub()
		exit_flag.set_open(true)
		hud.message("SAFE HOUSE", Hud.GREEN, 3.0, "RESTOCK, THEN TAKE THE DOOR >")
	else:
		hud.show_level(Run.depth + 1, Run.loop, lv.title)
		hud.set_kills(0, Run.quota())
		hud.message("LEVEL %d" % (Run.depth + 1), Hud.WHITE, 2.5, "%s - KILL %d TO OPEN THE EXIT" % [lv.title, Run.quota()])
	Run.kills_changed.connect(hud.set_kills)
	Run.quota_reached.connect(_on_quota_reached)
	player.died.connect(_on_player_died)
	for boss in get_tree().get_nodes_in_group("bosses"):
		boss.engaged.connect(hud.track_boss)

	if ResourceLoader.exists(MUSIC):
		var music := AudioStreamPlayer.new()
		music.stream = load(MUSIC)
		music.volume_db = -12.0
		add_child(music)
		music.play()


func _exit_tree() -> void:
	# Run is an autoload: drop this level's connections before the next level connects its own.
	Run.kills_changed.disconnect(hud.set_kills)
	Run.quota_reached.disconnect(_on_quota_reached)


func _physics_process(delta: float) -> void:
	_locked_cooldown -= delta
	if not player.dead and player.position.y > _fall_limit:  # fell through a blasted-out floor
		player.kill()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.position.y > _fall_limit:
			enemy.queue_free()


func _on_quota_reached() -> void:
	exit_flag.set_open(true)
	hud.message("EXIT OPEN", Hud.GREEN, 2.5, "GET TO THE FLAG >")
	Sfx.play(self, "quota_reached")


func _on_exit_touched() -> void:
	if _ending or player.dead:
		return
	if not Run.quota_met():
		if _locked_cooldown <= 0.0:
			_locked_cooldown = 1.5
			hud.message("KILL %d MORE" % (Run.quota() - Run.kills), Hud.RED, 1.5)
			Sfx.play(self, "exit_locked", -4.0)
		return
	_ending = true
	player.freeze()
	Run.store_loadout(player)
	if Run.in_hub:
		hud.message("GOOD LUCK", Hud.YELLOW, 0.0)
	else:
		hud.message("LEVEL CLEAR", Hud.YELLOW, 0.0)
	Sfx.play(self, "level_clear")
	await get_tree().create_timer(GameData.RUN.clear_delay).timeout
	Run.next_level()
	get_tree().reload_current_scene()


func _on_player_died() -> void:
	if _ending:
		return
	_ending = true
	var over := Run.lose_life()
	hud.set_lives(maxi(Run.lives, 0))
	if over:
		hud.message("RUN OVER", Hud.RED, 0.0, "BACK TO LEVEL 1")
	else:
		hud.message("YOU DIED", Hud.RED, 0.0, "%d LIVES LEFT" % Run.lives)
	await get_tree().create_timer(GameData.RUN.run_over_delay if over else Run.bro_stats().respawn_delay).timeout
	if over:
		Run.new_run()
	get_tree().reload_current_scene()


## Same rules as the catalog preview (tools/build.py: pick_tile). Earth: grass on top, two rows of normal-detail earth
## (a stone now and then), then low-detail earth. Rock tiles are never picked here (they are for hand-placed stone);
## in the stone biome it is all rock, darker the deeper it lies.
func _add_block(rows: Array, x: int, y: int, pos: Vector2, biome: String) -> void:
	var block := Block.new()
	var h := tile_hash(x, y)
	var flip_h := (h >> 3) & 1 == 1
	var flip_v := (h >> 4) & 1 == 1
	var sky := _has_sky(rows, x, y)
	var d := _air_distance(rows, x, y)
	var roll := tile_hash(x, y, 2) % 100
	var anim: String
	var drip := ""
	var debris := Block.EARTH_DEBRIS
	if biome == "stone":
		debris = Block.STONE_DEBRIS
		if sky:
			anim = _pick("stonetop", x, y)
			flip_v = false
		else:
			anim = _pick("stone", x, y) if d <= 2 else _pick("deep", x, y)
	elif sky:
		var k := tile_hash(x, y, 1) % GameData.TILE_VARIANTS.grass
		anim = "grass_%d" % k
		if y + 1 < rows.size():
			drip = "drip_%d" % k
		flip_v = false
	elif d <= 3:  # the second layer (two rows deep): some clods, now and then a stone
		anim = _pick("pebble", x, y) if roll < 14 else _pick("earth", x, y)
	else:  # the third layer and deeper: low detail
		anim = _pick("flint", x, y) if roll < 7 else _pick("subsoil", x, y)
	block.setup(anim, drip, flip_h, flip_v, debris)
	if sky and biome != "stone":
		block.add_child(Grass.new())  # living blades on top (grass.gd)
	block.position = pos
	add_child(block)


## Grass grows only where GameData.BLOCK.grass_clearance tiles above are all air.
func _has_sky(rows: Array, x: int, y: int) -> bool:
	for yy in range(maxi(0, y - GameData.BLOCK.grass_clearance), y):
		if rows[yy][x] == "#":
			return false
	return true


## 1 = the tile touches open air ... reach + 1 = buried deeper than that. not_above ignores air higher up (the sky over the ground).
func _air_distance(rows: Array, x: int, y: int, reach := 3, not_above := false) -> int:
	for r in range(1, reach + 1):
		for dy in range(0 if not_above else -r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and _is_air(rows, x + dx, y + dy):
					return r
	return reach + 1


func _is_air(rows: Array, x: int, y: int) -> bool:
	if y < 0:
		return true
	if x < 0 or y >= rows.size() or x >= rows[0].length():
		return false  # the map edge counts as solid ground
	return rows[y][x] != "#"


func _pick(kind: String, x: int, y: int) -> String:
	return "%s_%d" % [kind, tile_hash(x, y, 1) % GameData.TILE_VARIANTS[kind]]


## Random-looking but fixed per map position (same hash as tools/build.py tile_hash).
static func tile_hash(x: int, y: int, salt := 0) -> int:
	var n := (x * 374761393 + y * 668265263 + salt * 1274126177) & 0xFFFFFFFF
	n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
	return n ^ (n >> 16)


## A hub station was used (hub_station.gd).
func _on_station_used(kind: String) -> void:
	match kind:
		"A":
			player.restock()
			hud.message("AMMO RESTOCKED", Hud.GREEN, 1.5)
			Sfx.play(self, "reload", -4.0)
		"H":
			player.heal()
			Run.lives = GameData.RUN.lives
			hud.set_lives(Run.lives)
			hud.message("HEARTS AND LIVES REFILLED", Hud.GREEN, 1.5)
			Sfx.play(self, "quota_reached", -6.0)
		"G":
			Run.grenades = GameData.GRENADE.grenades_per_level
			player.grenades_changed.emit(Run.grenades)
			hud.message("GRENADES REFILLED", Hud.GREEN, 1.5)
			Sfx.play(self, "reload", -4.0)
