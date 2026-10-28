extends Node2D
## Builds the current run level (Run autoload -> design/run.yaml -> design/levels/*.txt),
## spawns everything, and runs the level flow: kill quota -> exit opens -> level clear,
## or death -> lose a life (restart level) / run over (new run).
## Symbols: # block  . air  P Bro  E mook  K kamikaze  V vest  M helmet  B Brute  O barrel  X exit

const ENEMY_SCENES := {
	"E": preload("res://scenes/mook.tscn"),
	"K": preload("res://scenes/kamikaze.tscn"),
	"V": preload("res://scenes/vest.tscn"),
	"M": preload("res://scenes/helmet.tscn"),
	"B": preload("res://scenes/brute.tscn"),
}
const MUSIC := "res://assets/music/level_jungle.mp3"

@onready var player: CharacterBody2D = $Player

var hud: Hud
var exit_flag: LevelExit
var walls: BackWall  # the dark earth behind every block: what shows where one is shot away
var _ending := false
var _by_truck := false  # this level started with the truck driving in
var _locked_cooldown := 0.0
var _fall_limit := 0.0
var _level_width := 0.0
var _arena := {}  # boss level: {door cells, trigger column, entry_col} from level_gen.gd; empty otherwise
var _arena_sealed := false
var _lv: Dictionary
var _palms := {}  # tiles that have a palm (tree_decor.gd plan)


func _ready() -> void:
	var lv: Dictionary = Run.level()
	_lv = lv
	_arena = lv.get("arena", {})
	var stone := {}
	for cell: Vector2i in lv.get("stone", []):
		stone[cell] = true
	var rows: Array = lv.rows
	var hub: bool = lv.kind == "hub"
	Run.begin_level()
	var tile := Block.SIZE
	if lv.get("biome", "earth") != "stone":
		var sky_tiles := []
		for y in rows.size():
			for x in rows[y].length():
				if rows[y][x] == "#" and _has_sky(rows, x, y) and not stone.has(Vector2i(x, y)):
					sky_tiles.append(Vector2i(x, y))
		_palms = TreeDecor.plan(sky_tiles)
	walls = BackWall.new()
	add_child(walls)
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var pos := Vector2(x * tile + tile / 2.0, y * tile + tile / 2.0)
			var ch := row[x]
			if ch == "#":
				_add_block(rows, x, y, pos, "stone" if stone.has(Vector2i(x, y)) else lv.get("biome", "earth"))
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
				station.used.connect(_on_station_used.bind(station))
			elif ch == "X":
				exit_flag = LevelExit.new()
				exit_flag.position = pos
				add_child(exit_flag)
				exit_flag.touched.connect(_on_exit_touched)
			elif ENEMY_SCENES.has(ch):
				var enemy: Node2D = ENEMY_SCENES[ch].instantiate()
				enemy.position = pos
				add_child(enemy)
	for cell: Vector2i in lv.get("walls", []):  # shafts of towers: the dark back wall shows there from the start
		var wpos := Vector2(cell.x * tile + tile / 2.0, cell.y * tile + tile / 2.0)
		walls.add(wpos, _wall_anim(cell.x, cell.y, lv.get("biome", "earth")), (tile_hash(cell.x, cell.y) >> 5) & 1 == 1, (tile_hash(cell.x, cell.y) >> 6) & 1 == 1)
		walls.reveal(wpos)
	for zip: Dictionary in lv.get("zips", []):
		var line := Zipline.new()
		line.a = Vector2(zip.a.x * tile + tile / 2.0, zip.a.y * tile + tile / 2.0)
		line.b = Vector2(zip.b.x * tile + tile / 2.0, zip.b.y * tile + tile / 2.0)
		add_child(line)
	for info: Dictionary in lv.get("ladders", []):  # the ladders of the temples
		var ladder := Ladder.new()
		ladder.position = Vector2(info.x * tile + tile / 2.0, 0.0)
		ladder.top = info.top * tile
		ladder.bottom = info.bot * tile
		ladder.step = info.step
		add_child(ladder)
	_seal_arena(lv, tile)
	_seal_trucks(rows)
	move_child(player, -1)  # drawn and processed after the level
	Run.spawned = get_tree().get_nodes_in_group("enemies").size()
	if Run.by_truck:
		_by_truck = true
		Run.by_truck = false
		var truck := ArrivalTruck.new()
		add_child(truck)
		move_child(truck, player.get_index())  # drawn under the Bro
		truck.arrive(player, player.position)

	var cam: Camera2D = player.get_node("Camera")
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = rows[0].length() * tile
	cam.limit_bottom = rows.size() * tile
	_fall_limit = rows.size() * tile + 48.0
	_level_width = rows[0].length() * tile

	var background := Background.new()
	add_child(background)
	background.track(cam)

	_make_hud()
	Run.quota_reached.connect(_on_quota_reached)
	Run.upgrade_ended.connect(_on_upgrade_ended)
	player.died.connect(_on_player_died)
	for boss in get_tree().get_nodes_in_group("bosses"):
		boss.engaged.connect(_on_boss_engaged)
		if not _arena.is_empty():
			boss.gate_x = (_arena.entry_col + 0.5) * Block.SIZE

	add_child(PauseMenu.new())

	if ResourceLoader.exists(MUSIC):
		var music := AudioStreamPlayer.new()
		music.stream = load(MUSIC)
		music.volume_db = -12.0
		add_child(music)
		music.play()
	if lv.kind == "start":
		_choose_bro()


