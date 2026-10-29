class_name TunnelDoor
extends StaticBody2D
## A wooden door across an underground corridor, three blocks high (level_gen.gd _tunnels cuts the tunnels into rooms
## with them). It shuts the soldiers of one room off from the next: they cannot see through it. When the Bro walks up
## to it, it swings open by itself - away from him, the way he is going, hinged on the far side - and stays open for good.
## Bullets and blasts break it while it is shut (`hit`, `on_blast`). `position` is the middle of its top edge.

const FRAMES := preload("res://assets/sprites/tunnel_door_frames.tres")
const HEIGHT := Block.SIZE * 3.0
const WIDTH := 8.0
const WOOD := Color("6e4527")
const OPEN_TIME := 0.3
const WAKE := 22.0  # how near (sideways) the Bro has to be for it to open

var _hp := 6
var _open := 0.0  # 0 shut .. 1 open
var _opening := false
var _way := 1  # which side it falls to
var _shape: CollisionShape2D
var _sprite: AnimatedSprite2D


func _init() -> void:
	collision_layer = 1
	collision_mask = 0
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(6, HEIGHT)
	_shape.shape = rect
	_shape.position = Vector2(0, HEIGHT / 2.0)
	add_child(_shape)


func _ready() -> void:
	z_index = 1
	_sprite = AnimatedSprite2D.new()  # 64x78 frames; the shut door's top edge middle (32, 3) sits on the node origin
	_sprite.sprite_frames = FRAMES
	_sprite.centered = false
	_sprite.offset = Vector2(-32, -3)
	_sprite.animation = "shut"
	add_child(_sprite)


func _process(delta: float) -> void:
	if not _opening:
		var p := get_tree().get_first_node_in_group("player")
		if p == null or p.dead:
			return
		var d: Vector2 = p.global_position - global_position
		if absf(d.x) < WAKE and d.y > -12.0 and d.y < HEIGHT + 12.0:
			_opening = true
			_way = 1 if d.x < 0.0 else -1  # away from him: the way he is going
			_sprite.flip_h = _way < 0  # the art opens to the right
			_sprite.play("opening")
			Sfx.play(self, "block_hit", -14.0)
	if _opening and _open < 1.0:
		_open = move_toward(_open, 1.0, delta / OPEN_TIME)
		if _open > 0.3:
			_shape.set_deferred("disabled", true)
		if _open >= 1.0:
			_sprite.play("open")


func hit(_damage: int, _direction := 0) -> void:
	if _opening:
		return
	_hp -= 1
	if _hp <= 0:
		_break()
	else:
		Sfx.play(self, "block_hit", -8.0)


func on_blast(center: Vector2, power: Dictionary) -> void:
	var mid := global_position + Vector2(0, HEIGHT / 2.0)
	if mid.distance_to(center) <= power.radius * GameData.EXPLOSION.core_share + Block.SIZE:
		_break()


func _break() -> void:
	Sfx.play(self, "block_break", -4.0)
	for k in 3:
		DirtDebris.burst(get_parent(), position + Vector2(0, Block.SIZE * (k + 0.5)), WOOD, 6)
	queue_free()
