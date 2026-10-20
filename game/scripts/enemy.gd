class_name Enemy
extends CharacterBody2D
## Shared enemy behaviour: line of sight, patrolling, blood on every hit, death (kill count,
## blood burst, a body that stays in a pool of blood), and being tossed by explosions.
## Subclasses set `stats` / `eye` before calling super._ready() and implement _think().

signal health_changed(hp: int, max_hp: int)

const FX_FRAMES := preload("res://assets/sprites/fx_frames.tres")
const WORLD_MASK := 1
const CORPSE_LAYER := 8  # physics layer 4 "corpses": only explosions touch bodies

@onready var sprite: AnimatedSprite2D = $Sprite

var stats: Dictionary
var eye := Vector2.ZERO  # eye anchor relative to the body origin (facing right)
var facing := -1
var hp := 1
var dead := false
var death_sound := "enemy_death"
var _pause := 0.0
var _pooled := false
var _bubble: AnimatedSprite2D


func _ready() -> void:
	add_to_group("enemies")
	z_index = 2
	hp = stats.hp
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
	velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
	move_and_slide()
	if is_on_floor() and not _pooled:
		_pooled = true
		Blood.pool_under(self)


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


## Called by bullets. `direction` = which way the bullet was flying.
func hit(damage: int, direction := 0) -> void:
	if dead:
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
	_pooled = false  # leaves another pool where it lands
	create_tween().tween_property(sprite, "rotation", sprite.rotation + TAU * dir, 0.6)


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


## Default death: knocked back, falls over, body stays.
func _on_death(direction: int) -> void:
	Sfx.play(self, death_sound, -4.0)
	sprite.play("hurt")
	var push := direction if direction != 0 else -facing
	velocity = Vector2(push * 80.0, -140.0)
	var tween := create_tween().set_parallel()
	tween.tween_property(sprite, "rotation", PI / 2 * push, 0.35)
	tween.tween_property(sprite, "position:y", sprite.position.y + 3.0, 0.35)
