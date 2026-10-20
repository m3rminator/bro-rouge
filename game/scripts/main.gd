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
	var rows: Array = GameData.LEVELS[lv.map]
	Run.begin_level()
	var tile := Block.SIZE
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var pos := Vector2(x * tile + tile / 2.0, y * tile + tile / 2.0)
			var ch := row[x]
			if ch == "#":
				_add_block(rows, x, y, pos)
			elif ch == "P":
				player.position = pos
			elif ch == "O":
				var barrel := Barrel.new()
				barrel.position = pos
				add_child(barrel)
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

	hud = Hud.new()
	add_child(hud)
	hud.track(player)
	hud.show_level(Run.level_index + 1, Run.loop, lv.title)
	hud.set_lives(Run.lives)
	hud.set_kills(0, Run.quota())
	hud.message("LEVEL %d" % (Run.level_index + 1), Hud.WHITE, 2.5, "%s - KILL %d TO OPEN THE EXIT" % [lv.title, Run.quota()])
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
	await get_tree().create_timer(GameData.RUN.run_over_delay if over else GameData.BRO.respawn_delay).timeout
	if over:
		Run.new_run()
	get_tree().reload_current_scene()


## Same rules as the catalog preview (tools/build.py: level_tiles / tile_variant).
func _add_block(rows: Array, x: int, y: int, pos: Vector2) -> void:
	var block := Block.new()
	if _has_sky(rows, x, y):
		var k := _variant(x, y, GameData.TILE_VARIANTS.grass)
		var drip := "drip_%d" % k if y + 1 < rows.size() else ""
		block.setup("grass_%d" % k, drip)
	else:
		block.setup("earth_%d" % _variant(x, y, GameData.TILE_VARIANTS.earth))
	block.position = pos
	add_child(block)


## Grass grows only where GameData.BLOCK.grass_clearance tiles above are all air.
func _has_sky(rows: Array, x: int, y: int) -> bool:
	for yy in range(maxi(0, y - GameData.BLOCK.grass_clearance), y):
		if rows[yy][x] == "#":
			return false
	return true


func _variant(x: int, y: int, count: int) -> int:
	return ((x * 73) ^ (y * 151)) % count
