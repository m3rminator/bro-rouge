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
const CROWD_REACH := 40.0  # soldiers this close ahead count as standing together

@onready var sprite: AnimatedSprite2D = $Sprite

var stats: Dictionary
var eye := Vector2.ZERO  # eye anchor relative to the body origin (facing right)
var sprite_name := ""  # art/sprites/<name>.yaml — places the frame so the feet are on the tile bottom
var facing := -1
var hp := 1
var dead := false
var death_sound := "enemy_death"
var _pause := 0.0
var _crowd_next := 0  # when to look for a crowd ahead again (ms)
var _crowded := false
var _pooled := false
var _air_top := INF  # highest point (smallest y) of the current time in the air; INF while on the ground
var _pool_x := INF  # where the last pool was left (a new one only after the body moved)
var _bubble: AnimatedSprite2D
var _lying := false
var _idle := 0.0  # seconds the corpse has lain untouched; past rest_time it sinks and fades away
var _shots_taken := 0  # bullets this body has absorbed; it bursts at CORPSE.burst_hits
var _bumped := false  # the Bro is walking through this body right now
var _dead_anim := "dead"  # lying pose; sprites with two (dead_a / dead_b) get one at random per body
var counts_kill := true  # false for soldiers dropped in by the boss: they are extra, the quota does not count them
var tears_apart := true  # a blast rips the body into pieces (BodyPiece); kamikazes keep theirs for the fuse
var _punched := 0.0  # share of his health Bruce's blows have taken (a full 1.0 kills); forgotten after 3 s
var _punch_at := -100.0
var _stab_hits := 0  # knife hits taken that did not kill (a slower knife needs knife_hits of them)
var _shoved := 0.0  # > 0 while sliding back from a knife hit he survived (no AI meanwhile)
var _stunned := 0.0  # > 0 while stunned by a melee hit (design/entities/stun.yaml): blinks white, birds over the head
var _stun_birds: AnimatedSprite2D
var _headless := false  # his head was blown off (Head): headless poses, blood fountain from the neck
var _fountain: CPUParticles2D
var _fountain_left := 0.0
var _fountain_drip := 0.0
var _fountain_side := 1  # which way the neck points in the unrotated sprite
var _grenade_seen := 0.0  # how long a live grenade has been in sight (he panics at GRENADE.flee_reaction)
var _grenade_calm := {}  # grenade instance id -> true if he ignores that grenade (rolled once)
var _grenade_late := {}  # grenades he only noticed in the last second
var _fleeing: Node2D = null  # the grenade he is running from
var _disco: Node2D = null  # a landed disco grenade he is walking toward (design/entities/disco.yaml)
var _panic := 0.0  # > 0 while panicking after the disco burst: jumps about, runs back and forth, shoots wildly
var _panic_turn := 0.0
var _panic_dir := 0
var _panic_shot := 0.0
var _doomed := false  # the disco party ends him: when the panic is over he bursts (a lone soldier, or a kamikaze: he blows up)
var _died_at := -100.0  # when he died (seconds), for the short spell after it that bullets pass through him
var party_doom := false  # set by kinds that always go off when the panic ends (kamikaze)


func _ready() -> void:
	add_to_group("enemies")
	z_index = 2
	hp = stats.hp
	if not get_script().resource_path.ends_with("brute.gd"):
		hp = ceili(hp * (1.0 + GameData.RUN.enemy_hp_per_loop * (Run.loop - 1)))  # tougher every boss loop
	if sprite_name != "":
		sprite.position.y = Block.SIZE / 2.0 - GameData.SPRITE_SIZES[sprite_name].y / 2.0
		eye += Vector2(0, sprite.position.y)
	$Collision.shape = $Collision.shape.duplicate()  # every body gets its own box (it changes when he dies)
	var box: RectangleShape2D = $Collision.shape
	box.size = Vector2(stats.hitbox[0], stats.hitbox[1])
	$Collision.position.y = Block.SIZE / 2.0 - stats.hitbox[1] / 2.0  # feet on the bottom of the start tile
	_bubble = AnimatedSprite2D.new()
	_bubble.sprite_frames = FX_FRAMES
	_bubble.animation = "alert"
	_bubble.position = Vector2(0, 2 - stats.hitbox[1] - 6)
	_bubble.visible = false
	add_child(_bubble)


