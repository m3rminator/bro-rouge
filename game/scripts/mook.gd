extends CharacterBody2D
## Enemy soldier. Patrols; if the Bro is in front of him (in range, about his height,
## no blocks between) he shows "!", waits reaction_time, then shoots bursts.
## Numbers: design/entities/mook.yaml (GameData.MOOK).

enum State { PATROL, ALERT, ATTACK, DEAD }

const STATS := GameData.MOOK
const MUZZLE: Vector2 = GameData.ANCHORS["mook"]["muzzle"]
const EYE: Vector2 = GameData.ANCHORS["mook"]["eye"]
const FX_FRAMES := preload("res://assets/sprites/fx_frames.tres")
const BULLET_MASK := 1 | 2  # world + player
const WORLD_MASK := 1

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var flash: MuzzleFlash = $Flash

var state := State.PATROL
var facing := -1
var hp: int = STATS.hp
var _timer := 0.0  # countdown for the current step (reaction, next shot, burst pause)
var _shots_left := 0
var _since_seen := 0.0
var _pause := 0.0
var _shot_anim := 0.0
var _bubble: AnimatedSprite2D


func _ready() -> void:
	add_to_group("enemies")
	z_index = 2
	var box: RectangleShape2D = $Collision.shape
	box.size = Vector2(STATS.hitbox[0], STATS.hitbox[1])
	$Collision.position.y = 8 - STATS.hitbox[1] / 2.0
	_bubble = AnimatedSprite2D.new()
	_bubble.sprite_frames = FX_FRAMES
	_bubble.animation = "alert"
	_bubble.position = Vector2(0, -14)
	_bubble.visible = false
	add_child(_bubble)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += STATS.gravity * delta
	match state:
		State.PATROL:
			_patrol(delta)
		State.ALERT, State.ATTACK:
			_fight(delta)
		State.DEAD:
			velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
	move_and_slide()
	_shot_anim -= delta
	_animate()


func _patrol(delta: float) -> void:
	if _sees_player(facing):
		_spot()
		return
	if _pause > 0.0:
		_pause -= delta
		velocity.x = 0.0
		return
	if is_on_floor() and (is_on_wall() or not _ground_ahead()):
		facing = -facing
		_pause = STATS.turn_pause
		velocity.x = 0.0
		return
	velocity.x = facing * STATS.walk_speed


func _fight(delta: float) -> void:
	velocity.x = 0.0
	if _sees_player(-facing):  # the Bro jumped over him: turn around
		facing = -facing
	var sees := _sees_player(facing)
	_since_seen = 0.0 if sees else _since_seen + delta
	if _since_seen > STATS.forget_time:
		state = State.PATROL
		_bubble.visible = false
		return
	_timer -= delta
	if _timer > 0.0:
		return
	if state == State.ALERT:
		state = State.ATTACK
		_bubble.visible = false
		_shots_left = STATS.burst_count
	if _shots_left == 0:
		_shots_left = STATS.burst_count
		_timer = STATS.burst_pause
	elif sees:
		_shoot()
		_shots_left -= 1
		_timer = STATS.fire_interval


func _spot() -> void:
	state = State.ALERT
	_timer = STATS.reaction_time
	_since_seen = 0.0
	velocity.x = 0.0
	_bubble.visible = true
	Sfx.play(self, "enemy_alert", -6.0)


func _shoot() -> void:
	var muzzle := Vector2(MUZZLE.x * facing, MUZZLE.y)
	Bullet.spawn(get_parent(), position + muzzle, facing, GameData.ENEMY_BULLET, "enemy_bullet", BULLET_MASK)
	flash.fire(muzzle, facing)
	_shot_anim = 0.12
	Sfx.play(self, "enemy_shoot", -10.0)


## True if the Bro is visible looking in `dir`: in range, about eye height, nothing solid between.
func _sees_player(dir: int) -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or player.dead:
		return false
	var eye := global_position + Vector2(EYE.x * dir, EYE.y)
	var to_player: Vector2 = player.global_position - eye
	if signf(to_player.x) != dir or absf(to_player.x) > STATS.vision_range or absf(to_player.y) > STATS.vision_height:
		return false
	return _ray(eye, player.global_position).is_empty()


func _ground_ahead() -> bool:
	var foot := global_position + Vector2(facing * 7, 4)
	return not _ray(foot, foot + Vector2(0, 12)).is_empty()


func _ray(from: Vector2, to: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, WORLD_MASK)
	return get_world_2d().direct_space_state.intersect_ray(query)


## Called by the Bro's bullets. `direction` = which way the bullet was flying.
func hit(damage: int, direction := 0) -> void:
	if state == State.DEAD:
		return
	hp -= damage
	if direction == facing:  # shot from behind: turn to face the shooter
		facing = -facing
	sprite.modulate = Color(3, 3, 3)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.08)
	if hp <= 0:
		_die(direction)
	elif state == State.PATROL:
		_spot()


func _die(direction: int) -> void:
	state = State.DEAD
	collision_layer = 0
	z_index = 1
	_bubble.visible = false
	Sfx.play(self, "enemy_death", -4.0)
	sprite.play("hurt")
	var push := direction if direction != 0 else -facing
	velocity = Vector2(push * 80.0, -140.0)
	var tween := create_tween().set_parallel()
	tween.tween_property(sprite, "rotation", PI / 2 * push, 0.35)
	tween.tween_property(sprite, "position:y", 3.0, 0.35)
	await get_tree().create_timer(STATS.corpse_time).timeout
	await create_tween().tween_property(sprite, "modulate:a", 0.0, 0.5).finished
	queue_free()


func _animate() -> void:
	if state == State.DEAD:
		return
	sprite.flip_h = facing < 0
	var anim := "idle"
	if not is_on_floor():
		anim = "fall"
	elif _shot_anim > 0.0:
		anim = "shoot"
	elif velocity.x != 0.0:
		anim = "walk"
	if sprite.animation != anim:
		sprite.play(anim)
