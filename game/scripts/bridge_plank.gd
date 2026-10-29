class_name BridgePlank
extends AnimatableBody2D
## One plank of a RopeBridge: a thin board he walks on. `position` is the middle of its top edge. Bullets and blasts break
## it; a broken plank falls away (no collision any more) and tells the bridge.

signal broken(plank: BridgePlank)

const WOOD := Color("7a5230")
const WOOD_LIGHT := Color("a0713f")
const WOOD_DARK := Color("4a301c")
const THICK := 6
const BEVEL := 2.0

var index := 0
var falling := false
var _hp := 2
var _vel := Vector2.ZERO
var _spin := 0.0
var _shape: CollisionShape2D


func _init() -> void:
	collision_layer = 1
	collision_mask = 0
	sync_to_physics = true
	_shape = CollisionShape2D.new()
	var half := Block.SIZE / 2.0  # the top corners are cut at 45 degrees, so a step of a pixel or two between boards is a slope
	var board := ConvexPolygonShape2D.new()
	board.points = PackedVector2Array([Vector2(-half, BEVEL), Vector2(-half + BEVEL, 0), Vector2(half - BEVEL, 0), Vector2(half, BEVEL), Vector2(half, THICK), Vector2(-half, THICK)])
	_shape.shape = board
	add_child(_shape)


func _draw() -> void:
	var half := Block.SIZE / 2.0
	draw_rect(Rect2(-half, 0, Block.SIZE, THICK), WOOD)
	draw_rect(Rect2(-half, 0, Block.SIZE, 1), WOOD_LIGHT)
	draw_rect(Rect2(-half, THICK - 1, Block.SIZE, 1), WOOD_DARK)
	draw_rect(Rect2(-half, 0, 1, THICK), WOOD_DARK)  # the gap to the next board
	draw_rect(Rect2(-half + 3, 2, 1, 2), WOOD_DARK)  # nails
	draw_rect(Rect2(half - 4, 2, 1, 2), WOOD_DARK)


func hit(_damage: int, _direction := 0) -> void:
	if falling:
		return
	_hp -= 1
	if _hp <= 0:
		Sfx.play(self, "block_break", -4.0)
		snap()
	else:
		Sfx.play(self, "block_hit", -10.0)


func on_blast(center: Vector2, power: Dictionary) -> void:
	if global_position.distance_to(center) <= power.radius * GameData.EXPLOSION.core_share + Block.SIZE / 2.0:
		snap()


## Breaks off: it falls (turning a little), nothing stands on it any more.
func snap() -> void:
	if falling:
		return
	falling = true
	_shape.set_deferred("disabled", true)
	sync_to_physics = false
	_vel = Vector2(randf_range(-30.0, 30.0), -20.0)
	_spin = randf_range(-3.0, 3.0)
	DirtDebris.burst(get_parent(), position + Vector2(0, THICK), WOOD, 5)
	broken.emit(self)


func _process(delta: float) -> void:
	if not falling:
		return
	_vel.y += 900.0 * delta
	position += _vel * delta
	rotation += _spin * delta
	if position.y > (LevelGen.ROWS + 60) * Block.SIZE:
		queue_free()
