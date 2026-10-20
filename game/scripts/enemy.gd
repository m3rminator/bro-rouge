class_name Enemy
extends CharacterBody2D
## Shared enemy behaviour: line of sight, patrolling, blood on every hit, death (kill count,
## blood burst, a body that stays in a pool of blood), and being tossed by explosions.
## Bodies stay physical: the Bro bumps and drags them, bullets knock them back
## (design/entities/corpse.yaml, GameData.CORPSE).
## Subclasses set `stats` / `eye` / `sprite_name` before calling super._ready() and implement _think().

signal health_changed(hp: int, max_hp: int)

const FX_FRAMES := preload("res://assets/sprites/fx_frames.tres")
const WORLD_MASK := 1
const CORPSE_LAYER := 8  # physics layer 4 "corpses": explosions and the Bro's bullets touch bodies
const CORPSE := GameData.CORPSE

@onready var sprite: AnimatedSprite2D = $Sprite

var stats: Dictionary
var eye := Vector2.ZERO  # eye anchor relative to the body origin (facing right)
var sprite_name := ""  # art/sprites/<name>.yaml — places the frame so the feet are on the tile bottom
var facing := -1
var hp := 1
var dead := false
var death_sound := "enemy_death"
var _pause := 0.0
var _pooled := false
var _pool_x := INF  # where the last pool was left (a new one only after the body moved)
var _bubble: AnimatedSprite2D
var _lying := false
var _bumped := false  # the Bro is walking through this body right now


func _ready() -> void:
	add_to_group("enemies")
	z_index = 2
	hp = stats.hp
	if sprite_name != "":
		sprite.position.y = 8.0 - GameData.SPRITE_SIZES[sprite_name].y / 2.0
		eye += Vector2(0, sprite.position.y)
	$Collision.shape = $Collision.shape.duplicate()  # every body gets its own box (it changes when he dies)
	var box: RectangleShape2D = $Collision.shape
	box.size = Vector2(stats.hitbox[0], stats.hitbox[1])
	$Collision.position.y = 8 - stats.hitbox[1] / 2.0  # feet on the bottom of the start tile
	_bubble = AnimatedSprite2D.new()
	_bubble.sprite_frames = FX_FRAMES
	_bubble.animation = "alert"
	_bubble.position = Vector2(0, 2 - stats.hitbox[1] - 6)
	_bubble.visible = false
	add_child(_bubble)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += stats.gravity * delta
	if dead:
		_dead_process(delta)
		return
	_think(delta)
	move_and_slide()
	_animate()


## AI step for living enemies — set velocity here. Overridden by every enemy.
func _think(_delta: float) -> void:
	pass


func _animate() -> void:
	pass


func _dead_process(delta: float) -> void:
	_bump(delta)
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, CORPSE.friction * delta)
	move_and_slide()
	if is_on_floor() and not _lying and velocity.y >= 0.0:
		_lie()
	if is_on_floor() and not _pooled and absf(velocity.x) < 20.0:
		_pooled = true
		if absf(global_position.x - _pool_x) > 12.0:
			_pool_x = global_position.x
			Blood.pool_under(self)


## The Bro walking through a body: a small hop and a push the first moment, then it is
## dragged along while he keeps walking.
func _bump(delta: float) -> void:
	var p := player()
	var touching := false
	if p != null:
		var box: RectangleShape2D = $Collision.shape
		var dx: float = p.global_position.x - global_position.x
		touching = absf(dx) < box.size.x / 2.0 + 6.0 and absf(p.global_position.y - global_position.y) < 14.0 \
				and absf(p.velocity.x) > 20.0
		if touching:
			var mass: float = stats.get("mass", 1.0)
			if not _bumped:
				velocity.x = p.velocity.x * CORPSE.bump_speed / mass
				velocity.y = CORPSE.bump_hop / mass
				_fly()
			elif is_on_floor():
				velocity.x = move_toward(velocity.x, p.velocity.x * CORPSE.drag / mass, 600.0 * delta)
	_bumped = touching


## Body leaves the ground: flailing pose.
func _fly() -> void:
	_lying = false
	_pooled = false  # leaves another pool where it lands
	sprite.play("hurt")
	sprite.rotation = 0.0
	sprite.position = Vector2(0, 8.0 - sprite.sprite_frames.get_frame_texture("hurt", 0).get_height() / 2.0)


