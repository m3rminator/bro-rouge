class_name BloodFountain
extends Node2D
## A gusher of blood where a Bro left the level: sprays up and back into the play area for
## `duration` seconds, using real drops that stain the blocks (BloodDrops).

const DURATION := 1.4
const EVERY := 0.05

var _age := 0.0
var _next := 0.0


static func start(parent: Node, pos: Vector2) -> void:
	var fountain := BloodFountain.new()
	fountain.position = pos
	parent.add_child(fountain)
	Blood.gore(parent, pos)
	Sfx.play(fountain, "block_break", -4.0)


func _physics_process(delta: float) -> void:
	_age += delta
	_next -= delta
	if _next <= 0.0:
		_next = EVERY
		var strength := 1.0 - _age / DURATION  # the gusher weakens
		BloodDrops.emit(get_parent(), position, Vector2.UP, 6, 28.0, 260.0 * (0.5 + strength))
	if _age >= DURATION:
		queue_free()