## The HUD for this level; built again when a crate changes the Bro (new hearts, magazines, grenade icons).
func _make_hud() -> void:
	if hud != null:
		Run.kills_changed.disconnect(hud.set_kills)
		hud.queue_free()
	hud = Hud.new()
	add_child(hud)
	hud.track(player)
	hud.set_lives(Run.lives)
	if _lv.kind == "start":
		hud.show_title("START")
		hud.message("BRO ROGUE", Hud.YELLOW, 3.0, "WALK TO THE BOX >")
	elif _lv.kind == "hub":
		hud.show_hub()
		exit_flag.set_open(true)
		hud.message("SAFE HOUSE", Hud.GREEN, 3.0, "RESTOCK, THEN BOARD THE TRUCK >")
	else:
		hud.show_level(Run.depth + 1, Run.loop, _lv.title)
		hud.set_kills(Run.kills, Run.quota())
		hud.message("LEVEL %d" % (Run.depth + 1), Hud.WHITE, 2.5, "%s - KILL %d TO OPEN THE EXIT" % [_lv.title, Run.quota()])
	Run.kills_changed.connect(hud.set_kills)


## A crate boost ran out: the Bro's numbers go back.
func _on_upgrade_ended(_kind: String) -> void:
	player.refresh_stats()


func _on_boss_engaged(boss: Node) -> void:
	hud.track_boss(boss)


func _exit_tree() -> void:
	# Run is an autoload: drop this level's connections before the next level connects its own.
	Run.kills_changed.disconnect(hud.set_kills)
	Run.quota_reached.disconnect(_on_quota_reached)
	Run.upgrade_ended.disconnect(_on_upgrade_ended)


func _physics_process(delta: float) -> void:
	_locked_cooldown -= delta
	if not _arena.is_empty() and not _arena_sealed and not player.dead and player.position.x > (_arena.trigger + 0.5) * Block.SIZE:
		_close_arena()
	var out := player.is_physics_processing() and (player.position.y > _fall_limit or player.position.x < -32.0 or player.position.x > _level_width + 32.0)  # not while the truck carries him in
	if not player.dead and out:  # fell through a blasted-out floor, or was blown off the side
		BloodFountain.start(self, Vector2(clampf(player.position.x, 4.0, _level_width - 4.0), minf(player.position.y, _fall_limit - 40.0)))
		player.kill()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.position.y > _fall_limit:
			if not enemy.dead:
				if enemy.counts_kill:
					Run.add_kill()  # lost in a pit: counts, or the quota could never be reached
			enemy.queue_free()


