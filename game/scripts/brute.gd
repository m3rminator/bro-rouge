extends Enemy
## Brute mini-boss: about three blocks tall, two miniguns. Sees far and high, hears the Bro behind
## him, spins up, then sprays long alternating bursts in a wide fan.
## Numbers: design/entities/brute.yaml (GameData.BRUTE). Shared behaviour: enemy.gd.

signal engaged(brute: Node)
signal phase_changed(phase: int)
signal defeated

enum State { PATROL, SPIN, FIRE, PAUSE }

const MUZZLE: Vector2 = GameData.ANCHORS["brute"]["muzzle_top"]  # one minigun at the hip
const BULLET_MASK := 1 | 2  # world + player

@onready var flash: Node = $FlashTop

var state := State.PATROL
var _timer := 0.0
var _shot_timer := 0.0
var _since_seen := 0.0
var gate_x := 0.0  # world x of the arena gate the kamikazes come out of (0 = none: they drop from above)
var _sweat_timer := 0.0  # next drop of sweat while he kneels (sweat_drops.gd)
var _angry := 0.0  # time left of the angry pose after he gets up from a phase change
var _engaged := false
var _phase := 1  # 1, 2, 3 - one per block of his health bar (brute.yaml phases)
var _strike_t := 0.0
var _drop_t := 0.0
var _shield := false  # a phase change is playing out: nothing hurts him
var _shield_time := 0.0
var _barrage_left := 0
var _barrage_t := 0.0
var _dropped: Array = []  # the suicide soldiers he dropped that may still be alive


func _ready() -> void:
	stats = GameData.BRUTE
	eye = GameData.ANCHORS["brute"]["eye"]
	sprite_name = "brute"
	death_sound = "brute_death"
	add_to_group("bosses")
	super()


func fears_grenades() -> bool:
	return false  # a boss stands his ground


func _think(delta: float) -> void:
	_boss_tick(delta)
	if _shield:
		velocity.x = 0.0  # down on one knee: no walking, no shooting
		return
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
				_shot_timer = stats.fire_interval / (stats.rage_fire_mult if _raging() else 1.0)
			if _timer <= 0.0:
				state = State.PAUSE
				_timer = stats.burst_pause


## The level calls this when it starts: he goes for the Bro at once, wherever the Bro is.
func aggro() -> void:
	if not _engaged and not dead:
		_spot()


## The health the current phase ends at: the bar is split into `phases` equal blocks.
func _phase_floor() -> int:
	return int(stats.hp * (stats.phases - _phase) / stats.phases)


## While a phase change plays out (`_shield`) nothing hurts him, and a hit never takes him past the
## end of his current block - it ends exactly on the limit, then the change begins.
func hit(damage: int, direction := 0, at := Vector2.INF, behead := "none") -> void:
	if _shield:
		if not dead:
			Sfx.play(self, "block_hit", -6.0)  # shots just clank off him
		return
	damage = mini(damage, hp - _phase_floor()) if _phase_floor() > 0 else damage
	if damage <= 0:
		return
	super(damage, direction, at, behead)


## The phases: phase 2 begins with him down and calling a barrage of air strikes on the Bro (nothing hurts
## him meanwhile), phase 3 with him down while suicide soldiers drop into the arena (he gets up when they
## are dead). From phase 2 on he also calls a single strike now and then. Nothing happens before he spotted the Bro.
func _boss_tick(delta: float) -> void:
	if not _engaged:
		return
	if _shield:
		_transition_tick(delta)
		return
	if _phase < stats.phases and hp <= _phase_floor():
		_begin_transition()
		return
	if _phase >= 2:
		_strike_t -= delta
		if _strike_t <= 0.0:
			_strike_t = stats.strike_interval
			_call_strike(stats.strike_delay)
	if _phase >= 3:
		_drop_t -= delta
		if _drop_t <= 0.0:
			_drop_t = stats.drop_interval
			_drop_kamikazes()


func _begin_transition() -> void:
	_phase += 1
	_shield = true
	_shield_time = 0.0
	velocity.x = 0.0
	state = State.PATROL
	phase_changed.emit(_phase)
	Sfx.play(self, "brute_alert", -4.0)
	if _phase == 2:
		_barrage_left = randi_range(stats.barrage_min, stats.barrage_max)
		_barrage_t = 1.0
	else:
		_dropped.clear()
		_drop_kamikazes(true)


func _transition_tick(delta: float) -> void:
	_shield_time += delta
	var done := false
	if _phase == 2:  # strikes one after another on wherever the Bro stands
		_barrage_t -= delta
		if _barrage_left > 0 and _barrage_t <= 0.0:
			_barrage_left -= 1
			_barrage_t = stats.barrage_gap
			_call_strike(stats.barrage_delay)
		done = _barrage_left == 0 and _barrage_t <= -stats.barrage_end
	else:  # down until every dropped soldier is dead
		_dropped = _dropped.filter(func(k): return is_instance_valid(k) and not k.dead)
		done = _dropped.is_empty() and _shield_time > 1.5
	if done or _shield_time > stats.transition_timeout:
		_shield = false
		_strike_t = stats.strike_first
		_drop_t = stats.drop_interval
		Sfx.play(self, "minigun_spinup", -6.0)


