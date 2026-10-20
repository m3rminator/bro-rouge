extends Node2D
## Test level built from an ASCII map. Procedural level generation will replace this map later.
##   # = dirt   G = grass-topped dirt   P = player start   . = air

const LEVEL := [
	"............................................................",
	"............................................................",
	"............................................................",
	"............................................................",
	"............................................................",
	"............................................................",
	".....................................GGGG...................",
	"...........................GGG.......####...................",
	"..................GGGG.....###..............GGGGG...........",
	"..........GGG.....####......................#####...........",
	"..P.......###....................GGG........#####.......GG..",
	"GGGGGGGGGGGGGGG....GGGGGGGGGGGGGG###GGGGGGGG#####GGGGGGG##GG",
	"###############....##############################.##########",
	"###############....##############################.##########",
	"############################################################",
	"############################################################",
	"############################################################",
]
const MUSIC := "res://assets/music/level_jungle.mp3"


func _ready() -> void:
	var tile := Block.SIZE
	for y in LEVEL.size():
		for x in LEVEL[y].length():
			var pos := Vector2(x * tile + tile / 2.0, y * tile + tile / 2.0)
			match LEVEL[y][x]:
				"#":
					_add_block("dirt", pos)
				"G":
					_add_block("grass", pos)
				"P":
					$Player.position = pos
	var cam: Camera2D = $Player/Camera
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = LEVEL[0].length() * tile
	cam.limit_bottom = LEVEL.size() * tile
	if ResourceLoader.exists(MUSIC):
		var music := AudioStreamPlayer.new()
		music.stream = load(MUSIC)
		music.volume_db = -12.0
		add_child(music)
		music.play()


func _add_block(kind: String, pos: Vector2) -> void:
	var block := Block.new().setup(kind)
	block.position = pos
	add_child(block)
