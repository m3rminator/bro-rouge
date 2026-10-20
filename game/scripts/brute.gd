extends Enemy
## Brute mini-boss: about three blocks tall, two miniguns. Sees far and high, hears the Bro behind
## him, spins up, then sprays long alternating bursts in a wide fan.
## Numbers: design/entities/brute.yaml (GameData.BRUTE). Shared behaviour: enemy.gd.

signal engaged(brute: Node)

enum State { PATROL, SPIN, FIRE, PAUSE }

const MUZZLES := [GameData.ANCHORS["brute"]["muzzle_top"], GameData.ANCHORS["brute"]["muzzle_bottom"]]
const BULLET_MASK := 1 | 2  # world + player

@onready var flashes: Array = [$FlashTop, $FlashBottom]

var state := State.PATROL
var _timer := 0.0
var _shot_timer := 0.0
var _since_seen := 0.0
var _gun := 0
var _engaged := false


func _ready() -> void:
	stats = GameData.BRUTE
	eye = GameData.ANCHORS["brute"]["eye"]
	sprite_name = "brute"
	death_sound = "brute_death"
	add_to_group("bosses")
	super()


func _think(delta: float) -> void:
	var sees := sees_player(facing)
	if not sees and _hears_behind():
		facing = -facing
		sees = sees_player(facing)
	if state == State.PATROL:
		if sees:
			_spot()
		else:
			patrol_step(delta, stats.walk_speed)
		return
	velocity.x = 0.0
	_since_seen = 0.0 if sees else _since_seen + delta
	if _since_seen > stats.forget_time:
		state = State.PATROL
		return
	_timer -= delta
	match state:
		State.SPIN, State.PAUSE:
			if _timer <= 0.0:
				state = State.FIRE
				_timer = stats.burst_time
				_shot_timer = 0.0
				Sfx.play(self, "minigun_fire", -6.0, 0.03)
		State.FIRE:
			_shot_timer -= delta
			if _shot_timer <= 0.0:
				_fire()
				_shot_timer = stats.fire_interval
			if _timer <= 0.0:
				state = State.PAUSE
				_timer = stats.burst_pause


func _hears_behind() -> bool:
	var p := player()
	if p == null or global_position.distance_to(p.global_position) > stats.hearing_range:
		return false
	if signf(p.global_position.x - global_position.x) != -facing:
		return false
	return ray(global_position + Vector2(0, eye.y), p.global_position).is_empty()


func _spot() -> void:
	state = State.SPIN
	_timer = stats.spin_up
	_since_seen = 0.0
	velocity.x = 0.0
	if not _engaged:
		_engaged = true
		engaged.emit(self)
		show_alert(true)
		get_tree().create_timer(1.0).timeout.connect(show_alert.bind(false))
		Sfx.play(self, "brute_alert", -2.0)
	Sfx.play(self, "minigun_spinup", -6.0)


## One bullet from the next gun, at a random angle inside the fan.
func _fire() -> void:
	var anchor: Vector2 = MUZZLES[_gun] + sprite.position
	var muzzle := Vector2(anchor.x * facing, anchor.y)
	var half: float = stats.spread_angle / 2.0
	Bullet.spawn(get_parent(), position + muzzle, facing, GameData.MINIGUN_BULLET, "minigun_shot", BULLET_MASK,
			randf_range(-half, half))
	flashes[_gun].fire(muzzle, facing)
	_gun = 1 - _gun


func _on_hurt(_direction: int) -> void:
	if state == State.PATROL:
		_spot()


## He is too big to fall over: slumps where he stands, blood everywhere.
func _on_death(_direction: int) -> void:
	Sfx.play(self, death_sound, -2.0)
	sprite.play("hurt")
	velocity = Vector2.ZERO
	Blood.burst(get_parent(), global_position + Vector2(0, -24))
	Blood.burst(get_parent(), global_position + Vector2(6 * facing, -6))


func toss(dir: int, speed: float) -> void:
	velocity = Vector2(dir * speed * 0.2, -speed * 0.3)  # heavy: barely moves
	_pooled = false


## Too big to lie down or flail: his body stays slumped (hurt pose) and only slides a little.
func _fly() -> void:
	_pooled = false


func _lie() -> void:
	_lying = true
	var box: RectangleShape2D = $Collision.shape
	box.size = Vector2(stats.hitbox[0] + 8, stats.hitbox[1] * 0.6)
	$Collision.position.y = 8.0 - box.size.y / 2.0


func _animate() -> void:
	sprite.flip_h = facing < 0
	var anim := "idle"
	match state:
		State.SPIN, State.PAUSE:
			anim = "spin"
		State.FIRE:
			anim = "shoot"
		_:
			anim = "walk" if velocity.x != 0.0 else "idle"
	if sprite.animation != anim:
		sprite.play(anim)
