extends Node2D
## Builds the level from GameData.LEVELS (design/levels/*.txt) and spawns the Bro, enemies and HUD.
## Symbols: # earth block (grass if open sky above)  P player start  E mook  . air

const LEVEL := "level_01"
const MOOK_SCENE := preload("res://scenes/mook.tscn")
const MUSIC := "res://assets/music/level_jungle.mp3"


func _ready() -> void:
	var rows: Array = GameData.LEVELS[LEVEL]
	var tile := Block.SIZE
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var pos := Vector2(x * tile + tile / 2.0, y * tile + tile / 2.0)
			match row[x]:
				"#":
					_add_block(rows, x, y, pos)
				"P":
					$Player.position = pos
				"E":
					var mook := MOOK_SCENE.instantiate()
					mook.position = pos
					add_child(mook)

	var cam: Camera2D = $Player/Camera
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = rows[0].length() * tile
	cam.limit_bottom = rows.size() * tile

	var hud := Hud.new()
	add_child(hud)
	hud.track($Player)

	if ResourceLoader.exists(MUSIC):
		var music := AudioStreamPlayer.new()
		music.stream = load(MUSIC)
		music.volume_db = -12.0
		add_child(music)
		music.play()


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
