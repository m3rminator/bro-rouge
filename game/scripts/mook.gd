class_name Mook
extends Enemy
## Enemy soldier. Patrols; if the Bro is in front of him (in range, about his height,
## no blocks between) he shows "!", waits reaction_time, then shoots bursts.
## Numbers: design/entities/mook.yaml (GameData.MOOK). Shared behaviour: enemy.gd.

enum State { PATROL, ALERT, ATTACK }

const BULLET_MASK := 1 | 2  # world + player

@onready var flash: MuzzleFlash = $Flash

var sheet := "mook"  # sprite sheet / anchors name (vest and helmet soldiers reuse this script)
var state := State.PATROL
var _timer := 0.0  # countdown for the current step (reaction, next shot, burst pause)
var _shots_left := 0
var _since_seen := 0.0
var _shot_anim := 0.0
var _behind := 0.0  # seconds the Bro has been behind him while he fights
var _hunting := false  # dropped in by the boss: roughly knows where the Bro is and goes looking for him, sloppily
var _hunt_delay := 0.0  # idles this long before setting off, so the squad does not arrive together
var _hunt_dir := 0
var _hunt_wander := 0.0  # time until he picks a new way to go
var _hunt_speed := 1.0  # each soldier has his own pace


func _ready() -> void:
	stats = _own_stats()
	eye = GameData.ANCHORS[sheet]["eye"]
	sprite_name = sheet
	super()


func _own_stats() -> Dictionary:
	return GameData.MOOK


func _think(delta: float) -> void:
	_shot_anim -= delta
	if state == State.PATROL:
		if sees_player(facing):
			_spot()
		elif _hunting:
			_hunt_step(delta)
		else:
			patrol_step(delta, stats.walk_speed)
	else:
		_fight(delta)


func _fight(delta: float) -> void:
	velocity.x = 0.0
	if not sees_player(facing) and sees_player(-facing):  # the Bro jumped over him: he takes a moment to notice, turns, and has to react again
		_behind += delta
		if _behind >= stats.turn_delay:
			_behind = 0.0
			facing = -facing
			_spot()
			return
	else:
		_behind = 0.0
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


## Called by the Brute for the soldiers he drops: no patrol - they head for the Bro, but sloppily. Each waits a
## moment, walks at his own pace, now and then stops or wanders the wrong way, so they straggle in one by one.
func hunt(delay := 0.0) -> void:
	_hunting = true
	_hunt_delay = delay
	_hunt_speed = randf_range(0.7, 1.3)


func _hunt_step(delta: float) -> void:
	_hunt_delay -= delta
	_hunt_wander -= delta
	if _hunt_delay > 0.0:
		velocity.x = 0.0
		return
	var p := player()
	if p == null:
		velocity.x = 0.0
		return
	if _hunt_wander <= 0.0:
		_hunt_wander = randf_range(0.5, 1.5)
		var toward := 1 if p.global_position.x >= global_position.x else -1
		var roll := randf()
		_hunt_dir = toward if roll < 0.65 else (0 if roll < 0.82 else -toward)
	if _hunt_dir != 0 and is_on_floor() and not ground_ahead():
		_hunt_dir = 0
	velocity.x = _hunt_dir * stats.walk_speed * _hunt_speed * 1.5
	if _hunt_dir != 0:
		facing = _hunt_dir


func _spot() -> void:
	_behind = 0.0
	state = State.ALERT
	_timer = stats.reaction_time
	_since_seen = 0.0
	velocity.x = 0.0
	show_alert(true)
	Sfx.play(self, "enemy_alert", -6.0)


func _shoot() -> void:
	_shot_anim = 0.12
	_animate()  # switch to the shoot pose first, so the bullet leaves its barrel
	var muzzle := MuzzleFlash.gun_tip(sprite, sheet, facing)
	Bullet.spawn(get_parent(), position + muzzle, facing, GameData.ENEMY_BULLET, "enemy_shot", BULLET_MASK)
	flash.fire(muzzle, facing)
	_shot_anim = 0.12
	Sfx.play(self, "enemy_shoot", -10.0)


## Panicking (disco grenade): fires wherever he happens to face. The bullet hits other enemies too.
func _panic_shoot() -> void:
	_shot_anim = 0.12
	_animate()
	var muzzle := MuzzleFlash.gun_tip(sprite, sheet, facing)
	Bullet.spawn(get_parent(), position + muzzle, facing, GameData.ENEMY_BULLET, "enemy_shot", BULLET_MASK | 4, 0.0, self)
	flash.fire(muzzle, facing)
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