static var _hero: Node2D
static var _hero_frame := -1
static var _wake_range := 760.0


## True while the Bro is far away: the enemy just stands there (no thinking, no physics), which saves a lot on a long level.
func _asleep() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _hero_frame:
		_hero_frame = frame
		_hero = get_tree().get_first_node_in_group("player")
		_wake_range = Quality.p("enemy_range")
	if _hero == null or is_in_group("bosses"):
		return false
	var d := global_position - _hero.global_position
	return absf(d.x) > _wake_range or absf(d.y) > 560.0


func _physics_process(delta: float) -> void:
	if not dead and _asleep():
		return
	if _stunned > 0.0:
		_update_stun(delta)
	if not is_on_floor():
		velocity.y += stats.gravity * delta
	if dead:
		_dead_process(delta)
		return
	if _shoved > 0.0:
		_shoved -= delta
		velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
		move_and_slide()
		_check_fall()
		_animate()
		return
	if _panic > 0.0:
		_panic_step(delta)
	elif _disco != null and _disco_step(delta):
		pass
	elif not _flee(delta):
		_think(delta)
	move_and_slide()
	_check_fall()
	_animate()


## A raygun shockwave from `from_x`: thrown away from it and stunned (bosses are never thrown).
func wave_hit(from_x: float, speed: float, up: float, stun_time: float) -> void:
	if dead or is_in_group("bosses"):
		return
	var away := signf(global_position.x - from_x)
	if away == 0.0:
		away = float(-facing)
	_disco = null
	_panic = 0.0
	_doomed = false
	velocity = Vector2(away * speed, -up)
	_shoved = stun_time
	_stun(stun_time)
	show_alert(false)


## A landed disco grenade calls him: he walks to it until it goes off (bosses ignore it).
func disco_lure(spot: Node2D) -> void:
	if dead or _panic > 0.0 or _shoved > 0.0 or is_in_group("bosses"):
		return
	_disco = spot
	show_alert(false)


func is_lured_by(spot: Node2D) -> bool:
	return _disco == spot


## The disco burst: panic for `time` seconds. `lone`: nobody else is there to finish him, so the party does.
func disco_panic(time: float, lone := false) -> void:
	if dead or is_in_group("bosses"):
		return
	_disco = null
	_doomed = lone or party_doom
	_panic = time
	_panic_turn = 0.0
	_panic_shot = randf_range(0.1, 0.4)
	show_alert(false)


func _disco_step(delta: float) -> bool:
	if not is_instance_valid(_disco):
		_disco = null
		return false
	var dx := _disco.global_position.x - global_position.x
	if absf(dx) > 20.0:
		facing = 1 if dx > 0.0 else -1
		velocity.x = facing * float(stats.get("walk_speed", 30.0)) * 1.8
		if is_on_floor() and is_on_wall():
			velocity.y = -230.0
	else:
		velocity.x = 0.0
		if is_on_floor() and randf() < delta * 2.0:
			velocity.y = -110.0  # a little dance
	return true


