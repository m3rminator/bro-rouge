extends Enemy
## Suicide bomber. Patrols and spots the Bro like a mook; then screams and sprints at him,
## hopping over walls, and blows up when close. Killed, he still blows up after death_fuse.
## Numbers: design/entities/kamikaze.yaml (GameData.KAMIKAZE). Shared behaviour: enemy.gd.

enum State { PATROL, ALERT, CHARGE }

var state := State.PATROL
var _timer := 0.0
var _fuse := -1.0  # counting down after death; explodes at 0
var _exploded := false


func _ready() -> void:
	stats = GameData.KAMIKAZE
	eye = GameData.ANCHORS["kamikaze"]["eye"]
	sprite_name = "kamikaze"
	super()


func _think(delta: float) -> void:
	match state:
		State.PATROL:
			if sees_player(facing):
				_spot()
			else:
				patrol_step(delta, stats.walk_speed)
		State.ALERT:
			velocity.x = 0.0
			_timer -= delta
			if _timer <= 0.0:
				state = State.CHARGE
				show_alert(false)
		State.CHARGE:
			_charge()


func _spot() -> void:
	state = State.ALERT
	_timer = stats.reaction_time
	velocity.x = 0.0
	show_alert(true)
	Sfx.play(self, "kamikaze_scream", -4.0)


func _charge() -> void:
	var p := player()
	if p == null or global_position.distance_to(p.global_position) > stats.chase_range:
		state = State.PATROL
		return
	if global_position.distance_to(p.global_position) < stats.trigger_range:
		_explode()
		return
	var dx: float = p.global_position.x - global_position.x
	if absf(dx) > 2.0:
		facing = 1 if dx > 0 else -1
	velocity.x = facing * stats.run_speed
	if is_on_floor() and is_on_wall():
		velocity.y = stats.jump_velocity


func _on_hurt(_direction: int) -> void:
	if state == State.PATROL:
		_spot()


func _on_death(direction: int) -> void:
	if _exploded:
		return
	Sfx.play(self, death_sound, -4.0)
	sprite.play("hurt")
	var push := direction if direction != 0 else -facing
	velocity = Vector2(push * 60.0, -100.0)
	_fuse = stats.death_fuse


func _dead_process(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
	move_and_slide()
	if _fuse > 0.0:
		_fuse -= delta
		if _fuse <= 0.0:
			_explode()


## Vest goes off: blast where he stands, nothing left but blood.
func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	if not dead:
		die(0)
	var power := {"radius": stats.blast_radius, "damage": stats.blast_damage, "player_damage": stats.blast_player_damage}
	Explosion.detonate(get_parent(), global_position, power, [global_position])
	Blood.burst(get_parent(), global_position)
	Blood.pool_under(self)
	queue_free()


func _animate() -> void:
	sprite.flip_h = facing < 0
	var anim := "idle"
	if not is_on_floor():
		anim = "fall"
	elif state == State.CHARGE:
		anim = "run"
	elif velocity.x != 0.0:
		anim = "walk"
	if sprite.animation != anim:
		sprite.play(anim)