func _on_quota_reached() -> void:
	exit_flag.set_open(true)
	hud.message("EXIT OPEN", Hud.GREEN, 2.5, "GET TO THE TRUCK >")
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
	exit_flag.board(player)
	Run.store_loadout(player)
	if Run.in_hub:
		hud.message("GOOD LUCK", Hud.YELLOW, 0.0)
	else:
		hud.message("LEVEL CLEAR", Hud.YELLOW, 0.0)
	Sfx.play(self, "level_clear")
	await get_tree().create_timer(GameData.RUN.clear_delay).timeout
	Run.next_level()
	Run.by_truck = true
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
		hud.message("YOU DIED", Hud.RED, 0.0, "ONE LIFE LEFT" if Run.lives == 1 else "%d EXTRA LIVES LEFT" % (Run.lives - 1))
	await get_tree().create_timer(GameData.RUN.run_over_delay if over else Run.bro_stats().respawn_delay).timeout
	if over:
		Run.go_to_start()
	get_tree().reload_current_scene()


## Same rules as the catalog preview (tools/build.py: pick_tile). Earth: grass on the top block only (everything of it
## stays inside that block), two rows of calm earth under it (a stone now and then), a mixed transition, then flat dark
## earth. Rock tiles are never picked here (they are for hand-placed stone); in the stone biome it is all rock, flatter
## and darker the deeper it lies.
func _add_block(rows: Array, x: int, y: int, pos: Vector2, biome: String) -> Block:
	var block := Block.new()
	var h := tile_hash(x, y)
	var flip_h := (h >> 3) & 1 == 1
	var flip_v := (h >> 4) & 1 == 1
	var sky := _has_sky(rows, x, y)
	var d := _air_distance(rows, x, y, 4)
	var roll := tile_hash(x, y, 2) % 100
	var anim: String
	var debris := Block.EARTH_DEBRIS
	if biome == "stone":
		debris = Block.STONE_DEBRIS
		if sky:
			anim = _pick("stonetop", x, y)
			flip_v = false
		else:
			anim = _pick("stone", x, y) if d <= 2 else _pick("deep", x, y)
	elif sky:
		anim = _pick("grass", x, y)
		flip_v = false
	elif d <= 3:  # layer 2 (two rows under the grass): calm earth, the odd stone
		anim = _pick("pebble", x, y) if roll < 14 else _pick("earth", x, y)
	elif d == 4:  # one row of gradient tiles: layer-2 earth fading into flat earth
		anim = _pick("mid", x, y) if roll < 90 else _pick("earth", x, y)
		flip_v = false
	else:  # layer 3 and deeper: flat dark
		anim = _pick("flint", x, y) if roll < 7 else _pick("subsoil", x, y)
	block.setup(anim, flip_h, flip_v, debris)
	if sky and biome != "stone":
		block.add_child(Grass.new())  # living blades on top (grass.gd)
		for plant in _palms.get(Vector2i(x, y), []):  # background palms and plants (tree_decor.gd)
			block.add_child(TreeDecor.make(plant[0], plant[1]))
	block.position = pos
	add_child(block)
	if not sky:  # a broken surface block opens onto the sky, not onto a wall
		walls.add(pos, _wall_anim(x, y, biome), (h >> 5) & 1 == 1, (h >> 6) & 1 == 1)
	return block


## Boss arena: unbreakable blocks are tinted bluish (the rock walls and platforms are rock already).
func _seal_arena(lv: Dictionary, _tile: int) -> void:
	var rock := {}
	for cell: Vector2i in lv.get("stone", []):
		rock[cell] = true
	for cell: Vector2i in lv.get("unbreakable", []):
		var block: Block = Block.cells.get(cell)
		if block:
			block.unbreakable = true
			if not rock.has(cell):
				block.modulate = Color(0.78, 0.84, 0.95)


## The ground under the two trucks (the one that brought him and the one at the exit) cannot be broken, or a truck
## would hang in the air over a hole.
func _seal_trucks(rows: Array) -> void:
	var spans := []
	if exit_flag != null:
		var ex := floori(exit_flag.position.x / Block.SIZE)
		spans.append([ex - 3, ex + 3])
	var px := floori(player.position.x / Block.SIZE)
	spans.append([px - 1, px + 5])  # the arrival truck stops about two blocks to his right
	for span in spans:
		for x in range(maxi(span[0], 0), mini(span[1], rows[0].length() - 1) + 1):
			for y in rows.size():
				var block: Block = Block.cells.get(Vector2i(x, y))
				if block:
					block.unbreakable = true


