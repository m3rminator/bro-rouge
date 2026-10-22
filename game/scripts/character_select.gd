extends Node2D
## Character select screen, the first thing in the game. Left/Right (A/D) pick a Bro,
## Shoot / Jump / Enter start the run with him (Run.character -> player.gd reads his stats).
## Placeholder look: the cards show each Bro's idle sprite and numbers read from the stats.

const BACKDROP := preload("res://assets/backgrounds/jungle.jpg")
const VIEW := Vector2(480, 270)
const CARD := Vector2(150, 160)
const YELLOW := Color("ffd23e")
const DIM := Color("8c8a9a")
const PANEL := Color("23202f")
const OUTLINE := Color("14101e")

## id (Run.character), title, one-line summary, GameData stats laid over the Bro's.
const CHARACTERS := [
	{"id": "bro", "title": "BRO", "line": "ALL ROUNDER", "stats": {}},
	{"id": "blala", "title": "BALAL", "line": "GLASS CANNON", "stats": GameData.BLALA},
]

var _index := 0
var _cards: Array[Node2D] = []
var _frames: Array[ColorRect] = []
var _starting := false


func _ready() -> void:
	var back := Sprite2D.new()
	back.texture = BACKDROP
	back.centered = false
	back.scale = Vector2.ONE * VIEW.y / BACKDROP.get_height()
	add_child(back)
	var shade := ColorRect.new()
	shade.size = VIEW
	shade.color = Color(0.05, 0.04, 0.09, 0.62)
	add_child(shade)

	_text("BRO ROGUE", Vector2(VIEW.x / 2.0, 18), PixelText.Align.CENTER, 4, YELLOW)
	_text("CHOOSE YOUR BRO", Vector2(VIEW.x / 2.0, 54), PixelText.Align.CENTER, 1, Color("f4f2e8"))

	var gap := 24.0
	var left := (VIEW.x - (CARD.x * CHARACTERS.size() + gap * (CHARACTERS.size() - 1))) / 2.0
	for i in CHARACTERS.size():
		_add_card(i, Vector2(left + i * (CARD.x + gap), 74))
	_text("A/D CHOOSE     J OR ENTER START", Vector2(VIEW.x / 2.0, 252), PixelText.Align.CENTER, 1, DIM)
	_refresh()


func _add_card(i: int, at: Vector2) -> void:
	var data: Dictionary = CHARACTERS[i]
	var stats: Dictionary = GameData.BRO.duplicate()
	stats.merge(data.stats, true)

	var card := Node2D.new()
	card.position = at
	add_child(card)
	_cards.append(card)
	var frame := ColorRect.new()  # the border: yellow on the selected card
	frame.position = Vector2(-2, -2)
	frame.size = CARD + Vector2(4, 4)
	card.add_child(frame)
	_frames.append(frame)
	var panel := ColorRect.new()
	panel.size = CARD
	panel.color = PANEL
	card.add_child(panel)

	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = load("res://assets/sprites/%s_frames.tres" % data.id)
	sprite.position = Vector2(CARD.x / 2.0, 38)
	sprite.scale = Vector2(2, 2)
	var tint: Array = stats.tint
	sprite.self_modulate = Color(tint[0], tint[1], tint[2])
	card.add_child(sprite)
	sprite.play("idle")

	_text(data.title, Vector2(CARD.x / 2.0, 66), PixelText.Align.CENTER, 2, Color("f4f2e8"), card)
	_text(data.line, Vector2(CARD.x / 2.0, 82), PixelText.Align.CENTER, 1, YELLOW, card)
	var range_blocks: float = GameData.BULLET.speed * stats.bullet_lifetime / Block.SIZE
	var rows := [
		"FIRE RATE %d/S" % roundi(1.0 / stats.fire_interval),
		"MAGAZINE %d X %d" % [stats.magazine_size, stats.magazines],
		"RANGE %d BLOCKS" % roundi(range_blocks),
		"SPREAD %d DEG" % roundi(stats.base_spread),
		"RUN SPEED %d" % roundi(stats.speed),
		"KNIFE %d HIT" % stats.knife_hits + ("S" if stats.knife_hits > 1 else ""),
	]
	for r in rows.size():
		_text(rows[r], Vector2(14, 98 + r * 10), PixelText.Align.LEFT, 1, Color("c9c7d6"), card)


func _text(s: String, at: Vector2, align: PixelText.Align, size: int, color: Color, parent: Node = self) -> void:
	var t := PixelText.make(at, align, size)
	t.text = s
	t.color = color
	parent.add_child(t)


func _process(_delta: float) -> void:
	if _starting:
		return
	if Input.is_action_just_pressed("move_left"):
		_index = (_index - 1 + CHARACTERS.size()) % CHARACTERS.size()
		_refresh()
	elif Input.is_action_just_pressed("move_right"):
		_index = (_index + 1) % CHARACTERS.size()
		_refresh()
	elif Input.is_action_just_pressed("shoot") or Input.is_action_just_pressed("jump") or Input.is_key_pressed(KEY_ENTER):
		_start()


func _refresh() -> void:
	for i in _cards.size():
		var picked := i == _index
		_frames[i].color = YELLOW if picked else OUTLINE
		_cards[i].modulate = Color.WHITE if picked else Color(0.62, 0.62, 0.68)
		_cards[i].scale = Vector2.ONE


func _start() -> void:
	_starting = true
	Run.character = CHARACTERS[_index].id
	Run.new_run()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