## One missile on the ground under the Bro; the red zone shows where, he has `delay` seconds to leave it.
func _call_strike(delay: float) -> void:
	var p := player()
	if p == null or p.dead:
		return
	var spot := AirStrike.ground_point(get_world_2d(), p.global_position + Vector2(0, 120))
	AirStrike.call_in(get_parent(), spot, {"bombs": 1, "spread": 0.0, "delay": delay, "warn_radius": stats.strike_radius, "through": true})


## Suicide soldiers land in the middle of the arena, between the Bro and him, and run at the Bro.
## They are extra: no kill credit.
func _drop_kamikazes(force := false) -> void:
	_dropped = _dropped.filter(func(k): return is_instance_valid(k) and not k.dead)
	if _dropped.size() >= stats.drop_max and not force:
		return
	var scene: PackedScene = load("res://scenes/kamikaze.tscn")
	for i in stats.drop_count:
		var x := global_position.x - randf_range(70.0, 260.0)
		if gate_x > 0.0:  # they come in through the arena's far side and run for the Bro
			x = gate_x - i * 14.0
		var spot := AirStrike.ground_point(get_world_2d(), Vector2(x, global_position.y))
		var k: Enemy = scene.instantiate()
		k.counts_kill = false
		k.position = Vector2(x, spot.y - 50.0)  # a short drop (a long one would kill him)
		get_parent().add_child(k)
		k.call("hunt")
		_dropped.append(k)
	var mook_scene: PackedScene = load("res://scenes/mook.tscn")
	for i in stats.drop_soldiers:  # ordinary soldiers come with them, and hunt the Bro in a straggling crowd
		var x := global_position.x - randf_range(70.0, 260.0)
		if gate_x > 0.0:
			x = gate_x - randf_range(0.0, 90.0)
		var spot := AirStrike.ground_point(get_world_2d(), Vector2(x, global_position.y))
		var m: Enemy = mook_scene.instantiate()
		m.counts_kill = false
		m.position = Vector2(x, spot.y - 50.0)
		get_parent().add_child(m)
		m.call("hunt", randf_range(0.0, 4.0))
		_dropped.append(m)
	Sfx.play(self, "grenade_throw", -4.0)


## Phase 3, once he is back on his feet.
func _raging() -> bool:
	return _phase >= 3 and not _shield


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
	var anchor: Vector2 = MUZZLE + sprite.position
	var muzzle := Vector2(anchor.x * facing, anchor.y)
	var half: float = stats.spread_angle / 2.0
	Bullet.spawn(get_parent(), position + muzzle, facing, GameData.MINIGUN_BULLET, "minigun_shot", BULLET_MASK,
			randf_range(-half, half))
	flash.fire(muzzle, facing)


func _on_hurt(_direction: int) -> void:
	if state == State.PATROL:
		_spot()


## He is too big to fall over: slumps on his knees where he stands, shakes, then bursts - blood everywhere
## and a pile of body pieces on the floor around him.
func _on_death(_direction: int) -> void:
	Sfx.play(self, death_sound, -2.0)
	sprite.play("hurt")
	velocity = Vector2.ZERO
	defeated.emit()
	Blood.burst(get_parent(), global_position + Vector2(0, -24))
	Blood.burst(get_parent(), global_position + Vector2(6 * facing, -6))
	_death_throes()


func _death_throes() -> void:
	var shake := 0.9
	while shake > 0.0 and is_inside_tree():  # a trembling that gets wilder
		shake -= get_physics_process_delta_time()
		sprite.offset.x = float(randi_range(-1, 1) * (1 + int(2.0 * (1.0 - shake / 0.9))))  # whole pixels, up to 3
		await get_tree().physics_frame
	if not is_inside_tree():
		return
	sprite.offset = Vector2.ZERO
	var parent := get_parent()
	Sfx.play(self, "blood_splat", 0.0)
	for i in 6:  # a lot of flesh and bone, thrown every which way
		var from := global_position + Vector2(randf_range(-10.0, 10.0), randf_range(-14.0, 4.0))
		BodyPiece.scatter(parent, from, 1 if i % 2 == 0 else -1, from + Vector2(randf_range(-4.0, 4.0), 8.0))
	for i in 3:
		BloodDrops.emit(parent, global_position + Vector2(0, -12), Vector2.UP, 15, 180.0, 260.0)
	Blood.pool_under(self)


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
	$Collision.position.y = Block.SIZE / 2.0 - box.size.y / 2.0


func _animate() -> void:
	_angry = maxf(0.0, _angry - get_physics_process_delta_time())
	sprite.flip_h = facing < 0
	var anim := "idle"
	match state:
		State.SPIN, State.PAUSE:
			anim = "spin"
		State.FIRE:
			anim = "shoot"
		_:
			anim = "walk" if velocity.x != 0.0 else "idle"
	if _angry > 0.0 or (_raging() and anim in ["idle", "walk"]):
		anim = "angry"  # glowing eyes: right after a phase change, and whenever he is not shooting in rage
	if _shield:
		anim = "kneel"  # down on one knee until he gets up
	_sweat_timer -= get_physics_process_delta_time()
	if _shield and not dead and _sweat_timer <= 0.0:
		_sweat_timer = 0.09
		SweatDrops.emit(get_parent(), global_position + Vector2(facing * 4.0, -8.0))
	if sprite.animation != anim:
		sprite.play(anim)