func _panic_step(delta: float) -> void:
	var disco: Dictionary = GameData.DISCO
	_panic -= delta
	if _panic <= 0.0 and _doomed:
		_doomed = false
		_party_over()
		return
	_panic_turn -= delta
	if _panic_turn <= 0.0:
		_panic_turn = randf_range(disco.panic_turn[0], disco.panic_turn[1])
		_panic_dir = [-1, 0, 1][randi() % 3]
		facing = [-1, 1][randi() % 2]
	velocity.x = _panic_dir * disco.panic_speed
	if is_on_floor():
		if randf() < disco.panic_jump_rate * delta or (is_on_wall() and _panic_dir != 0):
			velocity.y = -disco.panic_jump
		if is_on_wall():
			_panic_dir = -_panic_dir
	_panic_shot -= delta
	if _panic_shot <= 0.0:
		_panic_shot = randf_range(disco.panic_shot[0], disco.panic_shot[1])
		_panic_shoot()


## The panic ended with him still alive and doomed: he dies and bursts on the spot (a kamikaze goes off).
func _party_over() -> void:
	if dead:
		return
	die(0)
	_burst_body(facing)


## Wild shot while panicking (soldiers override this).
func _panic_shoot() -> void:
	pass


## Landing after a long drop kills (stats.fall_death_height; 0 = immune). Measured from the
## top of the flight, so being blown high into the air counts too.
func _check_fall() -> void:
	if is_on_floor():
		var fell := global_position.y - _air_top
		_air_top = INF
		var limit: float = stats.get("fall_death_height", 0.0)
		if limit > 0.0 and fell >= limit - 1.0:  # a drop of exactly the limit counts
			_fall_death()
	else:
		_air_top = minf(_air_top, global_position.y)


## Splattered by the landing: dies and bursts into gore on the spot, like a shot body.
func _fall_death() -> void:
	if not dead:
		die(0)
	_burst_body()


## A live grenade in sight and close: after flee_reaction he panics and runs away from it
## until it is gone. Returns true while fleeing (the normal AI is skipped).
func _flee(delta: float) -> bool:
	if not fears_grenades():
		return false
	if _fleeing != null and not is_instance_valid(_fleeing):
		_fleeing = null
	if _fleeing == null:
		var g := _grenade_in_sight()
		if g != null and not _grenade_calm.has(g.get_instance_id()):
			var panics := randf() < GameData.GRENADE.notice_chance * GameData.GRENADE.flee_chance
			_grenade_calm[g.get_instance_id()] = not panics
		if g != null and _grenade_calm[g.get_instance_id()]:
			if g._fuse <= GameData.GRENADE.last_notice and not _grenade_late.has(g.get_instance_id()):
				_grenade_late[g.get_instance_id()] = true  # the last second: he finally sees it - too late to run
				show_alert(true)
				Sfx.play(self, "enemy_alert", -6.0)
				get_tree().create_timer(GameData.GRENADE.last_notice + 0.2).timeout.connect(show_alert.bind(false))
			g = null  # he did not notice it, or does not care
		if g == null:
			_grenade_seen = 0.0
			return false
		_grenade_seen += delta
		if _grenade_seen < GameData.GRENADE.flee_reaction:
			return false
		_fleeing = g
		_grenade_seen = 0.0
		Sfx.play(self, "enemy_panic", -4.0, 0.1)
	var away := signf(global_position.x - _fleeing.global_position.x)
	facing = int(away) if away != 0.0 else facing
	velocity.x = facing * GameData.GRENADE.flee_speed
	if is_on_wall():
		velocity.x = 0.0  # cornered
	return true


## Enemies that run from grenades (the Brute does not).
func fears_grenades() -> bool:
	return true


func _grenade_in_sight() -> Node2D:
	var eye_pos := global_position + Vector2(eye.x * facing, eye.y)
	for g in get_tree().get_nodes_in_group("grenades"):
		if g.global_position.distance_to(global_position) <= GameData.GRENADE.flee_range and ray(eye_pos, g.global_position).is_empty():
			return g
	return null


## AI step for living enemies — set velocity here. Overridden by every enemy.
func _think(_delta: float) -> void:
	pass


func _animate() -> void:
	pass


