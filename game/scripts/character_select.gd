class_name CharacterCards
extends Object
## The Bro cards (picture, name and numbers read from the stats). Shown by bro_picker.gd, which the
## start-zone box and the random crates use to deal Bros. Run.character is set from the card picked.

const CARD := Vector2(104, 160)
const YELLOW := Color("ffd23e")
const PANEL := Color("23202f")
const OUTLINE := Color("14101e")

## id (Run.character), title, one-line summary, GameData stats laid over the Bro's.
const CHARACTERS := [
	{"id": "bro", "title": "BRO", "line": "ALL ROUNDER", "stats": {}},
	{"id": "blala", "title": "BALAL", "line": "GLASS CANNON", "stats": GameData.BLALA},
	{"id": "sharif", "title": "SHARIF", "line": "SHOTGUNNER", "stats": GameData.SHARIF},
	{"id": "heavy", "title": "HAMID", "line": "MINIGUNNER", "stats": GameData.HEAVY},
	{"id": "mib", "title": "MIB", "line": "RAYGUNNER", "stats": GameData.MIB},
]


static func ids() -> Array:
	return CHARACTERS.map(func(c): return c.id)


## A card node at `at`; its child "Frame" is the border (the picker colours it).
static func build(id: String, at: Vector2) -> Node2D:
	var data: Dictionary = {}
	for c in CHARACTERS:
		if c.id == id:
			data = c
	var stats: Dictionary = GameData.BRO.duplicate()
	stats.merge(data.stats, true)
	var card := Node2D.new()
	card.position = at
	var frame := ColorRect.new()
	frame.name = "Frame"
	frame.position = Vector2(-2, -2)
	frame.size = CARD + Vector2(4, 4)
	card.add_child(frame)
	var panel := ColorRect.new()
	panel.size = CARD
	panel.color = PANEL
	card.add_child(panel)

	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = load("res://assets/sprites/%s_frames.tres" % Run.look_of(id))
	sprite.position = Vector2(CARD.x / 2.0, 38)
	sprite.scale = Vector2(2, 2)
	var tint: Array = stats.tint
	sprite.self_modulate = Color(tint[0], tint[1], tint[2])
	card.add_child(sprite)
	sprite.play("idle")

	_text(data.title, Vector2(CARD.x / 2.0, 66), PixelText.Align.CENTER, 2, Color("f4f2e8"), card)
	_text(data.line, Vector2(CARD.x / 2.0, 82), PixelText.Align.CENTER, 1, YELLOW, card)
	var range_blocks: float = GameData.BULLET.speed * stats.bullet_lifetime / Block.SIZE
	if stats.weapon == "raygun":
		range_blocks = GameData.RAYGUN.range / Block.SIZE
	var rows := [
		"FIRE RATE %d/S" % roundi(1.0 / stats.fire_interval),
		("SHELLS %d" % stats.shells_start) if stats.shells_start > 0 else ("MAGAZINE %d X %d" % [stats.magazine_size, stats.magazines]),
		"RANGE %d BLOCKS" % roundi(range_blocks),
		"SPREAD %d DEG" % roundi(stats.base_spread),
		"RUN SPEED %d" % roundi(stats.speed),
		"KNIFE %d HIT" % stats.get("knife_hits_plain", 1) + ("S" if stats.get("knife_hits_plain", 1) > 1 else ""),
	]
	for r in rows.size():
		_text(rows[r], Vector2(14, 98 + r * 10), PixelText.Align.LEFT, 1, Color("c9c7d6"), card)
	return card


static func _text(s: String, at: Vector2, align: PixelText.Align, size: int, color: Color, parent: Node) -> void:
	var t := PixelText.make(at, align, size)
	t.text = s
	t.color = color
	parent.add_child(t)