## The Bro walked into the arena: two rock blocks close the doorway behind him and the Brute goes for him.
func _close_arena() -> void:
	_arena_sealed = true
	var tile := Block.SIZE
	for cell: Vector2i in _arena.door:
		var block := _add_block(_lv.rows, cell.x, cell.y, Vector2(cell.x * tile + tile / 2.0, cell.y * tile + tile / 2.0), "stone")
		block.unbreakable = true
	Sfx.play(player, "block_break", -4.0)
	player.shake(4.0)
	for boss in get_tree().get_nodes_in_group("bosses"):
		boss.aggro()


func _wall_anim(x: int, y: int, biome: String) -> String:
	var kind := "stonewall" if biome == "stone" else "wall"
	return "%s_%d" % [kind, tile_hash(x, y, 3) % GameData.TILE_VARIANTS[kind]]


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


## A new run: every Bro is shown, he picks one, and the first fight starts.
func _choose_bro() -> void:
	var picker := BroPicker.open(self, CharacterCards.ids(), "CHOOSE YOUR BRO")
	Run.character = await picker.chosen
	Run.new_run()  # leaves the starting zone: the first fight
	get_tree().reload_current_scene()


## A hub station was used (hub_station.gd).
func _on_station_used(kind: String, station: HubStation) -> void:
	match kind:
		"U":
			station.queue_free()
			Sfx.play(self, "reload", -4.0)
			var kinds := ["mag", "rate", "speed", "damage"]
			if player.STATS.weapon == "raygun":
				kinds.erase("damage")  # the beam has its own damage
			var pick: String = kinds[randi() % kinds.size()]
			Run.boost(pick)
			player.refresh_stats()
			hud.message({"mag": "BIGGER MAGAZINE", "rate": "FASTER FIRE", "speed": "FASTER RUNNING", "damage": "MORE DAMAGE"}[pick], Hud.GREEN, 2.0,
					"%d SECONDS" % int(GameData.RUN.upgrade_time))
		"W":
			var pool := ["heart", "spare", "grenade", "size", "rate", "speed", "damage", "jump", "reload"]
			if player.STATS.weapon == "raygun":
				pool.erase("damage")  # the beam has its own damage
			if player.STATS.weapon == "fists":
				for gone in ["damage", "rate", "size", "spare", "reload"]:
					pool.erase(gone)  # no gun to improve
			if player.STATS.shells_start > 0:
				pool.erase("reload")  # shell Bros load one shell at a time
				pool.erase("spare")  # and carry no magazines
			pool.shuffle()
			var picker := PowerPicker.open(self, pool.slice(0, 3), "CHOOSE A PERK")
			var pick: String = await picker.chosen
			station.queue_free()
			Run.add_perk(pick)
			player.refresh_stats()
			match pick:  # the new heart, magazine or grenade is already in hand
				"heart":
					player.hp = mini(player.hp + 1, player.STATS.max_hp)
				"spare":
					player.spare_mags = mini(player.spare_mags + 1, player.STATS.max_spare_mags)
				"grenade":
					Run.grenades = mini(Run.grenades + 1, Run.grenade_max())
			_make_hud()  # new heart, magazine and grenade icons
			player.hp_changed.emit(player.hp, player.STATS.max_hp)
			player.ammo_changed.emit(player.ammo, player.spare_mags, false)
			player.grenades_changed.emit(Run.grenades)
			Sfx.play(self, "quota_reached", -6.0)
			hud.message("PERK TAKEN", Hud.GREEN, 2.0, "FOR THE WHOLE RUN")
		"A":
			player.restock()
			hud.message("AMMO RESTOCKED", Hud.GREEN, 1.5)
			Sfx.play(self, "reload", -4.0)
		"H":
			player.heal()
			var lost: bool = Run.lives < Run.RULES.lives  # the extra life comes back if it is spent, never more than the one
			Run.lives = maxi(Run.lives, Run.RULES.lives)
			hud.set_lives(Run.lives)
			hud.message("HEARTS AND LIFE REFILLED" if lost else "HEARTS REFILLED", Hud.GREEN, 1.5)
			Sfx.play(self, "quota_reached", -6.0)
		"G":
			Run.grenades = Run.grenade_max()
			player.grenades_changed.emit(Run.grenades)
			hud.message("GRENADES REFILLED", Hud.GREEN, 1.5)
			Sfx.play(self, "reload", -4.0)
