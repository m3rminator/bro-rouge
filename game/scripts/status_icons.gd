class_name StatusIcons
extends Node2D
## The effects the Bro has on him, as small icons over his head (no numbers): a crate boost running (more magazine, faster
## fire, speed, damage), Bruce's fury, and - beside the shield icon - a lock while the shield keeps him from moving.
## An icon blinks when its time is nearly up. Child of the player; drawn in code.

const LOW_TIME := 3.0
const GAP := 2
const OUTLINE := Color("1f1b2c")
const LOCK := [
	"..ooo..",
	".o...o.",
	".o...o.",
	"ooooooo",
	"oyyyyyo",
	"oyyKyyo",
	"oyyKyyo",
	"oyyyyyo",
	"ooooooo",
]
const FLAME := [
	"...o...",
	"..oro..",
	"..orro.",
	".orrrro",
	".orYrro",
	"orrYYro",
	"orYYYro",
	"orYYYro",
	".orrrr.",
]
const BOLT := [
	"....cc.",
	"...cc..",
	"..cc...",
	".ccccc.",
	"...cc..",
	"..cc...",
	".cc....",
]
const BURST := [
	"r..r..r",
	".r.Y.r.",
	"..rYr..",
	"rYYYYYr",
	"..rYr..",
	".r.Y.r.",
	"r..r..r",
]
const COLORS := {
	"o": Color("1f1b2c"), "y": Color("ffd23e"), "K": Color("1f1b2c"), "r": Color("ff4a2a"), "Y": Color("ffd23e"),
	"c": Color("6fe0ff"), "b": Color("c98a4a"),
}

var player: Node2D
var _marks: Array = []  # [kind, seconds left] of the icons shown now


func _ready() -> void:
	z_index = 6


func _process(_delta: float) -> void:
	var now := _collect()
	if now != _marks or _blinking(now):
		_marks = now
		queue_redraw()


func _collect() -> Array:
	var out := []
	for kind in ["mag", "rate", "speed", "damage"]:
		if Run.upgrades.has(kind):
			out.append([kind, snappedf(Run.upgrades[kind], 0.1)])
	if player != null and is_instance_valid(player) and player.has_method("fury_left") and player.fury_left() > 0.0:
		out.append(["fury", snappedf(player.fury_left(), 0.1)])
	return out


func _blinking(marks: Array) -> bool:
	for m in marks:
		if m[1] < LOW_TIME:
			return true
	return false


func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return
	var shielded: bool = player.has_method("shield_up") and player.shield_up()
	var top := -50.0 if shielded else -38.0  # above the shield icon when there is one
	if shielded and player.movement_locked():
		_art(LOCK, Vector2(12, -39))  # beside the shield icon
	var shown := []
	for m in _marks:
		if m[1] >= LOW_TIME or fmod(m[1], 0.4) < 0.25:
			shown.append(m[0])
	var width := 0
	for kind: String in shown:
		width += _width(kind) + GAP
	var x := -(width - GAP) / 2.0
	for kind: String in shown:
		_icon(kind, Vector2(roundf(x), top))
		x += _width(kind) + GAP


func _width(kind: String) -> int:
	return 8 if kind == "mag" else (11 if kind == "rate" else 7)


func _icon(kind: String, at: Vector2) -> void:
	match kind:
		"fury":
			_art(FLAME, at)
		"speed":
			_art(BOLT, at + Vector2(0, 1))
		"damage":
			_art(BURST, at + Vector2(0, 1))
		"mag":
			for bx in [0, 5]:  # two cartridges
				draw_rect(Rect2(at + Vector2(bx - 1, -1), Vector2(5, 11)), OUTLINE)
				draw_rect(Rect2(at + Vector2(bx, 0), Vector2(3, 3)), COLORS.b)
				draw_rect(Rect2(at + Vector2(bx, 3), Vector2(3, 6)), COLORS.y)
		"rate":
			for i in 3:  # three arrows forward
				for k in 5:
					var px := i * 4 + (2 - absi(k - 2))
					draw_rect(Rect2(at + Vector2(px + 1, k + 2), Vector2(2, 1)), OUTLINE)
				for k in 5:
					var px := i * 4 + (2 - absi(k - 2))
					draw_rect(Rect2(at + Vector2(px, k + 1), Vector2(2, 1)), COLORS.r.lerp(COLORS.y, i / 2.0))


func _art(map: Array, at: Vector2) -> void:
	for y in map.size():
		var row: String = map[y]
		for x in row.length():
			var ch := row[x]
			if ch != ".":
				draw_rect(Rect2(at + Vector2(x - row.length() / 2, y), Vector2.ONE), COLORS[ch])
