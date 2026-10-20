extends CharacterBody2D
## The Bro: run, jump, hold to shoot.

## Tuning numbers live in design/entities/bro.yaml (generated into GameData.BRO).
const STATS := GameData.BRO
const MUZZLE: Vector2 = GameData.ANCHORS["bro"]["muzzle"]
const FX_FRAMES := preload("res://assets/sprites/fx_frames.tres")

@onready var sprite: AnimatedSprite2D = $Sprite

var facing := 1
var fire_cooldown := 0.0
var shooting := 0.0
var flash: AnimatedSprite2D


func _ready() -> void:
	flash = AnimatedSprite2D.new()
	flash.sprite_frames = FX_FRAMES
	flash.visible = false
	flash.animation_finished.connect(func(): flash.visible = false)
	add_child(flash)
	sprite.frame_changed.connect(_on_frame_changed)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += STATS.gravity * delta

	var dir := Input.get_axis("move_left", "move_right")
	velocity.x = dir * STATS.speed
	if dir != 0:
		facing = 1 if dir > 0 else -1
		sprite.flip_h = facing < 0

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = STATS.jump_velocity
		Sfx.play(self, "jump", -4.0)

	var was_on_floor := is_on_floor()
	move_and_slide()
	if not was_on_floor and is_on_floor():
		Sfx.play(self, "land", -6.0)

	fire_cooldown -= delta
	shooting -= delta
	if Input.is_action_pressed("shoot") and fire_cooldown <= 0.0:
		_shoot()

	_update_animation(dir)


func _shoot() -> void:
	fire_cooldown = STATS.fire_interval
	shooting = 0.15
	var muzzle := Vector2(MUZZLE.x * facing, MUZZLE.y)
	var bullet := Bullet.new()
	bullet.direction = facing
	bullet.global_position = global_position + muzzle
	get_parent().add_child(bullet)

	flash.position = muzzle + Vector2(3 * facing, 0)
	flash.flip_h = facing < 0
	flash.visible = true
	flash.play("muzzle")
	flash.frame = 0
	Sfx.play(self, "shoot", -8.0)


func _update_animation(dir: float) -> void:
	var anim := "idle"
	if not is_on_floor():
		anim = "jump"
	elif dir != 0:
		anim = "run"
	elif shooting > 0.0:
		anim = "shoot"
	if sprite.animation != anim:
		sprite.play(anim)


func _on_frame_changed() -> void:
	if sprite.animation == "run" and sprite.frame % 2 == 0:
		Sfx.play(self, "footstep", -14.0, 0.15)