func _dead_process(delta: float) -> void:
	var pieces: Dictionary = GameData.BODY_PIECES
	if _idle > pieces.rest_time:  # nobody touched it: sinks into the ground and fades
		_idle += delta
		var left: float = pieces.rest_time + pieces.fade_time - _idle
		if left <= 0.0:
			queue_free()
			return
		$Collision.disabled = true
		z_index = -1
		sprite.modulate.a = left / pieces.fade_time
		sprite.position.y += pieces.sink_speed * delta
		return
	_bump(delta)
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, CORPSE.friction * delta)
	move_and_slide()
	_check_fall()
	if is_on_floor() and not _lying and velocity.y >= 0.0:
		_lie()
	_idle = _idle + delta if _lying and is_on_floor() and absf(velocity.x) < 8.0 and not _bumped else 0.0
	if is_on_floor() and not _pooled and absf(velocity.x) < 20.0:
		_pooled = true
		if absf(global_position.x - _pool_x) > 12.0:
			_pool_x = global_position.x
			Blood.pool_under(self)
	if _fountain_left > 0.0:
		_pump_fountain(delta)


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
				_pooled = false  # stays in the lying pose; leaves another pool where it stops
			elif is_on_floor():
				velocity.x = move_toward(velocity.x, p.velocity.x * CORPSE.drag / mass, 600.0 * delta)
	_bumped = touching


## Body leaves the ground: flailing pose (a headless body keeps its headless pose).
func _fly() -> void:
	_lying = false
	_pooled = false  # leaves another pool where it lands
	var anim := _dead_anim if _headless else "hurt"
	sprite.play(anim)
	sprite.rotation = 0.0
	sprite.position = Vector2(0, Block.SIZE / 2.0 - sprite.sprite_frames.get_frame_texture(anim, 0).get_height() / 2.0)


## Body on the ground: its lying pose (drawn in the sprite, picked at death) and a low,
## wide collision box that the Bro's bullets can still hit.
func _lie() -> void:
	_lying = true
	sprite.play(_dead_anim)
	sprite.rotation = 0.0
	sprite.position = Vector2(0, Block.SIZE / 2.0 - GameData.SPRITE_SIZES[sprite_name].y / 2.0)
	var box: RectangleShape2D = $Collision.shape
	box.size = Vector2(stats.hitbox[1] * 0.8, CORPSE.lying_height)
	$Collision.position.y = Block.SIZE / 2.0 - CORPSE.lying_height / 2.0


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
	if is_on_floor() and (is_on_wall() or not ground_ahead() or crowd_ahead(facing)):
		facing = -facing
		_pause = stats.turn_pause
		velocity.x = 0.0
		return
	velocity.x = facing * speed


## True when two or more other soldiers already stand just ahead of him on his level (looked at a few times a second): a
## third would make a crowd of more than three, so he turns away instead of joining them.
func crowd_ahead(dir: int) -> bool:
	var now := Time.get_ticks_msec()
	if now >= _crowd_next:
		_crowd_next = now + 250
		var count := 0
		for e in get_tree().get_nodes_in_group("enemies"):
			if e == self or e.dead:
				continue
			var d: Vector2 = e.global_position - global_position
			if absf(d.y) < 20.0 and d.x * dir > 0.0 and absf(d.x) < CROWD_REACH:
				count += 1
		_crowded = count >= 2
	return _crowded


func ground_ahead() -> bool:
	var foot := global_position + Vector2(facing * (stats.hitbox[0] / 2.0 + 2.0), 4)
	return not ray(foot, foot + Vector2(0, 12)).is_empty()


func ray(from: Vector2, to: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, WORLD_MASK)
	return get_world_2d().direct_space_state.intersect_ray(query)


## Stunned for `time` seconds: the sprite blinks white and birds circle over his head.
func _stun(time: float) -> void:
	_stunned = time
	if _stun_birds == null:
		_stun_birds = AnimatedSprite2D.new()
		_stun_birds.sprite_frames = load("res://assets/sprites/stun_frames.tres")
		_stun_birds.position = Vector2(0, Block.SIZE / 2.0 - stats.hitbox[1] - GameData.STUN.birds_above_head)
		_stun_birds.z_index = 1
		add_child(_stun_birds)
	_stun_birds.visible = true
	_stun_birds.play("circle")