## Body on the ground: the "dead" pose (lying on its back, drawn in the sprite) and a low,
## wide collision box that the Bro's bullets can still hit.
func _lie() -> void:
	_lying = true
	sprite.play("dead")
	sprite.rotation = 0.0
	sprite.position = Vector2(0, 8.0 - GameData.SPRITE_SIZES[sprite_name].y / 2.0)
	var box: RectangleShape2D = $Collision.shape
	box.size = Vector2(stats.hitbox[1] * 0.8, CORPSE.lying_height)
	$Collision.position.y = 8.0 - CORPSE.lying_height / 2.0


func player() -> Node2D:
	var p := get_tree().get_first_node_in_group("player")
	return null if p == null or p.dead else p


## True if the Bro is visible looking in `dir`: in range, about eye height, nothing solid between.
func sees_player(dir: int) -> bool:
	var p := player()
	if p == null:
		return false
	var eye_pos := global_position + Vector2(eye.x * dir, eye.y)
	var to_player: Vector2 = p.global_position - eye_pos
	if signf(to_player.x) != dir or absf(to_player.x) > stats.vision_range or absf(to_player.y) > stats.vision_height:
		return false
	return ray(eye_pos, p.global_position).is_empty()


## Walk in `facing`; at a wall or ledge stop for turn_pause, then walk back.
func patrol_step(delta: float, speed: float) -> void:
	if _pause > 0.0:
		_pause -= delta
		velocity.x = 0.0
		return
	if is_on_floor() and (is_on_wall() or not ground_ahead()):
		facing = -facing
		_pause = stats.turn_pause
		velocity.x = 0.0
		return
	velocity.x = facing * speed


func ground_ahead() -> bool:
	var foot := global_position + Vector2(facing * (stats.hitbox[0] / 2.0 + 2.0), 4)
	return not ray(foot, foot + Vector2(0, 12)).is_empty()


func ray(from: Vector2, to: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, WORLD_MASK)
	return get_world_2d().direct_space_state.intersect_ray(query)


func show_alert(on: bool) -> void:
	_bubble.visible = on


## Called by bullets. `direction` = which way the bullet was flying. A body is knocked back.
func hit(damage: int, direction := 0) -> void:
	if dead:
		_shot_body(direction)
		return
	hp -= damage
	health_changed.emit(maxi(hp, 0), stats.hp)
	Blood.spray(get_parent(), global_position + Vector2(0, 6 - stats.hitbox[1] / 2.0), direction if direction != 0 else -facing)
	if direction == facing:  # shot from behind: turn to face the shooter
		facing = -facing
	sprite.modulate = Color(3, 3, 3)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.08)
	if hp <= 0:
		die(direction)
	else:
		_on_hurt(direction)


## Called by explosions (explosion.gd). Living enemies take blast damage; bodies get tossed.
func on_blast(center: Vector2, power: Dictionary) -> void:
	var dir := 1 if global_position.x >= center.x else -1
	if not dead:
		hit(power.damage, dir)
	if dead:
		toss(dir, GameData.EXPLOSION.fling_speed)


func toss(dir: int, speed: float) -> void:
	velocity = Vector2(dir * speed * 0.5, -speed)
	_fly()
	create_tween().tween_property(sprite, "rotation", TAU * dir, 0.6)


func _shot_body(direction: int) -> void:
	var dir := direction if direction != 0 else 1
	var mass: float = stats.get("mass", 1.0)
	Blood.spray(get_parent(), global_position + Vector2(0, 2), dir)
	velocity = Vector2(dir * CORPSE.shot_knockback / mass, CORPSE.shot_hop / mass)
	_fly()


func die(direction: int) -> void:
	dead = true
	collision_layer = CORPSE_LAYER
	z_index = 1
	show_alert(false)
	Run.add_kill()
	Blood.burst(get_parent(), global_position + Vector2(0, 8 - stats.hitbox[1] / 2.0))
	Sfx.play(self, "blood_splat", -6.0)
	_on_death(direction)


func _on_hurt(_direction: int) -> void:
	pass


## Default death: knocked back flailing, then lies flat where it lands; the body stays.
func _on_death(direction: int) -> void:
	Sfx.play(self, death_sound, -4.0)
	var push := direction if direction != 0 else -facing
	velocity = Vector2(push * 80.0, -140.0)
	_fly()
