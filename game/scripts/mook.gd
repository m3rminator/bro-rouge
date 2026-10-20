extends Enemy
## Enemy soldier. Patrols; if the Bro is in front of him (in range, about his height,
## no blocks between) he shows "!", waits reaction_time, then shoots bursts.
## Numbers: design/entities/mook.yaml (GameData.MOOK). Shared behaviour: enemy.gd.

enum State { PATROL, ALERT, ATTACK }

const MUZZLE: Vector2 = GameData.ANCHORS["mook"]["muzzle"]
const BULLET_MASK := 1 | 2  # world + player

@onready var flash: MuzzleFlash = $Flash

var state := State.PATROL
var _timer := 0.0  # countdown for the current step (reaction, next shot, burst pause)
var _shots_left := 0
var _since_seen := 0.0
var _shot_anim := 0.0


func _ready() -> void:
	stats = GameData.MOOK
	eye = GameData.ANCHORS["mook"]["eye"]
	super()


func _think(delta: float) -> void:
	_shot_anim -= delta
	if state == State.PATROL:
		if sees_player(facing):
			_spot()
		else:
			patrol_step(delta, stats.walk_speed)
	else:
		_fight(delta)


func _fight(delta: float) -> void:
	velocity.x = 0.0
	if sees_player(-facing):  # the Bro jumped over him: turn around
		facing = -facing
	var sees := sees_player(facing)
	_since_seen = 0.0 if sees else _since_seen + delta
	if _since_seen > stats.forget_time:
		state = State.PATROL
		show_alert(false)
		return
	_timer -= delta
	if _timer > 0.0:
		return
	if state == State.ALERT:
		state = State.ATTACK
		show_alert(false)
		_shots_left = stats.burst_count
	if _shots_left == 0:
		_shots_left = stats.burst_count
		_timer = stats.burst_pause
	elif sees:
		_shoot()
		_shots_left -= 1
		_timer = stats.fire_interval


func _spot() -> void:
	state = State.ALERT
	_timer = stats.reaction_time
	_since_seen = 0.0
	velocity.x = 0.0
	show_alert(true)
	Sfx.play(self, "enemy_alert", -6.0)


func _shoot() -> void:
	var muzzle := Vector2(MUZZLE.x * facing, MUZZLE.y)
	Bullet.spawn(get_parent(), position + muzzle, facing, GameData.ENEMY_BULLET, "enemy_shot", BULLET_MASK)
	flash.fire(muzzle, facing)
	_shot_anim = 0.12
	Sfx.play(self, "enemy_shoot", -10.0)


func _on_hurt(_direction: int) -> void:
	if state == State.PATROL:
		_spot()


func _animate() -> void:
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