func _update_stun(delta: float) -> void:
	_stunned -= delta
	if _stunned <= 0.0 or dead:
		_stunned = 0.0
		sprite.modulate = Color.WHITE
		_stun_birds.visible = false
		_stun_birds.stop()
		return
	var bright := int(_stunned / GameData.STUN.blink_interval) % 2 == 0
	sprite.modulate = Color(3, 3, 3) if bright else Color.WHITE


func show_alert(on: bool) -> void:
	_bubble.visible = on


## Called by bullets. `direction` = which way the bullet was flying. A body is knocked back.
## `at` = where the bullet struck; `behead` = the bullet's power to blow the head off
## ("headshot": a hit on the head kills and beheads, "always": any killing hit beheads).
func hit(damage: int, direction := 0, at := Vector2.INF, behead := "none") -> void:
	if dead:
		_shot_body(direction)
		return
	var off_head := can_behead() and (behead == "always" or (behead == "headshot" and _on_head(at)))
	if off_head and behead == "headshot":
		damage = maxi(damage, hp)  # a shot to the head kills
	hp -= damage
	health_changed.emit(maxi(hp, 0), stats.hp)
	Blood.spray(get_parent(), global_position + Vector2(0, 6 - stats.hitbox[1] / 2.0), direction if direction != 0 else -facing)
	if direction == facing:  # shot from behind: turn to face the shooter
		facing = -facing
	sprite.modulate = Color(3, 3, 3)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.08)
	if hp <= 0:
		die(direction)
		if off_head:
			_behead(direction if direction != 0 else -facing)
	else:
		_on_hurt(direction)


## Called by explosions (explosion.gd). Living enemies take blast damage; bodies get tossed.
func on_blast(center: Vector2, power: Dictionary) -> void:
	var dir := 1 if global_position.x >= center.x else -1
	var was_alive := not dead
	if not dead:
		hit(power.damage, dir)
	if dead:
		if was_alive and can_behead():  # killed by the blast: his head is blown off
			_behead(dir)
		if tears_apart and not is_in_group("bosses"):  # and the rest of him is torn to pieces
			BodyPiece.tear(self, dir, center)
			return
		toss(dir, GameData.EXPLOSION.fling_speed)


func toss(dir: int, speed: float) -> void:
	velocity = Vector2(dir * speed * 0.5, -speed)
	_fly()
	create_tween().tween_property(sprite, "rotation", TAU * dir, 0.6)


## How many knife hits it takes to kill him: `base` (the Bro's knife_hits) only for a soldier still wearing
## both helmet and vest (helmet.gd); everyone else needs `plain` (knife_hits_plain: 1 for most Bros, 2 for Balal and Hamid - the first stuns).
func knife_hits_needed(_base: int, plain := 1) -> int:
	return plain


## The Bro's knife (player.gd). Every enemy but a boss dies from one hit; a boss takes
## `boss_damage`. The knifed enemy (or body) is thrown back hard, and a kill sprays `blood`
## extra drops. Returns true if this hit killed him.
func stab(direction: int, boss_damage: int, knockback: float, hop: float, blood: int, hits_needed := 1, stun := 0.0, plain_hits := 1) -> bool:
	var mass: float = stats.get("mass", 1.0)
	var throw := Vector2(direction * knockback / mass, hop / mass)
	var chest := global_position + Vector2(0, Block.SIZE / 2.0 - stats.hitbox[1] * 0.6)
	if dead:  # stabbing a body bursts it at once, like the last bullet would
		Blood.spray(get_parent(), chest, direction)
		if not dead:
			die(0)
		_burst_body(direction)
		return false
	hits_needed = knife_hits_needed(hits_needed, plain_hits)
	if hits_needed > 1 and not is_in_group("bosses"):
		_stab_hits += 1
		if _stab_hits < hits_needed:  # not dead yet: thrown back and stunned, standing there helpless
			Blood.spray(get_parent(), chest, direction)
			velocity = throw
			_shoved = stun
			show_alert(false)
			_stun(stun)
			return false
	hit(boss_damage if is_in_group("bosses") else hp, direction)
	if dead:
		Blood.knife_kill(get_parent(), chest, direction, blood)
		velocity = throw  # harder than the bullet-kill push _on_death gave
		return true
	velocity.x = throw.x * 0.5  # a boss survives: shoved back a little
	_shoved = 0.25
	return false


## One of Bruce's blows (player.gd). An ordinary enemy takes `share` of his health and dies when the shares add up to
## all of it; a boss takes `boss_damage`. The blow shoves him back (`knock`, `hop`) and a kick that does not kill stuns
## him. Returns true if this blow killed him.
func punched(share: float, boss_damage: int, direction: int, knock: float, hop: float, stun_time: float) -> bool:
	if dead:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if now - _punch_at > 3.0:
		_punched = 0.0
	_punch_at = now
	var mass: float = stats.get("mass", 1.0)
	var chest := global_position + Vector2(0, Block.SIZE / 2.0 - stats.hitbox[1] * 0.6)
	if is_in_group("bosses"):
		hit(boss_damage, direction)
		if not dead:
			velocity.x = direction * knock * 0.2 / mass
			_shoved = 0.12
		return dead
	_punched += share
	if _punched >= 0.999:
		hit(hp, direction)
		if dead:
			Blood.knife_kill(get_parent(), chest, direction, 20)
			velocity = Vector2(direction * knock / mass, hop / mass)
		return dead
	hit(0, direction)  # blood and the white flash, no damage of its own
	velocity = Vector2(direction * knock / mass, hop / mass)
	_shoved = maxf(0.12, stun_time)
	if stun_time > 0.0:
		_stun(stun_time)
	return false


func _shot_body(direction: int) -> void:
	var dir := direction if direction != 0 else 1
	var mass: float = stats.get("mass", 1.0)
	Blood.spray(get_parent(), global_position + Vector2(0, 2), dir)
	velocity = Vector2(dir * CORPSE.shot_knockback / mass, CORPSE.shot_hop / mass)
	_fly()
	_shots_taken += 1
	if _shots_taken >= CORPSE.burst_hits:
		_burst_body(dir)


## Shot to pieces: bursts into gore (no blast), leaving only blood.
func _burst_body(dir := 0) -> void:
	if tears_apart and not is_in_group("bosses"):  # torn into pieces, like a blast would
		BodyPiece.tear(self, dir if dir != 0 else facing, global_position - Vector2(dir * 6.0, 0.0))
		return
	Blood.gore(get_parent(), global_position)
	Sfx.play(self, "blood_splat", 0.0)
	Blood.pool_under(self)
	queue_free()


## Sprites drawn with headless poses (headless_a / headless_b, head_a / head_b) can lose their head.
func can_behead() -> bool:
	return sprite.sprite_frames.has_animation("headless_a")


## True if the point `at` is on his head (the top head_height px of his standing box).
func _on_head(at: Vector2) -> bool:
	if at == Vector2.INF or dead:
		return false
	var top: float = global_position.y + Block.SIZE / 2.0 - stats.hitbox[1]
	return at.y < top + stats.get("head_height", 0.0)


## Head blown off: the head flies away on its own (Head), the body switches to the matching
## headless pose and blood pumps out of the neck for a few seconds.
func _behead(dir: int) -> void:
	if _headless:
		return
	_headless = true
	var pose := "a" if _dead_anim == "dead_a" else "b"
	_dead_anim = "headless_" + pose
	var head_h: float = stats.get("head_height", 8.0)
	var neck := position + Vector2(0, Block.SIZE / 2.0 - stats.hitbox[1] + head_h / 2.0)
	Head.throw(get_parent(), neck, "head_" + pose, dir, sprite.flip_h, sprite.sprite_frames)
	Blood.spray(get_parent(), neck, dir)
	if _lying:
		_lie()
	else:
		_fly()
	_fountain_side = -1 if sprite.flip_h else 1
	_fountain = CPUParticles2D.new()
	_fountain.position = Vector2(CORPSE.neck[0] * _fountain_side, CORPSE.neck[1])
	_fountain.amount = Quality.n(45)
	_fountain.lifetime = 0.9
	_fountain.local_coords = false
	_fountain.direction = Vector2(_fountain_side, -0.8)
	_fountain.spread = 18.0
	_fountain.gravity = Vector2(0, 420)
	_fountain.scale_amount_min = 1.0
	_fountain.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	ramp.colors = PackedColorArray([Blood.COLORS[0], Blood.COLORS[1], Color(Blood.COLORS[2], 0.0)])
	_fountain.color_ramp = ramp
	_fountain.z_index = -2  # behind the blocks (the body is z 1): the ground hides drops falling past it
	sprite.add_child(_fountain)  # child of the sprite: it turns with the body while it flies
	_fountain.emitting = true
	_fountain_left = CORPSE.fountain_time


## The neck pumps in heartbeats, weaker and weaker; real drops fall and stain the ground.
func _pump_fountain(delta: float) -> void:
	_fountain_left -= delta
	var strength: float = clampf(_fountain_left / CORPSE.fountain_time, 0.0, 1.0)
	var beat := 0.55 + 0.45 * absf(sin(_fountain_left * CORPSE.fountain_beat * PI))
	_fountain.initial_velocity_min = CORPSE.fountain_speed * 0.4 * strength * beat
	_fountain.initial_velocity_max = CORPSE.fountain_speed * strength * beat
	_fountain.emitting = _fountain_left > 0.0
	_fountain_drip -= delta
	if _fountain_drip <= 0.0 and _fountain_left > 0.0:
		_fountain_drip = 0.1
		var dir := Vector2(_fountain_side, -0.8).rotated(sprite.rotation)
		BloodDrops.emit(get_parent(), _fountain.global_position, dir, CORPSE.fountain_drops, 18.0, CORPSE.fountain_speed * strength * beat)


## The first moments after death the body cannot be shot (CORPSE.ghost_time): bullets fly through it.
func is_ghost() -> bool:
	return dead and Time.get_ticks_msec() / 1000.0 - _died_at < GameData.CORPSE.ghost_time


func die(direction: int) -> void:
	dead = true
	_died_at = Time.get_ticks_msec() / 1000.0
	if sprite.sprite_frames.has_animation("dead_b"):
		_dead_anim = "dead_a" if randi() % 2 == 0 else "dead_b"  # 50 / 50
	collision_layer = CORPSE_LAYER
	z_index = 1
	show_alert(false)
	if counts_kill:
		Run.add_kill()
	get_tree().call_group("enemies", "hear_death", global_position)
	Blood.burst(get_parent(), global_position + Vector2(0, Block.SIZE / 2.0 - stats.hitbox[1] / 2.0))
	Sfx.play(self, "blood_splat", -6.0)
	_on_death(direction)


## Another soldier died at `at` (soldiers override this to go and look).
func hear_death(_at: Vector2) -> void:
	pass


func _on_hurt(_direction: int) -> void:
	pass


## Default death: knocked back flailing, then lies flat where it lands; the body stays.
func _on_death(direction: int) -> void:
	Sfx.play(self, death_sound, -4.0)
	var push := direction if direction != 0 else -facing
	velocity = Vector2(push * 80.0, -140.0)
	_fly()
